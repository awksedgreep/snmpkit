# Concurrent Multi (High-Throughput Multi-Target)

`get_multi/2`, `get_bulk_multi/2`, `walk_multi/2` and `walk_table_multi/2` on
`SnmpKit.SNMP` (and their `SnmpKit` shortcuts) execute every request
concurrently. They are implemented by `SnmpKit.SnmpMgr.Multi` on top of
`SnmpKit.SnmpMgr.Engine`, which owns one UDP socket with a large receive
buffer and correlates responses by request id. There is no per-request
process and no GenServer in the send path, which is what lets a single node
poll thousands of devices per second.

## Setup

None. The request-id generator and the engine are started on demand by the
first multi-target call (`auto_start_services: true`, the default). Set it to
`false` and start `SnmpKit.SnmpMgr.Engine` yourself if you want control over
the socket options; multi-target calls then return
`{:error, :services_not_started}` until it is running.

## Requests

A request is `{target, oid}` or `{target, oid, opts}`. Per-request options
override the call-level options for that request only:

```elixir
requests = [
  {"10.0.0.1", "sysDescr.0"},
  {"10.0.0.2:1161", "sysDescr.0", community: "lab", timeout: 2_000},
  {"core-1", "ifTable"}
]
```

Targets accept the same forms as single-target calls: hostnames, IPs,
`"host:port"`, or a map with `:host` and `:port`.

## Results and return formats

Results come back in request order, one entry per request, each `{:ok, value}`
or `{:error, reason}`. The value is a list of enriched varbind maps even for a
GET, so a successful `get_multi` entry looks like `{:ok, [%{value: ...}]}`.

| `return_format:` | Shape |
|------------------|-------|
| `:list` (default) | `[{:ok, ...}, {:error, ...}]` in request order |
| `:with_targets` | `[{target, oid, result}, ...]` |
| `:map` | `%{{target, oid} => result}` |

## Defaults

| Option | Default | Notes |
|--------|---------|-------|
| `version:` | `:v2c` | GETBULK needs v2c; pass `version: :v1` for v1-only agents |
| `max_concurrent:` | 10 | requests in flight at once; raise it for large fleets |
| `timeout:` | 10 000 ms | per PDU, the default for requests without their own |
| `retries:` | from config | per PDU |
| `walk_timeout:` | 20 min | whole-walk cap for `walk_multi` / `walk_table_multi`, never above 30 min |
| `max_repetitions:` | walk default | never capped by the library; tune it to your network |

Walks keep one GETBULK in flight per target and stop on end-of-MIB view, on
leaving the requested subtree, or when `walk_timeout` expires.

## Practical guidance

- Choose `return_format:` by how you consume results: `:map` for lookups,
  `:list` for iteration alongside the request list.
- Turn off `include_names` and `include_formatted` on hot paths.
- Batch very large fleets into calls of a few thousand requests and keep
  `max_concurrent` in line with what the devices and links can absorb; the
  [high performance livebook](../livebooks/05_high_performance.livemd) has a
  table of starting points.
- Timeouts are per PDU, so a slow walk fails one bulk request at a time. See
  [TIMEOUT_DOCUMENTATION.md](../TIMEOUT_DOCUMENTATION.md).
