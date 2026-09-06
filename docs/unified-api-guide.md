# SnmpKit Unified API Guide

SnmpKit groups its functionality into a few context modules. This guide walks
through each of them with the exact shapes the functions return.

> Coming from 1.x? The breaking changes are summarised at the top of the
> [README](../README.md#breaking-changes-in-20) and detailed in the
> [migration guide](v2-migration.md).

| Module | Purpose |
|--------|---------|
| `SnmpKit.SNMP` | Manager operations: get, set, walks, bulk, tables, streams, async, multi-target, pretty output |
| `SnmpKit.MIB` | Name and OID resolution, tree navigation, compiling and loading MIBs |
| `SnmpKit.Sim` | Simulated devices for tests and development |
| `SnmpKit.SnmpSim` | Configuration-driven simulation of whole device groups |
| `SnmpKit` | Shortcuts (`get`, `walk`, `get_bulk`, `get_multi`, `resolve`, ...) that delegate to the modules above |

Every example below can be run against a simulated device:

```elixir
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
{:ok, _} = SnmpKit.Sim.start_device(profile, port: 1161)
target = "127.0.0.1:1161"
```

## SNMP operations

### Targets and options

A target is a hostname, an IP address, `"host:port"`, or a map with `:host`
and `:port`. Options common to every call:

| Option | Default | Notes |
|--------|---------|-------|
| `community:` | `"public"` | |
| `version:` | `:v2c` | `:v1`, `:v2c` or `:v3` |
| `timeout:` | 5 000 ms | per PDU; walks default to 30 000 ms |
| `retries:` | 1 | per PDU |
| `port:` | 161 | overrides the port in the target |
| `include_names:` | `true` | reverse-lookup names into `:name` |
| `include_formatted:` | `true` | human-readable `:formatted` values |

Defaults come from `config :snmpkit` and can be changed at runtime with
`SnmpKit.SnmpMgr.Config.set_default_timeout/1` and friends.

### GET, GETNEXT and SET

```elixir
{:ok, %{name: "sysDescr.0", oid: "1.3.6.1.2.1.1.1.0", type: :octet_string,
        value: "Cisco Router", formatted: "Cisco Router"}} =
  SnmpKit.SNMP.get(target, "sysDescr.0")

# Several objects in one PDU: one enriched map per OID, in request order.
# An object the agent does not have comes back with the SNMPv2c exception
# as its type instead of failing the whole call.
{:ok, [%{value: descr}, %{value: name}, %{type: :no_such_object, value: nil}]} =
  SnmpKit.SNMP.get(target, ["sysDescr.0", "sysName.0", "1.3.6.1.2.1.1.99.0"])

# GETNEXT returns the varbind that follows the given OID
{:ok, %{name: "sysObjectID.0"}} = SnmpKit.SNMP.get_next(target, "sysDescr.0")

# SET (against a writable agent; simulated devices answer {:error, :not_writable})
:ok = SnmpKit.SNMP.set("192.168.1.1", "sysContact.0", "ops@example.com")

# Several objects in one SET PDU, applied atomically by the agent
:ok = SnmpKit.SNMP.set_many("192.168.1.1", [{"sysContact.0", "ops"}, {"sysLocation.0", "rack 4"}])
```

Unknown objects yield `{:error, :no_such_object}` on v2c and
`{:error, :no_such_name}` on v1. Every network problem is `{:error, reason}`;
`reason` is `:timeout` for an unanswered request.

### Formatted values

`formatted` follows the MIB: enumeration labels (`ifOperStatus.1` ->
`"up"`, `ifType.1` -> `"ethernetCsmacd"`), DISPLAY-HINTs (`ifPhysAddress.1`
-> `"00:1a:2b:3c:4d:5e"`), textual conventions such as `TruthValue` and
`DateAndTime`, uptime for TimeTicks, and the plain value otherwise. The
built-in tables cover the standard MIBs; compile and load a vendor MIB and
its enumerations and hints are used too.

### Walks

```elixir
# GETNEXT/GETBULK walk of a subtree, list of enriched maps in OID order
{:ok, rows} = SnmpKit.SNMP.walk(target, "system")

# GETBULK-only walk (v2c)
{:ok, rows} = SnmpKit.SNMP.bulk_walk(target, "interfaces")

# Tunes max_repetitions while it runs
{:ok, rows} = SnmpKit.SNMP.adaptive_walk(target, "interfaces")

# Tables: the same varbinds restricted to the table...
{:ok, varbinds} = SnmpKit.SNMP.walk_table(target, "ifTable")

# ...or indexed rows: %{index => %{column => value}}
{:ok, %{1 => %{1 => 1, 2 => "eth0"}}} = SnmpKit.SNMP.get_table(target, "ifTable")
```

`max_repetitions:` is never capped by the library. Whole walks are bounded by
`walk_timeout:` (default 20 minutes); see
[TIMEOUT_DOCUMENTATION.md](../TIMEOUT_DOCUMENTATION.md).

### GETBULK

```elixir
{:ok, rows} = SnmpKit.SNMP.get_bulk(target, "interfaces", max_repetitions: 10)
rows = SnmpKit.get_bulk!(target, "interfaces", max_repetitions: 10)  # raises on error
```

### Streams

Streams fetch one GETBULK at a time as the consumer demands, so a walk of a
huge table never has to be held in memory:

```elixir
target
|> SnmpKit.SNMP.walk_stream("ifTable")
|> Stream.filter(&(&1.type == :counter32))
|> Enum.take(100)

SnmpKit.SNMP.bulk_walk_stream(target, "interfaces")          # GETBULK, v2c
SnmpKit.SNMP.table_bulk_stream(target, "ifTable", columns: [2, 8])  # only ifDescr and ifOperStatus
```

Elements are enriched varbind maps; an error mid-stream appears as a final
`{:error, reason}` element.

### Async

`get_async/3` and `get_bulk_async/3` return a `Task`:

```elixir
task = SnmpKit.SNMP.get_async(target, "sysDescr.0")
{:ok, %{value: _}} = Task.await(task, 5_000)
```

### Pretty output

The `*_pretty` variants return the same enriched maps; they exist for callers
that only want `:formatted` and read better in scripts:

```elixir
{:ok, %{formatted: "1 day, 10:17:36.78", value: 12345678, type: :timeticks}} =
  SnmpKit.SNMP.get_pretty(target, "sysUpTime.0")

{:ok, rows} = SnmpKit.SNMP.walk_pretty(target, "ifDescr")
```

### Multi-target

`get_multi`, `get_bulk_multi`, `walk_multi` and `walk_table_multi` take a list
of `{target, oid}` or `{target, oid, opts}` and return a plain list in request
order, one `{:ok, varbinds}` or `{:error, reason}` per request. For `get_multi`
the OID may be a list of OIDs, which go into one PDU:

```elixir
[{:ok, [%{value: "Cisco Router"}]}, {:error, :timeout}] =
  SnmpKit.SNMP.get_multi([
    {target, "sysDescr.0"},
    {"192.0.2.1", "sysDescr.0", timeout: 500, retries: 0}
  ])

SnmpKit.SNMP.walk_multi([{target, "system"}, {target, "interfaces"}], max_concurrent: 20)
SnmpKit.SNMP.get_bulk_multi([{target, "ifTable"}], max_repetitions: 20)
SnmpKit.SNMP.get_multi(requests, return_format: :map)   # %{{target, oid} => result}
```

Requests share one UDP socket and are correlated by request id, which is what
makes polling thousands of devices from one node practical. Details in
[concurrent-multi.md](concurrent-multi.md).

### Notifications

`SnmpKit.Trap` receives SNMPv1 traps, SNMPv2c traps and informs (informs are
acknowledged automatically) and hands each one to a handler: a function, an
MFA, or a pid that gets `{:snmp_trap, notification}`.

```elixir
{:ok, receiver} = SnmpKit.Trap.start_link(port: 162, handler: &MyApp.Alerts.handle/1)
# or as a child: {SnmpKit.Trap, port: 162, handler: {MyApp.Alerts, :handle, []}}

%{kind: :trap, version: :v2c, community: "public", source: {{10, 0, 0, 7}, 49152},
  trap_oid: [1, 3, 6, 1, 6, 3, 1, 1, 5, 3], trap_name: "linkDown", uptime: 12345,
  varbinds: [%{name: "sysUpTime.0", ...}, %{name: "snmpTrapOID.0", ...}, %{name: "ifIndex.3", value: 3, ...}]}
```

Sending is symmetrical. Trap OIDs and varbind OIDs accept names, dotted
strings or lists; `sysUpTime.0` and `snmpTrapOID.0` are added for you:

```elixir
:ok = SnmpKit.SNMP.send_trap("nms.example.com", "linkDown", [{"ifIndex.3", :integer, 3}])
:ok = SnmpKit.SNMP.send_inform("nms.example.com:162", "coldStart", [], timeout: 2_000, retries: 2)
:ok = SnmpKit.SNMP.send_trap(nms, "1.3.6.1.4.1.9999.0.7", [], version: :v1, agent_addr: {10, 0, 0, 7})

# From a simulated device, with its community and uptime
:ok = SnmpKit.Sim.send_trap(device, "linkDown", [{"ifIndex.1", :integer, 1}], to: "127.0.0.1:1162")
```

`send_inform/4` returns `{:error, :timeout}` when no acknowledgement arrives.
SNMPv3 notifications are not supported yet.

### Telemetry

Every request, walk and multi-target call is wrapped in a `:telemetry` span,
and the engine, trap receiver and simulated devices emit events. Attach to
`[:snmpkit, :request, :stop]`, `[:snmpkit, :walk, :stop]`,
`[:snmpkit, :multi, :stop]`, `[:snmpkit, :engine, :timeout]`,
`[:snmpkit, :trap, :received]` and friends; `SnmpKit.Telemetry` lists the
measurements and metadata of each.

```elixir
:telemetry.attach("snmp-latency", [:snmpkit, :request, :stop], fn _e, %{duration: d}, meta, _ ->
  MyApp.Metrics.observe(:snmp_request_ms, System.convert_time_unit(d, :native, :millisecond), meta.operation)
end, nil)
```

### Analysis helpers

```elixir
{:ok, rows} = SnmpKit.SNMP.walk_table(target, "ifTable")
{:ok, %{indexes: [1, 2], columns: [1, 2, 8], density: 1.0}} = SnmpKit.SNMP.analyze_table(rows)

# Measures response time for several max_repetitions values
{:ok, %{optimal_bulk_size: 20, recommendations: %{max_repetitions: 20, timeout: 3000}}} =
  SnmpKit.SNMP.benchmark_device(target, "interfaces")
```

## MIB operations

The common IETF MIBs (system, interfaces, ip, tcp, udp, snmp, host
resources, DOCSIS IF-MIB) are built in; nothing has to be loaded for them.

```elixir
{:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = SnmpKit.MIB.resolve("sysDescr.0")
{:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1]} = SnmpKit.MIB.resolve("ifInOctets.1")
{:ok, [1, 3, 6, 1, 2, 1, 1]} = SnmpKit.MIB.resolve("system")
{:error, :not_found} = SnmpKit.MIB.resolve("noSuchObject")

{:ok, "sysDescr.0"} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
{:ok, "sysDescr.0"} = SnmpKit.MIB.reverse_lookup("1.3.6.1.2.1.1.1.0")

# Tree navigation
{:ok, ["sysContact", "sysDescr", ...]} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])
{:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = SnmpKit.MIB.parent([1, 3, 6, 1, 2, 1, 1, 1, 0])
{:ok, [{"system", [1, 3, 6, 1, 2, 1, 1]}, {"sysDescr", [...]}, ...]} =
  SnmpKit.MIB.walk_tree([1, 3, 6, 1, 2, 1, 1])

# Metadata for an object
{:ok, %{module: "SNMPv2-MIB", oid: [1, 3, 6, 1, 2, 1, 1, 1],
        syntax: %{base: :octet_string, textual_convention: "DisplayString"}}} =
  SnmpKit.MIB.resolve_enhanced("sysDescr")
```

### Compiling and loading MIBs

```elixir
{:ok, compiled} = SnmpKit.MIB.compile("priv/mibs/MY-MIB.mib")
compiled.warnings           # [{line, message}] lexical/vendor-construct warnings
:ok = SnmpKit.MIB.load(compiled)

{:ok, [compiled | _]} = SnmpKit.MIB.compile_all(["A-MIB.mib", "B-MIB.mib"])
{:ok, compiled_list} = SnmpKit.MIB.compile_dir("priv/mibs")

# Compile, parse and register in one call
:ok = SnmpKit.MIB.load_and_integrate_mib("priv/mibs/MY-MIB.mib")
{:ok, oid} = SnmpKit.MIB.resolve("myObject.0")
```

Compilation errors are `{:error, {:snmp_lib_compilation_failed, [%SnmpKit.MIB.Error{}]}}`.
The [MIB guide](mib-guide.md) covers the compiler options and the parser's
compatibility with libsmi and net-snmp.

## Device simulation

```elixir
# Bundled walk files: :cable_modem, :router, :switch
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:cable_modem)
{:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161, community: "public")

# Your own objects (OIDs as strings or lists; values inferred or typed)
{:ok, _} =
  SnmpKit.Sim.start_device(
    %{objects: %{
        "1.3.6.1.2.1.1.1.0" => "Test Router v1.0",
        [1, 3, 6, 1, 2, 1, 1, 3, 0] => %{type: "TimeTicks", value: 12345}
      }},
    port: 1162
  )

# A recorded walk from a real device
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:my_switch, {:walk_file, "test/fixtures/switch.walk"})

# Populations
{:ok, devices} =
  SnmpKit.Sim.start_device_population([
    %{type: :cable_modem, port: 30001},
    %{type: :switch, port: 30002, community: "private"}
  ])

{:ok, devices} =
  SnmpKit.Sim.start_device_population(
    [{:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 100}],
    port_range: 30_000..30_099
  )
# devices: [%{type: :cable_modem, port: 30000, pid: pid, target: "127.0.0.1:30000"}, ...]
```

Devices started with `start_device/2` are linked to the caller, which is what
you want in an ExUnit `setup`. `SnmpKit.SnmpSim.start/1` starts supervised
device groups from a configuration map or file; see its docs and the
[testing guide](testing-guide.md).

## Shortcuts on `SnmpKit`

`SnmpKit.get/3`, `get_next/3`, `set/4`, `walk/3`, `walk_table/3`,
`get_bulk/3`, `bulk_walk/3`, `get_multi/2`, `get_bulk_multi/2`,
`walk_multi/2`, `walk_table_multi/2` and `resolve/1` delegate to the modules
above and return the same shapes.

## Error handling

```elixir
case SnmpKit.SNMP.get(target, oid, timeout: 1_000) do
  {:ok, %{value: value}} -> value
  {:error, :timeout} -> :unreachable
  {:error, :no_such_object} -> :missing
  {:error, reason} -> {:error, reason}
end
```

## Choosing an API level

- Scripts and one-off tools: `SnmpKit.get/3` and friends.
- Applications: `alias SnmpKit.{SNMP, MIB, Sim}` and call the context modules.
- Fleet polling: the multi-target functions with `return_format: :map`,
  `include_names: false` and `include_formatted: false`.
- Protocol-level work (custom PDUs, SNMPv3 key handling): `SnmpKit.SnmpLib.*`.
