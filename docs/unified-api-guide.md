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

A target is a hostname, an IPv4 or IPv6 address (`"[2001:db8::1]:161"` with
a port), `"host:port"`, an IP tuple, or a map with `:host` and `:port`.
Hostnames resolve to A records first, then AAAA. Options common to every call:

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

### SNMPv3

Pass `version: :v3` with a USM user. Engine discovery, key localization to
the agent's engine id, and time synchronisation happen on the first call
and are cached per target; `usmStatsNotInTimeWindows` and
`usmStatsUnknownEngineIDs` reports trigger a resynchronised retry.

```elixir
v3 = [
  version: :v3,
  security_name: "admin",
  auth_protocol: :sha256, auth_password: "auth-secret",   # :md5, :sha1, :sha256, :sha384, :sha512
  priv_protocol: :aes128, priv_password: "priv-secret"    # :des, :aes128, :aes192, :aes256
]

{:ok, %{value: descr}} = SnmpKit.SNMP.get(target, "sysDescr.0", v3)
{:ok, rows} = SnmpKit.SNMP.walk(target, "ifTable", v3)
```

Omit the privacy options for authNoPriv, or both for noAuthNoPriv. A wrong
password or user comes back as `{:error, {:usm_report, :usm_stats_wrong_digests}}`
or `{:error, {:usm_report, :usm_stats_unknown_user_names}}`. Multi-target
calls remain v1/v2c. Simulated devices speak v3 when started with
`v3_users:`, so all of this is testable offline (see the testing guide).

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

# ...with column names and decoded INDEX objects from the MIB
{:ok, %{1 => %{"ifIndex" => 1, "ifDescr" => "eth0", "ifOperStatus" => 1}}} =
  SnmpKit.SNMP.get_table(target, "ifTable", named: true)
```

Named rows work for the built-in tables and for any loaded MIB; a table
indexed by `IpAddress` and `Integer32` comes back with those values decoded
(`%{"peerAddr" => {10, 0, 0, 1}, "peerPort" => 179, ...}`) under the raw
index key.

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

### Counter rates

`SnmpKit.SNMP.Rate` turns two samples into deltas and per-second rates,
handling Counter32 and Counter64 wraparound:

```elixir
{:ok, t0} = SnmpKit.SNMP.walk(target, "ifTable")
Process.sleep(10_000)
{:ok, t1} = SnmpKit.SNMP.walk(target, "ifTable")

{:ok, rates} = SnmpKit.SNMP.Rate.rates(t0, t1, interval_ms: 10_000)
# [%{name: "ifInOctets.1", delta: 123_456, rate: 12_345.6, ...}, ...]

{:ok, 1296} = SnmpKit.SNMP.Rate.delta({:counter32, 4_294_967_000}, {:counter32, 1_000})
```

Include `sysUpTime.0` in what you poll and `rates/3` derives the interval
from it and reports `{:error, :device_restarted}` instead of computing rates
from reset counters.

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

To simulate a real device, record it once:

```elixir
{:ok, count} = SnmpKit.Sim.record("192.168.1.1", "test/fixtures/core-switch.walk", community: "public")
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:core_switch, {:walk_file, "test/fixtures/core-switch.walk"})
```

The file is net-snmp's numeric walk format, so `snmpwalk -On` output loads
the same way. `root:` picks the subtree (default mib-2).

Devices started with `start_device/2` are linked to the caller, which is what
you want in an ExUnit `setup`. `SnmpKit.SnmpSim.start/1` starts supervised
device groups from a configuration map or file; see its docs and the
[testing guide](testing-guide.md).

## SNMP agent

`SnmpKit.Agent` is the other side of the manager: it answers GET, GETNEXT,
GETBULK and SET for data your application owns, over SNMPv1, v2c and v3,
and sends notifications.

```elixir
{:ok, agent} =
  SnmpKit.Agent.start_link(
    port: 1161,
    communities: %{"public" => :read, "private" => :write},
    v3_users: [
      %{name: "monitor", auth: :sha256, auth_password: "auth-secret"},
      %{name: "ops", auth: :sha256, auth_password: "auth-secret",
        priv: :aes128, priv_password: "priv-secret", access: :write}
    ],
    system: [descr: "orders-api 3.2", name: "orders-01", location: "rack 4", contact: "ops@example.com"]
  )
```

The `system` group is served from those options, with `sysUpTime` computed
and `sysContact`, `sysName` and `sysLocation` writable. The rest of the MIB
is made of subtrees, each served by a handler registered at an OID prefix;
the longest matching prefix wins.

### Scalars

```elixir
# a fixed value, and one read on every request
:ok = SnmpKit.Agent.put(agent, "hrSystemProcesses.0", :gauge32, fn -> length(Process.list()) end)
:ok = SnmpKit.Agent.put(agent, [1, 3, 6, 1, 4, 1, 99999, 1, 0], :octet_string, "3.2.0")

