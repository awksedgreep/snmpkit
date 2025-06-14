defmodule SnmpKit.SnmpSim.DeviceDistributionTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.DeviceDistribution

  describe "default port assignments" do
    test "returns valid default port assignments" do
      assignments = DeviceDistribution.default_port_assignments()

      assert is_map(assignments)
      assert Map.has_key?(assignments, :cable_modem)
      assert Map.has_key?(assignments, :mta)
      assert Map.has_key?(assignments, :switch)
      assert Map.has_key?(assignments, :router)
      assert Map.has_key?(assignments, :cmts)
      assert Map.has_key?(assignments, :server)

      # Check ranges are valid
      Enum.each(assignments, fn {_type, range} ->
        assert Range.size(range) > 0
      end)
    end

    test "default assignments cover expected port counts" do
      assignments = DeviceDistribution.default_port_assignments()

      # Cable modems should have the largest allocation
      cable_modem_count = Enum.count(assignments.cable_modem)
      mta_count = Enum.count(assignments.mta)

      assert cable_modem_count > mta_count
      assert cable_modem_count == 8000
      assert mta_count == 1500
    end
  end

  describe "device type determination" do
    test "determines device type from port" do
      assignments = DeviceDistribution.default_port_assignments()

      # Test cable modem range
      assert DeviceDistribution.determine_device_type(30_000, assignments) == :cable_modem
      assert DeviceDistribution.determine_device_type(35_000, assignments) == :cable_modem
      assert DeviceDistribution.determine_device_type(37_999, assignments) == :cable_modem

      # Test MTA range
      assert DeviceDistribution.determine_device_type(38_000, assignments) == :mta
      assert DeviceDistribution.determine_device_type(39_000, assignments) == :mta

      # Test switch range
      assert DeviceDistribution.determine_device_type(39_500, assignments) == :switch
      assert DeviceDistribution.determine_device_type(39_600, assignments) == :switch

      # Test unknown port
      assert DeviceDistribution.determine_device_type(99_999, assignments) == nil
    end

    test "handles edge cases in port ranges" do
      assignments = %{
        test_device: 100..200
      }

      # Boundary conditions
      assert DeviceDistribution.determine_device_type(100, assignments) == :test_device
      assert DeviceDistribution.determine_device_type(200, assignments) == :test_device
      assert DeviceDistribution.determine_device_type(99, assignments) == nil
      assert DeviceDistribution.determine_device_type(201, assignments) == nil
    end
  end

  describe "device mix patterns" do
    test "provides valid cable network mix" do
      mix = DeviceDistribution.get_device_mix(:cable_network)

      assert is_map(mix)
      assert Map.has_key?(mix, :cable_modem)
      assert Map.has_key?(mix, :mta)
      assert Map.has_key?(mix, :cmts)

      # Cable modems should dominate
      assert mix.cable_modem > mix.mta
      assert mix.cable_modem > mix.cmts
    end

    test "provides valid enterprise network mix" do
      mix = DeviceDistribution.get_device_mix(:enterprise_network)

      assert is_map(mix)
      assert Map.has_key?(mix, :switch)
      assert Map.has_key?(mix, :router)
      assert Map.has_key?(mix, :server)

      # Switches should be more common than routers in enterprise
      assert mix.switch > mix.router
    end

    test "provides test mixes with reasonable scales" do
      small_mix = DeviceDistribution.get_device_mix(:small_test)
      medium_mix = DeviceDistribution.get_device_mix(:medium_test)

      # Small should be actually small
      small_total = Enum.sum(Map.values(small_mix))
      medium_total = Enum.sum(Map.values(medium_mix))

      assert small_total < 20
      assert medium_total > small_total
      assert medium_total < 200
    end
  end

  describe "port assignment building" do
    test "builds assignments from device mix" do
      device_mix = %{
        device_a: 10,
        device_b: 5
      }

      port_range = 1000..1020

      assignments = DeviceDistribution.build_port_assignments(device_mix, port_range)

      assert is_map(assignments)
      assert Map.has_key?(assignments, :device_a)
      assert Map.has_key?(assignments, :device_b)

      # Check ranges are reasonable
      device_a_count = Enum.count(assignments.device_a)
      device_b_count = Enum.count(assignments.device_b)

      # May be larger if non-contiguous
      assert device_a_count >= 10
      assert device_b_count >= 5
    end

    test "handles empty device mix" do
      device_mix = %{}
      port_range = 1000..1020

      assignments = DeviceDistribution.build_port_assignments(device_mix, port_range)
      assert assignments == %{}
    end

    test "raises error when not enough ports" do
      device_mix = %{
        device_a: 100
      }

      # Only 11 ports
      port_range = 1000..1010

      assert_raise ArgumentError, fn ->
        DeviceDistribution.build_port_assignments(device_mix, port_range)
      end
    end

    test "assigns largest device types first" do
      device_mix = %{
        small: 2,
        large: 10,
        medium: 5
      }

      port_range = 1000..1020

      assignments = DeviceDistribution.build_port_assignments(device_mix, port_range)

      # Should have assignments for all types
      assert Map.has_key?(assignments, :small)
      assert Map.has_key?(assignments, :large)
      assert Map.has_key?(assignments, :medium)
    end
  end

  describe "density statistics" do
    test "calculates density statistics correctly" do
      assignments = %{
        # 100 devices
        type_a: 1000..1099,
        # 50 devices
        type_b: 1100..1149,
        # 5 devices
        type_c: 1150..1154
      }

      stats = DeviceDistribution.calculate_density_stats(assignments)

      assert stats.total_devices == 155
      assert stats.device_types == 3

      # Check percentages
      type_a_stats = stats.distribution.type_a
      assert type_a_stats.count == 100
      # 100/155 * 100
      assert_in_delta type_a_stats.percentage, 64.5, 0.1
      assert type_a_stats.density == :dominant

      type_c_stats = stats.distribution.type_c
      assert type_c_stats.count == 5
      # 5/155 * 100
      assert_in_delta type_c_stats.percentage, 3.2, 0.1
      assert type_c_stats.density == :minor
    end

    test "identifies largest and smallest groups" do
      assignments = %{
        # 100 devices
        large: 1000..1099,
        # 5 devices
        small: 1100..1104
      }

      stats = DeviceDistribution.calculate_density_stats(assignments)

      assert stats.largest_group.type == :large
      assert stats.largest_group.count == 100

      assert stats.smallest_group.type == :small
      assert stats.smallest_group.count == 5
    end

    test "handles single device type" do
      assignments = %{
        only_type: 1000..1010
      }

      stats = DeviceDistribution.calculate_density_stats(assignments)

      assert stats.total_devices == 11
      assert stats.device_types == 1
      assert stats.largest_group.type == :only_type
      assert stats.smallest_group.type == :only_type
    end
  end

  describe "device characteristics" do
    test "provides characteristics for known device types" do
      cable_modem = DeviceDistribution.get_device_characteristics(:cable_modem)

      assert is_map(cable_modem)
      assert Map.has_key?(cable_modem, :typical_interfaces)
      assert Map.has_key?(cable_modem, :primary_protocols)
      assert Map.has_key?(cable_modem, :expected_uptime_days)
      assert Map.has_key?(cable_modem, :traffic_pattern)
      assert Map.has_key?(cable_modem, :error_rates)

      # Cable modems should have DOCSIS support
      assert :docsis in cable_modem.primary_protocols
      assert cable_modem.signal_monitoring == true
    end

    test "provides different characteristics for different device types" do
      cable_modem = DeviceDistribution.get_device_characteristics(:cable_modem)
      switch = DeviceDistribution.get_device_characteristics(:switch)
      cmts = DeviceDistribution.get_device_characteristics(:cmts)

      # Switches should have more interfaces than cable modems
      assert switch.typical_interfaces > cable_modem.typical_interfaces

      # CMTS should have highest uptime expectations
      assert cmts.expected_uptime_days >= switch.expected_uptime_days
      assert cmts.expected_uptime_days >= cable_modem.expected_uptime_days

      # Cable modems and CMTS should monitor signals, switches shouldn't
      assert cable_modem.signal_monitoring == true
      assert cmts.signal_monitoring == true
      assert switch.signal_monitoring == false
    end

    test "handles unknown device types gracefully" do
      unknown = DeviceDistribution.get_device_characteristics(:unknown_type)

      assert is_map(unknown)
      assert unknown.primary_protocols == [:unknown]
      assert unknown.traffic_pattern == :unknown
      # High error rate for unknown
      assert unknown.error_rates.high == 1.0
    end
  end

  describe "device ID generation" do
    test "generates default device IDs" do
      id = DeviceDistribution.generate_device_id(:cable_modem, 30001)
      assert id == "cable_modem_30001"

      id = DeviceDistribution.generate_device_id(:switch, 39500)
      assert id == "switch_39500"
    end

    test "generates MAC-based device IDs" do
      id = DeviceDistribution.generate_device_id(:cable_modem, 30001, format: :mac_based)

      # Should contain the type code and port info
      # Cable modem type code
      assert String.contains?(id, "CM")
      assert is_binary(id)
    end

    test "generates hostname-based device IDs" do
      id = DeviceDistribution.generate_device_id(:switch, 39500, format: :hostname)

      # Should start with switch prefix
      assert String.starts_with?(id, "sw-")
      # Padded port number
      assert String.contains?(id, "039500")
    end

    test "generates serial-based device IDs" do
      id = DeviceDistribution.generate_device_id(:router, 39900, format: :serial)

      # Should start with router prefix
      assert String.starts_with?(id, "ISR")
      # Should be reasonably long
      assert String.length(id) > 10
    end
  end

  describe "port assignment validation" do
    test "validates non-overlapping port assignments" do
      valid_assignments = %{
        type_a: 1000..1100,
        type_b: 1200..1300
      }

      assert DeviceDistribution.validate_port_assignments(valid_assignments) == :ok
    end

    test "detects overlapping port assignments" do
      overlapping_assignments = %{
        type_a: 1000..1150,
        # Overlaps with type_a
        type_b: 1100..1200
      }

      assert {:error, {:overlapping_ranges, _}} =
               DeviceDistribution.validate_port_assignments(overlapping_assignments)
    end

    test "detects invalid ranges" do
      invalid_assignments = %{
        # Invalid range
        type_a: 1000..999
      }

      assert {:error, {:invalid_ranges, _}} =
               DeviceDistribution.validate_port_assignments(invalid_assignments)
    end

    test "validates reasonable distribution sizes" do
      empty_assignments = %{}

      assert {:error, :no_device_types} =
               DeviceDistribution.validate_port_assignments(empty_assignments)

      huge_assignments = %{
        # Too many devices
        type_a: 1..200_000
      }

      assert {:error, {:too_many_devices, _}} =
               DeviceDistribution.validate_port_assignments(huge_assignments)
    end

    test "validates edge cases" do
      single_port = %{
        # Single port range
        type_a: 1000..1000
      }

      assert DeviceDistribution.validate_port_assignments(single_port) == :ok

      adjacent_ranges = %{
        type_a: 1000..1100,
        # Adjacent but not overlapping
        type_b: 1101..1200
      }

      assert DeviceDistribution.validate_port_assignments(adjacent_ranges) == :ok
    end
  end
end
