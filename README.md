# SnmpKit

[![Hex.pm](https://img.shields.io/hexpm/v/snmpkit.svg)](https://hex.pm/packages/snmpkit)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snmpkit)
[![License](https://img.shields.io/github/license/awksedgreep/snmpkit.svg)](LICENSE)
[![Elixir CI](https://github.com/awksedgreep/snmpkit/actions/workflows/elixir.yml/badge.svg)](https://github.com/awksedgreep/snmpkit/actions/workflows/elixir.yml)

A pure Elixir SNMP toolkit: manager operations for SNMPv1, v2c and v3, a
native MIB compiler, and simulated devices for tests. It does not depend on
Erlang's `:snmp` application.

## Installation

```elixir
def deps do
  [
    {:snmpkit, "~> 2.0"}
  ]
end
```

Upgrading from 1.x? See the [2.0 migration guide](docs/v2-migration.md).

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
| `SnmpKit.Sim` | Start one simulated device, or a population of them |
| `SnmpKit.SnmpSim` | Configuration-driven simulation of whole device groups |
| `SnmpKit` | Shortcuts for the most common calls (`get`, `walk`, `resolve`, ...) |

Lower layers are public too when you need them: `SnmpKit.SnmpLib` (PDU
encoding, ASN.1, transport, SNMPv3 security), `SnmpKit.SnmpMgr` (engine,
multi-target coordinator, walk strategies) and `SnmpKit.MIB.Parser` /
`SnmpKit.MIB.Compiler` (the native MIB toolchain).

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

Name resolution and formatting can be switched off per call
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
- Livebooks: [quickstart](livebooks/01_quickstart.livemd), [SNMP operations](livebooks/02_snmp_operations.livemd), [MIB management](livebooks/03_mib_management.livemd), [device simulation](livebooks/04_device_simulation.livemd), [high performance](livebooks/05_high_performance.livemd)
- [Examples](examples/README.md)
- [Full API reference](https://hexdocs.pm/snmpkit)

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