# writable from a :write principal; SET keeps the type
:ok = SnmpKit.Agent.put(agent, [1, 3, 6, 1, 4, 1, 99999, 2, 0], :integer, 30, writable: true)
{:ok, {:integer, 30}} = SnmpKit.Agent.get(agent, [1, 3, 6, 1, 4, 1, 99999, 2, 0])
```

### Tables

`SnmpKit.Agent.Table` serves a table from a function that returns the rows.
Register it at the *entry* OID:

```elixir
:ok =
  SnmpKit.Agent.register(agent, "ifEntry", SnmpKit.Agent.Table,
    columns: [{1, :integer}, {2, :octet_string}, {5, :gauge32}, {8, :integer}],
    index: [:integer],
    rows: fn ->
      [{1, %{1 => 1, 2 => "lo", 5 => 0, 8 => 1}}, {2, %{1 => 2, 2 => "eth0", 5 => 1_000_000_000, 8 => 1}}]
    end,
    set: fn _index, _column, {_type, _value} -> {:error, :not_writable} end
  )

{:ok, %{2 => %{"ifDescr" => "eth0"}}} = SnmpKit.SNMP.get_table("127.0.0.1:1161", "ifTable", named: true)
```

`index:` lists the INDEX kinds (`:integer`, `:string`, `:implied_string`,
`:ip_address`, `:oid`, `:implied_oid`); a row's index is one value or a list
of them. Rows are fetched once per request, so each GETBULK sees a
consistent snapshot.

### Handlers

Anything else is a module implementing `SnmpKit.Agent.Handler`: `get/2`,
`get_next/2` and optionally `check_set/3`, `set/3` and `init/1`, all working
on the suffix below the registered prefix:

```elixir
defmodule MyApp.QueueStats do
  @behaviour SnmpKit.Agent.Handler

  @objects [{[1, 0], :gauge32, &MyApp.Queue.depth/0}, {[2, 0], :counter32, &MyApp.Queue.processed/0}]

  def get(suffix, _ctx) do
    case List.keyfind(@objects, suffix, 0) do
      {_, type, fun} -> {:ok, {type, fun.()}}
      nil -> {:error, :no_such_instance}
    end
  end

  def get_next(suffix, _ctx) do
    case Enum.find(@objects, fn {s, _, _} -> s > suffix end) do
      {s, type, fun} -> {:ok, {s, {type, fun.()}}}
      nil -> :end_of_subtree
    end
  end
end

:ok = SnmpKit.Agent.register(agent, [1, 3, 6, 1, 4, 1, 99999, 10], MyApp.QueueStats)
```

Handlers run in the request's worker process, concurrently, so keep state
in ETS or a process rather than in the handler's `ctx`. A handler that
raises answers `genErr` instead of taking the agent down.

### Access control and SET

A community or v3 user is `:read` or `:write`. SET from a `:read`
principal is `noAccess` (`noSuchName` to SNMPv1); unknown communities get
no answer. A SET is checked for every varbind first (`check_set/3`) and
only then applied (`set/3`), so a request that fails validation changes
nothing. SNMPv1 managers never see Counter64 objects, and receive
`noSuchName`/`badValue`/`genErr` in place of the SNMPv2 error codes
(RFC 3584). GETBULK is answered with as many repetitions as fit in a
datagram; `max_repetitions` is never capped.

### Notifications

```elixir
{:ok, agent} = SnmpKit.Agent.start_link(port: 1161, notify_targets: ["nms.example.com", {"10.0.0.5", 1162}])
:ok = SnmpKit.Agent.notify(agent, "linkDown", [{"ifIndex.2", :integer, 2}])
:ok = SnmpKit.Agent.notify(agent, "coldStart", [], targets: [%{host: "10.0.0.5", inform: true}])
```

`sysUpTime.0` is the agent's uptime; options are those of
`SnmpKit.SNMP.send_trap/4`. The result is `:ok` or
`{:error, [{target, reason}]}`.

### In a supervision tree

```elixir
children = [
  {SnmpKit.Agent,
   port: 161,
   name: MyApp.Agent,
   communities: ["public"],
   subtrees: [
     {"ifEntry", SnmpKit.Agent.Table, columns: [...], rows: &MyApp.Ports.rows/0},
     {[1, 3, 6, 1, 4, 1, 99999, 10], MyApp.QueueStats}
   ]}
]
```

Every request emits `[:snmpkit, :agent, :request]`; see `SnmpKit.Telemetry`.
Port 161 needs a privileged process or a capability such as
`setcap cap_net_bind_service=+ep` on the BEAM binary.

## Command line

`mix snmpkit.get`, `mix snmpkit.walk` (with `--table` for named rows and
`--no-bulk` for SNMPv1), `mix snmpkit.mib.compile` (prints the parser's
warnings per file, non-zero exit on failure), `mix snmpkit.mib.lint`
(semantic checks, see the MIB guide) and `mix snmpkit.sim` (a bundled
device, a recorded walk file, or a whole configuration) wrap the same
functions. Run any of them with `mix help snmpkit.walk` for options.

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
