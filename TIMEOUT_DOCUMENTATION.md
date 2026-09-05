# SnmpKit Timeout Documentation

SnmpKit separates the time allowed for one packet exchange from the time
allowed for a whole walk:

1. **PDU timeout** (`timeout:`) - how long to wait for the response to one
   SNMP packet, retried `retries:` times.
2. **Walk timeout** (`walk_timeout:`) - the cap on an entire walk, however
   many packets it takes.

## PDU timeout (`timeout:`)

Applies to every individual request: a GET, a SET, or each GETNEXT/GETBULK
inside a walk.

| Call | Default |
|------|---------|
| Single-target `get`, `set`, `get_bulk`, ... | 5 000 ms (`config :snmpkit, timeout:`) |
| Single-target walks (`walk`, `bulk_walk`, `walk_table`) | 30 000 ms per PDU |
| Multi-target calls (`get_multi`, `walk_multi`, ...) | 10 000 ms per PDU, unless the request carries its own |

```elixir
# One GET, 5-second timeout
SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0", timeout: 5_000)

# Each GETBULK of this walk may take 15 seconds
SnmpKit.SNMP.walk("192.168.1.1", "ifTable", timeout: 15_000)
```

## Retries (`retries:`)

`retries:` is the number of additional attempts after a PDU timeout, so
`timeout: 10_000, retries: 2` can wait about 30 seconds for one PDU before
returning `{:error, :timeout}`. Retries are per PDU, never per walk: a walk
that sends 100 GETBULKs gives each one its own timeout and retry budget. The
default is 1 (`config :snmpkit, retries:`).

## Walk timeout (`walk_timeout:`)

Walks send as many GETBULK/GETNEXT packets as the subtree needs. The walk
timeout bounds the whole operation so a device that keeps answering slowly,
or a loop in a broken agent, cannot hang a caller forever.

- Default 20 minutes, which is enough for very large routing tables.
- Any user value above 30 minutes is clamped to 30 minutes.
- When it expires the walk returns `{:error, :timeout}` (the rows already
  received are discarded, as with any failed walk).

```
Root OID: 1.3.6.1.2.1.2.2.1 (ifTable), 50 interfaces, per-PDU timeout 10 s

GETBULK 1 -> rows 1-30     (10 s budget, answered in 40 ms)
GETBULK 2 -> rows 31-60    (10 s budget, answered in 35 ms)
...
whole walk: bounded by walk_timeout
```

## Per-request overrides in multi-target calls

The call-level `timeout:` is the default; a third tuple element overrides it
for one request:

```elixir
SnmpKit.SNMP.walk_multi(
  [
    {"fast-switch", "ifTable", timeout: 5_000},
    {"slow-router", "ifTable", timeout: 30_000, walk_timeout: 600_000},
    {"normal-device", "ifTable"}
  ],
  timeout: 15_000
)
```

## Choosing values

| Situation | Suggestion |
|-----------|------------|
| Fast LAN, fail fast | `timeout: 3_000` |
| Slow WAN links | `timeout: 30_000` |
| Large tables on busy devices | `timeout: 45_000`, keep `walk_timeout` at its default |
| Mixed fleet | call-level default plus per-request overrides |

## Errors

| Result | Meaning |
|--------|---------|
| `{:error, :timeout}` | a PDU (after retries) or the whole walk timed out |
| `{:error, :hostname_resolution_failed}` | the target name did not resolve |
| `{:error, {:network_error, reason}}` | a socket-level failure |

## Troubleshooting

- **Everything times out**: raise `timeout:` for that device, and check the
  community string; many agents silently drop requests with a bad community.
- **Large walks fail**: decide whether one PDU is timing out (raise `timeout:`
  or lower `max_repetitions:`) or the walk as a whole is (raise
  `walk_timeout:` or walk a narrower subtree).
- **Mixed performance in one call**: use per-request overrides rather than
  raising the call-level default for everyone.

## API summary

- `SnmpKit.SNMP.get/3`, `set/4`, `get_bulk/3`: `timeout:` and `retries:` per PDU.
- `SnmpKit.SNMP.walk/3` and friends: `timeout:` per PDU, `walk_timeout:` for the walk.
- `SnmpKit.SNMP.get_multi/2`, `walk_multi/2`, ...: call-level defaults plus
  `{target, oid, opts}` overrides.
- Non-positive values fall back to the call default.
