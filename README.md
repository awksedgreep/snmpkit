# SnmpKit

[![Hex.pm](https://img.shields.io/hexpm/v/snmpkit.svg)](https://hex.pm/packages/snmpkit)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snmpkit)
[![License](https://img.shields.io/github/license/awksedgreep/snmpkit.svg)](LICENSE)
[![Elixir CI](https://github.com/awksedgreep/snmpkit/actions/workflows/elixir.yml/badge.svg)](https://github.com/awksedgreep/snmpkit/actions/workflows/elixir.yml)

A pure Elixir SNMP toolkit: manager operations for SNMPv1, v2c and v3, a
trap and inform receiver, a native MIB compiler, and simulated devices for
tests. It does not depend on Erlang's `:snmp` application.

## Installation

```elixir
def deps do
  [
    {:snmpkit, "~> 2.0"}
  ]
end
```

## Breaking changes in 2.0

2.0 is a consolidation release. Request and response shapes are the same as
in 1.4; what changed is which modules exist and a few behaviours:

- **Renamed:** `SnmpMgr.EngineV2` is now `SnmpMgr.Engine`, `SnmpMgr.MultiV2`
  is now `SnmpMgr.Multi`, `SnmpLib.MIB.*` is now `SnmpKit.MIB.*`, and
  `SnmpSim.Device.ErrorInjector` is now `SnmpSim.Device.ErrorConditions`.
- **Removed:** the old opt-in request-batching engine (`start_engine` /
  `engine_request` / `engine_batch`) with its `Router`, `CircuitBreaker`,
  `Metrics` and `SnmpMgr.Supervisor`, which no default operation used; `SnmpMgr.SocketManager` (the engine
  owns the socket); the Task-per-target `Multi` and the `strategy:` option;
  `SnmpLib.Config`, `Pool`, `Cache`, `Monitor`, `Dashboard`; the `SnmpLib.MIB`
  facade; `SnmpKit.TestSupport` (use `SnmpKit.SnmpSim`); `Keys.secure_wipe/1`;
  and `SnmpMgr.start_engine`, `engine_request`, `engine_batch`,
  `get_engine_stats`, `with_circuit_breaker`, `record_metric`.
- **Behaviour:** `get_async`/`get_bulk_async` return a `Task`; manager
  defaults are read from `config :snmpkit` (the `:snmp_mgr` key still works);
  `MIB.load/1` takes the map `compile/1` returns; `Sim.start_device_population/2`
  pre-warms devices and returns `[%{type, port, pid, target}]`; `set/4` and
  `set_many/3` return `:ok` (not `{:ok, :success}`); parsed MIBs carry a
  `warnings` list and identifiers are binaries instead of atoms.
- **Tooling:** Elixir 1.18+ on OTP 28.

The [2.0 migration guide](docs/v2-migration.md) has the full rename and
removal tables with replacements for each entry.

## Quick start

Everything below runs against a simulated device, so it works offline.

```elixir
# A simulated router on localhost:1161, built from a walk file that ships
# with the library (also :cable_modem and :switch)
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
{:ok, _device} = SnmpKit.Sim.start_device(profile, port: 1161)
target = "127.0.0.1:1161"

# GET returns one enriched varbind map
{:ok, %{value: descr, type: :octet_string, oid: "1.3.6.1.2.1.1.1.0"}} =
  SnmpKit.SNMP.get(target, "sysDescr.0")

# WALK returns a list of them, in OID order
{:ok, system} = SnmpKit.SNMP.walk(target, "system")
Enum.each(system, fn %{name: name, formatted: value} -> IO.puts("#{name} = #{value}") end)

# SNMPv3: discovery, key localization and time sync are automatic
{:ok, _} = SnmpKit.SNMP.get(target, "sysDescr.0",
  version: :v3, security_name: "admin",
  auth_protocol: :sha256, auth_password: "auth-secret",
  priv_protocol: :aes128, priv_password: "priv-secret")

# Multi-target calls return one result per request, in request order
[{:ok, [%{value: ^descr}]}, {:ok, [%{name: "sysName.0"}]}] =
  SnmpKit.SNMP.get_multi([{target, "sysDescr.0"}, {target, "sysName.0"}])

# MIB lookups work without any loading; the common IETF MIBs are built in
{:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = SnmpKit.MIB.resolve("sysDescr.0")
{:ok, "sysDescr.0"} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])

# Your own MIBs
{:ok, compiled} = SnmpKit.MIB.compile("priv/mibs/MY-ENTERPRISE-MIB.mib")
:ok = SnmpKit.MIB.load(compiled)
```

## The API in one screen

| Module | What it is for |
|--------|----------------|
| `SnmpKit.SNMP` | Manager operations: get, get_next, set, walk, get_bulk, bulk walks, tables, streams, async, multi-target, pretty formatting |
| `SnmpKit.MIB` | Name/OID resolution, tree navigation, MIB compilation and loading |
| `SnmpKit.Trap` | Receive SNMPv1/v2c traps and informs; `SnmpKit.SNMP.send_trap/4` and `send_inform/4` send them |
| `SnmpKit.Telemetry` | The `:telemetry` spans and events every request, walk, multi-target call, trap and simulated device emits |
| `SnmpKit.Agent` | Serve your own data over SNMP: scalars, tables and custom handlers, v1/v2c/v3, traps out |
| `SnmpKit.Sim` | Start one simulated device, or a population of them |
| `SnmpKit.SnmpSim` | Configuration-driven simulation of whole device groups |
| `SnmpKit` | Shortcuts for the most common calls (`get`, `walk`, `resolve`, ...) |

Lower layers are public too when you need them: `SnmpKit.SnmpLib` (PDU
encoding, ASN.1, transport, SNMPv3 security), `SnmpKit.SnmpMgr` (engine,
multi-target coordinator, walk strategies) and `SnmpKit.MIB.Parser` /
`SnmpKit.MIB.Compiler` (the native MIB toolchain).

## Your own SNMP agent

`SnmpKit.Agent` exposes an application's data to any NMS over SNMPv1, v2c
and v3. Scalars go in with `put/4` (a function value is read live), tables
come from a row-producing function, and anything else is a small module
implementing `SnmpKit.Agent.Handler`:

```elixir
{:ok, agent} =
  SnmpKit.Agent.start_link(
    port: 1161,
    communities: %{"public" => :read, "private" => :write},
    v3_users: [%{name: "ops", auth: :sha256, auth_password: "auth-secret", access: :write}],
    system: [descr: "orders-api 3.2", name: "orders-01", location: "rack 4"]
  )

:ok = SnmpKit.Agent.put(agent, "hrSystemProcesses.0", :gauge32, fn -> length(Process.list()) end)

:ok =
  SnmpKit.Agent.register(agent, "ifEntry", SnmpKit.Agent.Table,
    columns: [{1, :integer}, {2, :octet_string}, {8, :integer}],
    rows: fn -> [{1, %{1 => 1, 2 => "lo", 8 => 1}}, {2, %{1 => 2, 2 => "eth0", 8 => 1}}] end
  )

# Any manager, including this one, can read it now
{:ok, %{1 => %{2 => "lo"}, 2 => %{2 => "eth0"}}} =
  SnmpKit.SNMP.get_table("127.0.0.1:1161", "ifTable")

# and traps go out with the agent's sysUpTime
:ok = SnmpKit.Agent.notify(agent, "linkDown", [{"ifIndex.2", :integer, 2}], targets: ["nms.example.com"])
```

Put `{SnmpKit.Agent, port: 161, name: MyApp.Agent, subtrees: [...]}` in a
supervision tree for production. The [API guide](docs/unified-api-guide.md#snmp-agent)
covers access control, SET handling and writing handlers.

## Results

Every operation returns enriched varbind maps:

```elixir
%{
  name: "sysUpTime.0",            # nil when no MIB name is known
  oid: "1.3.6.1.2.1.1.3.0",
  oid_list: [1, 3, 6, 1, 2, 1, 1, 3, 0],
  type: :timeticks,
  value: 12345678,
  formatted: "1 day, 10:17:36.78"
}
```

`formatted` follows the MIB: `ifOperStatus` reads `"up"`, `ifType` reads
`"ethernetCsmacd"`, `ifPhysAddress` reads `"00:1a:2b:3c:4d:5e"`, and a loaded
vendor MIB's enumerations and DISPLAY-HINTs apply the same way. Name
resolution and formatting can be switched off per call
(`include_names: false`, `include_formatted: false`) or globally through
configuration, which matters on hot paths that walk large tables.

Errors are tagged tuples: `{:error, :timeout}`, `{:error, :no_such_object}`
(SNMPv2c), `{:error, :no_such_name}` (SNMPv1), `{:error, :not_writable}`, and
so on.

## Multi-target operations

`get_multi`, `get_bulk_multi`, `walk_multi` and `walk_table_multi` run every
request concurrently over one shared UDP socket with centralized response
correlation. Nothing needs to be started by hand; the engine comes up on the
first call.

```elixir
requests = [
  {"switch-1", "ifTable"},
  {"switch-2", "ifTable", timeout: 30_000},   # per-request options
  {"router-1", "ipRouteTable"}
]

results = SnmpKit.SNMP.walk_multi(requests, max_concurrent: 20, walk_timeout: 120_000)
# [{:ok, [...]}, {:ok, [...]}, {:error, :timeout}]   (request order)

SnmpKit.SNMP.get_multi(requests, return_format: :map)
# %{{"switch-1", "ifTable"} => {:ok, [...]}, ...}
```

See [Concurrent Multi](docs/concurrent-multi.md) and the
[timeout guide](TIMEOUT_DOCUMENTATION.md).

## Configuration

Defaults are read from the application environment at startup and can be
changed at runtime through `SnmpKit.SnmpMgr.Config`:

```elixir
# config/config.exs
config :snmpkit,
  community: "public",
  timeout: 5_000,          # per-PDU timeout for single-target calls, ms
  retries: 1,
  port: 161,
  version: :v2c,
  include_names: true,
  include_formatted: true,
  auto_start_services: true

# Limits applied when reading walk files and MIBs
config :snmpkit,
  max_input_file_bytes: 50_000_000,
  max_compiled_mib_bytes: 50_000_000,
  input_roots: ["priv"]   # optional jail for user-supplied file paths
```

## Documentation

- [2.0 migration guide](docs/v2-migration.md)
- [Unified API guide](docs/unified-api-guide.md)
- [Concurrent multi-target operations](docs/concurrent-multi.md)
- [Timeouts and retries](TIMEOUT_DOCUMENTATION.md)
- [MIB guide](docs/mib-guide.md) and [checking the parser against libsmi and net-snmp](docs/mib-parser-oracle.md)
- [Testing guide](docs/testing-guide.md)
- Livebooks: [quickstart](livebooks/01_quickstart.livemd), [SNMP operations](livebooks/02_snmp_operations.livemd), [MIB management](livebooks/03_mib_management.livemd), [device simulation](livebooks/04_device_simulation.livemd), [high performance](livebooks/05_high_performance.livemd), [your own SNMP agent](livebooks/06_snmp_agent.livemd), [SNMPv3](livebooks/07_snmpv3.livemd)
- [Examples](examples/README.md)
- [Full API reference](https://hexdocs.pm/snmpkit)

## Command line

Four mix tasks give you a shell without writing a script:

```sh
mix snmpkit.get 192.168.1.1 sysDescr.0 sysUpTime.0 -c public
mix snmpkit.walk 192.168.1.1 ifTable --table          # named columns
mix snmpkit.mib.compile priv/mibs                     # prints parser warnings
mix snmpkit.mib.lint VENDOR-MIB.mib --context priv/mibs # semantic checks, smilint-style
mix snmpkit.sim --device router --port 1161           # a simulated device until Ctrl-C
mix snmpkit.sim devices.yaml                          # a whole population from a config
```

## Development

```sh
mix test                       # unit + integration suite
mix test --include snmpv3      # SNMPv3 suites
mix test --include mib_oracle  # cross-check the MIB parser (needs smilint / snmptranslate)
mix lint                       # format check, credo --strict, dialyzer
```

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

SnmpKit is released under the [MIT License](LICENSE).
