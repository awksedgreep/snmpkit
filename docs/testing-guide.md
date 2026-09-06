# Testing Guide

SnmpKit's simulator lets you test SNMP code without hardware: real UDP, real
PDUs, real v1/v2c semantics, all on localhost. This guide shows the patterns
the library's own suite uses.

## A device per test

```elixir
defmodule MyApp.PollerTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpSim.ProfileLoader

  setup do
    # Bundled profiles: :cable_modem, :router, :switch
    {:ok, profile} = ProfileLoader.load_profile(:router)
    port = free_udp_port()
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: port)
    %{target: "127.0.0.1:#{port}", device: device}
  end

  test "reads sysDescr", %{target: target} do
    assert {:ok, %{value: "Cisco Router", type: :octet_string}} =
             SnmpKit.SNMP.get(target, "sysDescr.0")
  end

  defp free_udp_port do
    {:ok, socket} = :gen_udp.open(0)
    {:ok, port} = :inet.port(socket)
    :gen_udp.close(socket)
    port
  end
end
```

`start_device/2` links the device to the test process, so it goes away with
the test and `async: true` is safe as long as each test picks its own port.

## Defining what the device answers

### Manual profiles

```elixir
{:ok, profile} =
  ProfileLoader.load_profile(:test_switch, {:manual, %{
    "1.3.6.1.2.1.1.1.0" => "Test Switch v1.0",                   # STRING
    "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 12345},   # explicit type
    "1.3.6.1.2.1.2.1.0" => 2,                                    # INTEGER
    "1.3.6.1.2.1.2.2.1.2.1" => "FastEthernet0/1",
    "1.3.6.1.2.1.2.2.1.2.2" => "FastEthernet0/2",
    "1.3.6.1.2.1.2.2.1.8.1" => 1,
    "1.3.6.1.2.1.2.2.1.8.2" => 2
  }})
```

Strings become `OCTET STRING`, integers `INTEGER`; use
`%{type: "Counter32" | "Gauge32" | "TimeTicks" | "IpAddress" | ..., value: v}`
for anything else. `SnmpKit.Sim.start_device(%{objects: map}, port: p)`
accepts the same map (OID keys as strings or lists) without a profile step.

### Recorded walks

Record a real device once and replay it forever, with SnmpKit itself or
with net-snmp:

```elixir
{:ok, _count} = SnmpKit.Sim.record("192.168.1.1", "test/fixtures/my_switch.walk", community: "public")
```

```sh
snmpwalk -v2c -c public -On 192.168.1.1 .1 > test/fixtures/my_switch.walk
```

```elixir
{:ok, profile} = ProfileLoader.load_profile(:my_switch, {:walk_file, "test/fixtures/my_switch.walk"})
```

Both `-On` numeric output and named output are understood.

### Behaviours

```elixir
{:ok, profile} =
  ProfileLoader.load_profile(:dynamic, {:manual, oids},
    behaviors: [:counter_increment, :time_based_changes])
```

Counters then grow between polls and sysUpTime advances, which is what you
want when testing rate calculations.

## SNMPv3

A device started with `v3_users:` answers SNMPv3 with the User-based
Security Model: engine discovery, authentication, privacy, time windows and
the `usmStats` reports a manager expects.

```elixir
{:ok, device} =
  SnmpKit.Sim.start_device(profile,
    port: port,
    v3_users: [
      %{name: "guest"},
      %{name: "ops", auth: :sha256, auth_password: "auth-secret"},
      %{name: "admin", auth: :sha256, auth_password: "auth-secret", priv: :aes128, priv_password: "priv-secret"}
    ]
  )

{:ok, _} = SnmpKit.SNMP.get(target, "sysDescr.0",
  version: :v3, security_name: "admin",
  auth_protocol: :sha256, auth_password: "auth-secret",
  priv_protocol: :aes128, priv_password: "priv-secret")
```

The engine id derives from the device id (pass `engine_id:` to fix it); a
user must be addressed at least at its own security level.

## Error conditions

`SnmpKit.SnmpSim.ErrorInjector` attaches to a running device:

```elixir
{:ok, device} = SnmpKit.Sim.start_device(profile, port: port)
{:ok, injector} = SnmpKit.SnmpSim.ErrorInjector.start_link(device, port)

SnmpKit.SnmpSim.ErrorInjector.inject_timeout(injector, probability: 1.0, duration_ms: 5_000)
SnmpKit.SnmpSim.ErrorInjector.inject_packet_loss(injector, loss_rate: 0.3)
SnmpKit.SnmpSim.ErrorInjector.inject_snmp_error(injector, :genErr, oids: ["1.3.6.1.2.1.1.5.0"])
SnmpKit.SnmpSim.ErrorInjector.simulate_device_failure(injector, :reboot, duration_ms: 2_000)
SnmpKit.SnmpSim.ErrorInjector.clear_all_errors(injector)
```

