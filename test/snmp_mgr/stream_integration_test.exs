defmodule SnmpKit.SnmpMgr.StreamIntegrationTest do
  @moduledoc """
  Integration tests for walk_stream using actual simulated devices.

  These tests verify that streaming works end-to-end, catching issues like
  OID format mismatches between what the transport layer returns and what
  the filtering logic expects.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SNMP
  alias SnmpKit.Sim
  alias SnmpKit.SnmpSim.Device

  @moduletag :integration

  setup do
    # Create a simple device with known OIDs
    oids = %{
      "1.3.6.1.2.1.1.1.0" => "Test Device",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.9999",
      "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 12345},
      "1.3.6.1.2.1.1.4.0" => "admin@test.com",
      "1.3.6.1.2.1.1.5.0" => "test-device",
      "1.3.6.1.2.1.1.6.0" => "Test Lab",
      "1.3.6.1.2.1.2.1.0" => 2,
      "1.3.6.1.2.1.2.2.1.1.1" => 1,
      "1.3.6.1.2.1.2.2.1.1.2" => 2,
      "1.3.6.1.2.1.2.2.1.2.1" => "eth0",
      "1.3.6.1.2.1.2.2.1.2.2" => "eth1"
    }

    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:test_device, {:manual, oids})
    port = Enum.random(20000..29999)
    {:ok, device} = Sim.start_device(profile, port: port)

    on_exit(fn ->
      Device.stop(device)
    end)

    %{target: "127.0.0.1:#{port}", device: device}
  end

  describe "walk_stream/3 integration" do
    test "returns data from simulated device", %{target: target} do
      # This test would have caught the OID list vs string format bug
      stream = SNMP.walk_stream(target, "system")

      results = stream |> Enum.take(3) |> Enum.to_list()

      # Verify we got actual data
      assert length(results) >= 1, "walk_stream should return at least one result"

      # Verify the format is correct (enriched map)
      first = hd(results)
      assert is_map(first), "Results should be enriched maps"
      assert Map.has_key?(first, :oid), "Result should have :oid key"
      assert Map.has_key?(first, :type), "Result should have :type key"
      assert Map.has_key?(first, :value), "Result should have :value key"
      assert Map.has_key?(first, :formatted), "Result should have :formatted key"
    end

    test "stream filters results to OID subtree", %{target: target} do
      # Walk the system subtree
      stream = SNMP.walk_stream(target, "1.3.6.1.2.1.1")
      results = stream |> Enum.to_list()

      # All results should be under system (1.3.6.1.2.1.1)
      Enum.each(results, fn result ->
        assert String.starts_with?(result.oid, "1.3.6.1.2.1.1"),
          "OID #{result.oid} should be under system subtree"
      end)
    end

    test "stream handles interface table", %{target: target} do
      stream = SNMP.walk_stream(target, "interfaces")
      results = stream |> Enum.to_list()

      # Should get interface data
      assert length(results) >= 1, "Should return interface data"

      # Verify we can process results
      oids = Enum.map(results, & &1.oid)
      assert Enum.all?(oids, &is_binary/1), "All OIDs should be strings"
    end

    test "stream can be enumerated multiple times", %{target: target} do
      stream = SNMP.walk_stream(target, "system")

      # First enumeration
      first_results = stream |> Enum.take(2) |> Enum.to_list()

      # Second enumeration (stream should be reusable)
      second_results = stream |> Enum.take(2) |> Enum.to_list()

      assert length(first_results) >= 1
      assert length(second_results) >= 1
    end
  end
end
