# SnmpKit Examples

Runnable scripts that demonstrate SnmpKit against simulated devices. Run
them from a checkout with the library compiled:

```sh
mix run examples/getting_started.exs
mix run examples/unified_api_demo.exs
mix run examples/cable_modem_simulation.exs
```

To use SnmpKit in your own project add it to `mix.exs`:

```elixir
def deps do
  [{:snmpkit, "~> 2.0"}]
end
```

## The scripts

| Script | Shows |
|--------|-------|
| `getting_started.exs` | a simulated device, GET, WALK, bulk, MIB resolution, error handling |
| `unified_api_demo.exs` | the `SnmpKit.SNMP`, `SnmpKit.MIB` and `SnmpKit.Sim` modules and the `SnmpKit` shortcuts |
| `oid_formats_demo.exs` | the OID forms every call accepts (names, dotted strings, lists) |
| `multi_return_format_demo.exs` | `:list`, `:with_targets` and `:map` results from multi-target calls |
| `single_socket_demo.exs` | the shared-socket engine behind multi-target calls |
| `scalable_high_concurrency_polling.exs` | polling thousands of cable modems with `SnmpKit.SnmpMgr.Multi` |
| `cable_modem_simulation.exs`, `quick_cable_modem.exs` | DOCSIS cable modem simulation |
| `cable_modem_profile.json` | a JSON device profile for `{:json_profile, path}` |
| `docsis_mib_example.exs` | compiling and querying DOCSIS MIBs |

## Patterns worth copying

### Operations return enriched maps

```elixir
{:ok, %{value: descr, formatted: formatted, type: :octet_string}} =
  SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")

{:ok, rows} = SnmpKit.SNMP.walk("192.168.1.1", "ifTable")
{:ok, rows} = SnmpKit.SNMP.bulk_walk("192.168.1.1", "system")
```

### MIB lookups

```elixir
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
{:ok, name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
{:ok, children} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])
```

### A simulated device in a test

```elixir
setup do
  {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
  {:ok, _device} = SnmpKit.Sim.start_device(profile, port: 30161)
  %{target: "127.0.0.1:30161"}
end

test "can query the device", %{target: target} do
  assert {:ok, %{value: "Cisco Router"}} = SnmpKit.SNMP.get(target, "sysDescr.0")
end
```

### Many targets at once

```elixir
requests = for target <- targets, do: {target, "sysUpTime.0"}
results = SnmpKit.SNMP.get_multi(requests, max_concurrent: 50)
# [{:ok, [%{value: ...}]}, {:error, :timeout}, ...] in request order
```

### Streaming a large table

```elixir
"192.168.1.1"
|> SnmpKit.SNMP.walk_stream("ipRouteTable")
|> Stream.each(&process_entry/1)
|> Stream.run()
```

### Error handling

```elixir
case SnmpKit.SNMP.get(target, oid) do
  {:ok, %{value: value}} -> {:ok, value}
  {:error, :timeout} -> {:error, :device_unreachable}
  {:error, :no_such_object} -> {:error, :oid_not_found}
  {:error, reason} -> {:error, reason}
end
```

## More

- [Livebooks](../livebooks/01_quickstart.livemd) for an interactive tour
- [Unified API guide](../docs/unified-api-guide.md), [timeouts](../TIMEOUT_DOCUMENTATION.md), [MIB guide](../docs/mib-guide.md), [testing guide](../docs/testing-guide.md)
- [Issues](https://github.com/awksedgreep/snmpkit/issues)

New examples are welcome; keep them runnable with `mix run`, self-contained
(start their own simulated devices), and add them to the table above.