Some conditions need no injector at all:

| Condition | How |
|-----------|-----|
| unreachable device | query a port nothing listens on: `{:error, :timeout}` |
| unknown object | ask for an OID the profile lacks: `{:error, :no_such_object}` (v1: `:no_such_name`) |
| read-only agent | `SnmpKit.SNMP.set/4` against a simulated device: `{:error, :not_writable}` |
| wrong community | pass another `community:`; the device drops the packet, so `{:error, :timeout}` |

## Many devices

```elixir
{:ok, devices} =
  SnmpKit.Sim.start_device_population(
    [{:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 50},
     {:switch, {:walk_file, "priv/walks/switch.walk"}, count: 5}],
    port_range: 30_000..30_099
  )

targets = Enum.map(devices, &{&1.target, "sysUpTime.0"})
results = SnmpKit.SNMP.get_multi(targets, max_concurrent: 50)
assert Enum.all?(results, &match?({:ok, _}, &1))
```

Population devices run under the simulator's supervisor; stop them with
`SnmpKit.SnmpSim.stop_device/1` or `SnmpKit.SnmpSim.stop/0`. For whole
environments, `SnmpKit.SnmpSim.start/1` takes a configuration map or file
(`SnmpKit.SnmpSim.sample_config/0` shows the shape).

## Testing code that calls SnmpKit without the network

Hide SnmpKit behind a small module in your application and swap it in tests:

```elixir
defmodule MyApp.SNMPClient do
  @callback get(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(target, oid, opts \\ []), do: impl().get(target, oid, opts)
  defp impl, do: Application.get_env(:my_app, :snmp_client, SnmpKit.SNMP)
end

# test_helper.exs
Mox.defmock(MyApp.SNMPClientMock, for: MyApp.SNMPClient)
Application.put_env(:my_app, :snmp_client, MyApp.SNMPClientMock)
```

```elixir
test "reports unreachable devices" do
  expect(MyApp.SNMPClientMock, :get, fn _target, _oid, _opts -> {:error, :timeout} end)
  assert {:error, :device_unreachable} = MyApp.DeviceMonitor.status("10.0.0.1")
end
```

Prefer the simulator for anything that depends on real SNMP behaviour
(walk termination, table shapes, v1 versus v2c errors); use a mock only for
pure control-flow tests.

## Real devices

```elixir
defmodule MyApp.RealDeviceTest do
  use ExUnit.Case
  @moduletag :real_device

  @target System.get_env("SNMP_TEST_TARGET")

  setup_all do
    if @target, do: :ok, else: {:skip, "set SNMP_TEST_TARGET to run"}
  end

  test "answers sysDescr" do
    assert {:ok, %{value: descr}} = SnmpKit.SNMP.get(@target, "sysDescr.0", timeout: 5_000)
    assert is_binary(descr)
  end
end
```

Exclude the tag by default in `test_helper.exs` and include it on demand
with `mix test --include real_device`.

## Performance tests

```elixir
@moduletag :performance

test "walks ifTable quickly", %{target: target} do
  {micros, {:ok, rows}} = :timer.tc(fn -> SnmpKit.SNMP.walk(target, "ifTable") end)
  assert rows != []
  assert micros < 1_000_000
end
```

Keep wall-clock assertions behind an opt-in tag; they flake under a loaded
full run. `SnmpKit.SNMP.benchmark_device/3` measures how a device responds
to different `max_repetitions` values if you want data rather than a pass/fail.

## Test configuration

```elixir
# config/test.exs
config :snmpkit,
  timeout: 1_000,   # fail fast against simulated devices
  retries: 0

config :logger, level: :warning
```

## Tags used by SnmpKit's own suite

| Tag | Purpose |
|-----|---------|
| `:snmpv3` | SNMPv3 suites (`mix test --include snmpv3`) |
| `:performance` | timing assertions |
| `:mib_oracle` | MIB parser cross-check against libsmi / net-snmp |
| `:manual`, `:real_device` | need hardware or a person |

`mix test <directory>` runs only some files in that directory; pass globs
(`mix test test/snmp_mgr/*_test.exs`) or run the whole suite.

## Continuous integration

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ["1.18.4", "1.20.0"]
        otp: ["28.0"]
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix test
```

Simulated devices bind localhost UDP ports, which every hosted runner allows.
