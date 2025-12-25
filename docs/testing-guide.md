# Testing Guide - SnmpKit

This guide covers testing strategies, simulated devices, and best practices for testing SNMP applications with SnmpKit.

## Table of Contents

- [Overview](#overview)
- [Test Setup](#test-setup)
- [Unit Testing](#unit-testing)
- [Integration Testing](#integration-testing)
- [Simulated Devices](#simulated-devices)
- [Performance Testing](#performance-testing)
- [Test Utilities](#test-utilities)
- [Continuous Integration](#continuous-integration)
- [Best Practices](#best-practices)

## Overview

Testing SNMP applications presents unique challenges:

- **External Dependencies** - Real SNMP devices may not be available
- **Network Conditions** - Timeouts, packet loss, and latency variations
- **Device State** - SNMP values change over time
- **Scale Testing** - Testing with many devices and large data sets
- **Error Conditions** - Simulating various failure modes

SnmpKit addresses these challenges through:

- **Realistic Device Simulation** - Simulated SNMP agents for testing
- **Comprehensive Test Helpers** - Utilities for common testing patterns
- **Async Test Support** - Efficient testing of concurrent operations
- **Performance Benchmarking** - Built-in tools for performance testing

## Test Setup

### Basic Test Module Setup

```elixir
defmodule MyApp.SNMPTest do
  use ExUnit.Case, async: true
  
  alias SnmpKit.{SNMP, MIB, Sim}
  
  # Test configuration
  @test_community "public"
  @test_timeout 5_000
  
  setup_all do
    # Start any required services
    {:ok, _} = SNMP.start_engine()
    :ok
  end
  
  setup do
    # Per-test setup
    %{
      target: "127.0.0.1",
      community: @test_community,
      timeout: @test_timeout
    }
  end
end
```

### Application Test Helper

Create a test helper module for common operations:

```elixir
defmodule MyApp.TestHelper do
  @moduledoc """
  Common test utilities for SNMP testing.
  """
  
  def start_test_device(profile \\ :generic_router, opts \\ []) do
    port = Keyword.get(opts, :port, get_free_port())
    
    {:ok, profile_data} = SnmpKit.SnmpSim.ProfileLoader.load_profile(profile)
    {:ok, device} = SnmpKit.Sim.start_device(profile_data, port: port)
    
    %{
      device: device,
      target: "127.0.0.1:#{port}",
      port: port
    }
  end
  
  def get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
  
  def wait_for_device(target, timeout \\ 5_000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_device_loop(target, end_time)
  end
  
  defp wait_for_device_loop(target, end_time) do
    if System.monotonic_time(:millisecond) < end_time do
      case SnmpKit.SNMP.get(target, "sysDescr.0", timeout: 1_000) do
        {:ok, _} -> :ok
        {:error, _} -> 
          :timer.sleep(100)
          wait_for_device_loop(target, end_time)
      end
    else
      {:error, :timeout}
    end
  end
end
```

## Unit Testing

### Testing MIB Operations

```elixir
defmodule MyApp.MIBTest do
  use ExUnit.Case, async: true
  
  alias SnmpKit.MIB
  
  describe "OID resolution" do
    test "resolves standard system OIDs" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = MIB.resolve("sysDescr.0")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 3, 0]} = MIB.resolve("sysUpTime.0")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 5, 0]} = MIB.resolve("sysName.0")
    end
    
    test "handles invalid OID names" do
      assert {:error, :not_found} = MIB.resolve("nonExistentOid.0")
      assert {:error, :invalid_format} = MIB.resolve("")
    end
    
    test "resolves bulk OIDs efficiently" do
      oids = ["sysDescr.0", "sysUpTime.0", "sysName.0"]
      
      {time, {:ok, results}} = :timer.tc(fn ->
        MIB.resolve_many(oids)
      end)
      
      assert length(results) == 3
      assert time < 10_000  # Should be fast (< 10ms)
    end
  end
  
  describe "reverse lookup" do
    test "converts OIDs back to names" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      assert {:ok, "sysDescr.0"} = MIB.reverse_lookup(oid)
    end
    
    test "handles partial matches" do
      # OID that doesn't exactly match but has a parent
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 999]
      assert {:ok, name} = MIB.reverse_lookup(oid)
      assert String.contains?(name, "sysDescr")
    end
  end
end
```

### Testing SNMP Operations with Mocks

```elixir
defmodule MyApp.SNMPMockTest do
  use ExUnit.Case, async: true
  
  import Mox
  
  # Define mock in test_helper.exs:
  # Mox.defmock(MyApp.SNMPMock, for: SnmpKit.SNMP.Behaviour)
  
  setup :verify_on_exit!
  
  test "handles SNMP timeouts gracefully" do
    MyApp.SNMPMock
    |> expect(:get, fn _target, _oid, _opts ->
      {:error, :timeout}
    end)
    
    result = MyApp.DeviceMonitor.get_device_status("192.168.1.1")
    assert {:error, :device_unreachable} = result
  end
  
  test "retries on temporary failures" do
    MyApp.SNMPMock
    |> expect(:get, 2, fn _target, _oid, _opts ->
      {:error, :timeout}
    end)
    |> expect(:get, fn _target, _oid, _opts ->
      {:ok, "Test Device"}
    end)
    
    result = MyApp.DeviceMonitor.get_device_status("192.168.1.1")
    assert {:ok, %{description: "Test Device"}} = result
  end
end
```

## Integration Testing

### Testing with Simulated Devices

```elixir
defmodule MyApp.IntegrationTest do
  use ExUnit.Case, async: true
  
  alias MyApp.TestHelper
  
  describe "device communication" do
    setup do
      device_info = TestHelper.start_test_device(:cable_modem)
      :ok = TestHelper.wait_for_device(device_info.target)
      device_info
    end
    
    test "can query basic system information", %{target: target} do
      {:ok, %{value: description, type: type}} = SnmpKit.SNMP.get(target, "sysDescr.0")
      assert type == :octet_string
      assert is_binary(description)
      assert String.length(description) > 0

      {:ok, %{value: uptime, formatted: formatted}} = SnmpKit.SNMP.get(target, "sysUpTime.0")
      assert is_integer(uptime)
      assert uptime >= 0
      assert is_binary(formatted)  # Human-readable uptime string
    end
    
    test "can walk interface table", %{target: target} do
      {:ok, interfaces} = SnmpKit.SNMP.walk(target, "ifTable")
      assert is_list(interfaces)
      assert length(interfaces) > 0

      # Verify enriched map data structure
      for %{oid: oid, oid_list: oid_list, type: type, value: value, name: name} <- interfaces do
        assert is_binary(oid)
        assert is_list(oid_list)
        assert length(oid_list) > 0
        assert is_atom(type)
        assert value != nil
        assert is_binary(name)
      end
    end
    
    test "handles bulk operations", %{target: target} do
      {:ok, results} = SnmpKit.SNMP.bulk_walk(target, "system")
      assert is_list(results)
      assert length(results) > 0

      # Each result is an enriched map
      [first | _] = results
      assert Map.has_key?(first, :oid)
      assert Map.has_key?(first, :value)
      assert Map.has_key?(first, :type)
    end
  end
  
  describe "error handling" do
    setup do
      TestHelper.start_test_device(:unreliable_device)
    end
    
    test "handles device unreachable", %{target: target} do
      # Stop the device to simulate unreachable condition
      GenServer.stop(device.pid)
      
      result = SnmpKit.SNMP.get(target, "sysDescr.0", timeout: 1_000)
      assert {:error, :timeout} = result
    end
    
    test "handles invalid OIDs gracefully", %{target: target} do
      result = SnmpKit.SNMP.get(target, "nonExistent.0")
      assert {:error, :no_such_name} = result
    end
  end
end
```

### Testing with Real Devices

```elixir
defmodule MyApp.RealDeviceTest do
  use ExUnit.Case
  
  # Only run these tests when real devices are available
  @moduletag :integration
  @moduletag :real_devices
  
  @real_device_ip System.get_env("TEST_DEVICE_IP", "192.168.1.1")
  @real_device_community System.get_env("TEST_DEVICE_COMMUNITY", "public")
  
  setup_all do
    # Skip if no real device configured
    if @real_device_ip == "192.168.1.1" do
      {:skip, "No real device configured"}
    else
      # Verify device is reachable
      case SnmpKit.SNMP.get(@real_device_ip, "sysDescr.0", 
                            community: @real_device_community, timeout: 5_000) do
        {:ok, _} -> :ok
        {:error, _} -> {:skip, "Real device not reachable"}
      end
    end
  end
  
  test "can communicate with real device" do
    {:ok, %{value: description, formatted: formatted}} =
      SnmpKit.SNMP.get(@real_device_ip, "sysDescr.0",
                       community: @real_device_community)
    assert is_binary(description)
    IO.puts("Real device description: #{formatted}")
  end
end
```

## Simulated Devices

### Creating Custom Device Profiles

```elixir
defmodule MyApp.CustomDeviceTest do
  use ExUnit.Case, async: true
  
  test "creates custom device profile" do
    # Define custom device behavior
    custom_profile = %{
      name: "Test Switch",
      description: "Custom test switch for unit testing",
      objects: %{
        [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Test Switch v1.0",
        [1, 3, 6, 1, 2, 1, 1, 3, 0] => 12345,  # uptime
        [1, 3, 6, 1, 2, 1, 1, 5, 0] => "test-switch-01",
        # Interface table entries
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1] => "FastEthernet0/1",
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 2] => "FastEthernet0/2",
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 1] => 1,  # ifOperStatus = up
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 2] => 2   # ifOperStatus = down
      }
    }
    
    {:ok, device} = SnmpKit.Sim.start_device(custom_profile, port: 30001)
    target = "127.0.0.1:30001"
    
    # Test the custom device
    {:ok, %{value: description, name: name}} = SnmpKit.SNMP.get(target, "sysDescr.0")
    assert description == "Test Switch v1.0"
    assert name == "sysDescr.0"

    {:ok, %{value: if_name, type: type}} = SnmpKit.SNMP.get(target, "ifDescr.1")
    assert if_name == "FastEthernet0/1"
    assert type == :octet_string

    {:ok, %{value: if_status, formatted: formatted}} = SnmpKit.SNMP.get(target, "ifOperStatus.1")
    assert if_status == 1  # up
    assert formatted == "up"
  end
end
```

### Loading Device Profiles from Files

```elixir
defmodule MyApp.ProfileTest do
  use ExUnit.Case, async: true
  
  test "loads device profile from walk file" do
    # Create a test walk file
    walk_data = """
    1.3.6.1.2.1.1.1.0 = STRING: "Test Device"
    1.3.6.1.2.1.1.3.0 = Timeticks: (12345) 0:02:03.45
    1.3.6.1.2.1.1.5.0 = STRING: "test-device"
    """
    
    walk_file = Path.join(System.tmp_dir(), "test_device.walk")
    File.write!(walk_file, walk_data)
    
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
      :test_device,
      {:walk_file, walk_file}
    )
    
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: 30002)
    target = "127.0.0.1:30002"

    {:ok, %{value: description, type: type}} = SnmpKit.SNMP.get(target, "sysDescr.0")
    assert description == "Test Device"
    assert type == :octet_string

    # Clean up
    File.rm!(walk_file)
  end
end
```

## Performance Testing

### Benchmarking SNMP Operations

```elixir
defmodule MyApp.PerformanceTest do
  use ExUnit.Case
  
  alias MyApp.TestHelper
  
  @moduletag :performance
  
  setup_all do
    # Start multiple devices for load testing
    devices = for i <- 1..10 do
      TestHelper.start_test_device(:generic_router, port: 30000 + i)
    end
    
    %{devices: devices}
  end
  
  test "measures single GET performance", %{devices: [device | _]} do
    target = device.target
    
    # Warm up
    for _ <- 1..10 do
      SnmpKit.SNMP.get(target, "sysDescr.0")
    end
    
    # Measure performance
    {time, results} = :timer.tc(fn ->
      for _ <- 1..100 do
        SnmpKit.SNMP.get(target, "sysDescr.0")
      end
    end)
    
    avg_time = time / 100
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    IO.puts("Average GET time: #{avg_time/1000}ms")
    IO.puts("Success rate: #{success_count}/100")
    
    assert avg_time < 50_000  # Should be < 50ms average
    assert success_count == 100  # Should be 100% successful
  end
  
  test "measures concurrent GET performance", %{devices: devices} do
    targets = Enum.map(devices, & &1.target)
    
    {time, results} = :timer.tc(fn ->
      targets
      |> Enum.map(fn target ->
        Task.async(fn ->
          for _ <- 1..50 do
            SnmpKit.SNMP.get(target, "sysDescr.0")
          end
        end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))
    end)
    
    total_requests = length(devices) * 50
    avg_time = time / total_requests
    
    IO.puts("Concurrent average time: #{avg_time/1000}ms")
    IO.puts("Total requests: #{total_requests}")
    IO.puts("Total time: #{time/1_000_000}s")
    
    assert avg_time < 100_000  # Should be < 100ms average under load
  end
  
  test "measures walk performance", %{devices: [device | _]} do
    target = device.target

    {time, {:ok, results}} = :timer.tc(fn ->
      SnmpKit.SNMP.walk(target, "system")
    end)

    objects_per_ms = length(results) / (time / 1000)

    IO.puts("Walk time: #{time/1000}ms")
    IO.puts("Objects retrieved: #{length(results)}")
    IO.puts("Objects per ms: #{objects_per_ms}")

    # Verify enriched map format
    [first | _] = results
    assert %{oid: _, value: _, type: _, name: _} = first

    assert time < 1_000_000  # Should complete in < 1 second
    assert length(results) > 0
  end
end
```

### Memory and Resource Testing

```elixir
defmodule MyApp.ResourceTest do
  use ExUnit.Case
  
  test "handles large result sets without memory issues" do
    device = MyApp.TestHelper.start_test_device(:large_table_device)
    target = device.target

    # Monitor memory usage
    initial_memory = :erlang.memory(:total)

    # Perform large walk operation - returns list of enriched maps
    {:ok, results} = SnmpKit.SNMP.walk(target, "largeTable")

    # Each result is an enriched map with oid, oid_list, type, value, name, formatted
    assert Enum.all?(results, &is_map/1)

    peak_memory = :erlang.memory(:total)
    
    # Force garbage collection
    :erlang.garbage_collect()
    :timer.sleep(100)
    
    final_memory = :erlang.memory(:total)
    
    memory_growth = peak_memory - initial_memory
    memory_retained = final_memory - initial_memory
    
    IO.puts("Results count: #{length(results)}")
    IO.puts("Peak memory growth: #{memory_growth / 1024 / 1024}MB")
    IO.puts("Retained memory: #{memory_retained / 1024 / 1024}MB")
    
    # Memory should be reasonable
    assert memory_growth < 100 * 1024 * 1024  # < 100MB growth
    assert memory_retained < 10 * 1024 * 1024  # < 10MB retained
  end
end
```

## Test Utilities

### Custom ExUnit Assertions

```elixir
defmodule MyApp.SNMPAssertions do
  @moduledoc """
  Custom assertions for SNMP testing.
  """
  
  import ExUnit.Assertions
  
  def assert_snmp_success(result, message \\ nil) do
    case result do
      {:ok, value} -> value
      {:error, reason} -> 
        flunk(message || "Expected SNMP success, got error: #{inspect(reason)}")
    end
  end
  
  def assert_snmp_error(result, expected_error \\ nil, message \\ nil) do
    case result do
      {:error, reason} when expected_error == nil -> reason
      {:error, ^expected_error} -> expected_error
      {:error, reason} when expected_error != nil ->
        flunk(message || "Expected error #{expected_error}, got #{reason}")
      {:ok, value} ->
        flunk(message || "Expected SNMP error, got success: #{inspect(value)}")
    end
  end
  
  def assert_oid_resolved(oid_name, expected_oid \\ nil) do
    case SnmpKit.MIB.resolve(oid_name) do
      {:ok, ^expected_oid} when expected_oid != nil -> expected_oid
      {:ok, resolved_oid} when expected_oid == nil -> resolved_oid
      {:ok, actual_oid} when expected_oid != nil ->
        flunk("Expected OID #{inspect(expected_oid)}, got #{inspect(actual_oid)}")
      {:error, reason} ->
        flunk("Failed to resolve OID #{oid_name}: #{reason}")
    end
  end
  
  def assert_device_responsive(target, timeout \\ 5_000) do
    case SnmpKit.SNMP.get(target, "sysDescr.0", timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} ->
        flunk("Device #{target} not responsive: #{reason}")
    end
  end
end
```

### Test Data Generators

```elixir
defmodule MyApp.TestDataGenerator do
  @moduledoc """
  Generates test data for SNMP testing.
  """
  
  @doc """
  Generates mock walk data in the enriched map format.
  Useful for testing code that processes walk results.
  """
  def generate_walk_data(base_oid, count \\ 100) do
    for i <- 1..count do
      oid_list = base_oid ++ [i]
      oid_string = Enum.join(oid_list, ".")
      %{
        oid: oid_string,
        oid_list: oid_list,
        type: :octet_string,
        value: "Value #{i}",
        name: "testObject.#{i}",
        formatted: "Value #{i}"
      }
    end
  end
  
  @doc """
  Generates mock interface table data in the enriched map format.
  Each entry includes oid, oid_list, type, value, name, and formatted fields.
  """
  def generate_interface_table(interface_count \\ 24) do
    for i <- 1..interface_count do
      oper_status = Enum.random([1, 2])
      oper_status_formatted = if oper_status == 1, do: "up", else: "down"
      in_octets = :rand.uniform(1_000_000_000)
      out_octets = :rand.uniform(1_000_000_000)

      [
        %{oid: "1.3.6.1.2.1.2.2.1.1.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, i],
          type: :integer, value: i, name: "ifIndex.#{i}", formatted: "#{i}"},
        %{oid: "1.3.6.1.2.1.2.2.1.2.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, i],
          type: :octet_string, value: "eth#{i}", name: "ifDescr.#{i}", formatted: "eth#{i}"},
        %{oid: "1.3.6.1.2.1.2.2.1.3.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, i],
          type: :integer, value: 6, name: "ifType.#{i}", formatted: "ethernetCsmacd"},
        %{oid: "1.3.6.1.2.1.2.2.1.5.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, i],
          type: :gauge32, value: 1_000_000_000, name: "ifSpeed.#{i}", formatted: "1 Gbps"},
        %{oid: "1.3.6.1.2.1.2.2.1.8.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, i],
          type: :integer, value: oper_status, name: "ifOperStatus.#{i}", formatted: oper_status_formatted},
        %{oid: "1.3.6.1.2.1.2.2.1.10.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, i],
          type: :counter32, value: in_octets, name: "ifInOctets.#{i}", formatted: "#{in_octets}"},
        %{oid: "1.3.6.1.2.1.2.2.1.16.#{i}", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, i],
          type: :counter32, value: out_octets, name: "ifOutOctets.#{i}", formatted: "#{out_octets}"}
      ]
    end
    |> List.flatten()
  end
  
  @doc """
  Generates a device profile for use with SnmpKit.Sim.
  Note: Device profiles use OID list keys mapped to raw values,
  while SNMP responses use the enriched map format.
  """
  def generate_device_profile(type \\ :generic) do
    base_objects = %{
      [1, 3, 6, 1, 2, 1, 1, 1, 0] => device_description(type),
      [1, 3, 6, 1, 2, 1, 1, 2, 0] => device_object_id(type),
      [1, 3, 6, 1, 2, 1, 1, 3, 0] => :rand.uniform(1_000_000),
      [1, 3, 6, 1, 2, 1, 1, 4, 0] => "Test Admin",
      [1, 3, 6, 1, 2, 1, 1, 5, 0] => "test-device-#{:rand.uniform(1000)}",
      [1, 3, 6, 1, 2, 1, 1, 6, 0] => "Test Lab"
    }

    # Convert enriched maps to OID -> value format for device profile
    interface_objects =
      generate_interface_table()
      |> Enum.map(fn %{oid_list: oid_list, value: value} -> {oid_list, value} end)
      |> Enum.into(%{})

    Map.merge(base_objects, interface_objects)
  end
  
  defp device_description(:router), do: "Test Router v1.0"
  defp device_description(:switch), do: "Test Switch v2.0"
  defp device_description(:cable_modem), do: "Test Cable Modem v3.0"
  defp device_description(_), do: "Generic Test Device v1.0"
  
  defp device_object_id(:router), do: [1, 3, 6, 1, 4, 1, 9999, 1, 1]
  defp device_object_id(:switch), do: [1, 3, 6, 1, 4, 1, 9999, 1, 2]
  defp device_object_id(:cable_modem), do: [1, 3, 6, 1, 4, 1, 9999, 1, 3]
  defp device_object_id(_), do: [1, 3, 6, 1, 4, 1, 9999, 1, 0]
end
```

## Continuous Integration

### GitHub Actions Configuration

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        elixir: ['1.14', '1.15']
        otp: ['25', '26']
        
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}
        
    - name: Restore dependencies cache
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
        restore-keys: ${{ runner.os }}-mix-
        
    - name: Install dependencies
      run: mix deps.get
      
    - name: Run tests
      run: mix test --trace
      
    - name: Run integration tests
      run: mix test --include integration
      
    - name: Generate coverage report
      run: mix test --cover
      
    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
```

### Test Configuration

```elixir
# config/test.exs
import Config

config :snmpkit,
  default_timeout: 1_000,  # Faster timeouts for testing
  default_retries: 1

config :snmpkit, :simulation,
  device_profiles_path: "test/fixtures/profiles",
  walk_files_path: "test/fixtures/walks"

# Reduce log noise during testing
config :logger, level: :warning

# Enable async testing
config :ex_unit,
  capture_log: true,
  async: true
```

## Best Practices

### 1. Use Appropriate Test Types

- **Unit Tests** - Test individual functions and modules in isolation
- **Integration Tests** - Test interaction between components
- **System Tests** - Test complete workflows with simulated devices
- **Performance Tests** - Test performance characteristics and limits

### 2. Design for Testability

```elixir
# Bad: Hard to test, tightly coupled
def monitor_device(ip) do
  case SnmpKit.SNMP.get(ip, "sysDescr.0") do
    {:ok, description} -> 
      Logger.info("Device #{ip}: #{description}")
      send_notification(description)
    {:error, reason} ->
      Logger.error("Failed to monitor #{ip}: #{reason}")
      raise "Device monitoring failed"
  end
end

# Good: Testable, dependency injection
def monitor_device(ip, snmp_client \\ SnmpKit.SNMP, notifier \\ MyApp.Notifier) do
  case snmp_client.get(ip, "sysDescr.0") do
    {:ok, description} -> 
      Logger.info("Device #{ip}: #{description}")
      notifier.send_notification(description)
      {:ok, description}
    {:error, reason} ->
      Logger.error("Failed to monitor #{ip}: #{reason}")
      {:error, reason}
  end
end
```

### 3. Use Simulated Devices Extensively

- Create realistic device profiles for different device types
- Test edge cases and error conditions
- Simulate network conditions (latency, packet loss)
- Test with various SNMP versions and configurations

### 4. Test Error Conditions

```elixir
test "handles various error conditions" do
  test_cases = [
    {:timeout, "unreachable.device"},
    {:no_such_name, "invalid.oid"},
    {:bad_value, "read_only.oid"},
    {:authorization_error, "wrong.community"}
  ]
  
  for {expected_error, scenario} <- test_cases do
    result = perform_test_scenario(scenario)
    assert {:error, ^expected_error} = result
  end
end
```

### 5. Use Property-Based Testing

```elixir
defmodule MyApp.PropertyTest do
  use ExUnit.Case
  use PropCheck
  
  property "OID resolution is bidirectional" do
    forall oid_name <- valid_oid_name() do
      case SnmpKit.MIB.resolve(oid_name) do
        {:ok, oid} ->
          {:ok, reversed_name} = SnmpKit.MIB.reverse_lookup(oid)
          String.contains?(reversed_name, extract_base_name(oid_name))
        {:error, _} ->
          true  # Invalid names are okay
      end
    end
  end
  
  defp valid_oid_name do
    oneof([
      "sysDescr.0",
      "sysUpTime.0", 
      "sysName.0",
      "ifDescr.1",
      "ifInOctets.1"
    ])
  end
end
```

### 6. Monitor Test Performance

- Track test execution times
- Identify slow tests and optimize them
- Use async testing where possible
- Profile memory usage in tests

### 7. Maintain Test Data

- Keep device profiles up to date
- Version test data files
- Document test scenarios and expected outcomes
- Clean up test resources properly

For more advanced testing techniques and examples, see the [API documentation](https://hexdocs.pm/snmpkit) and [example tests](https://github.com/awksedgreep/snmpkit/tree/main/test).