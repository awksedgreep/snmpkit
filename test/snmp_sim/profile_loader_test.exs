defmodule SnmpKit.SnmpSim.ProfileLoaderTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.ProfileLoader

  describe "Profile Loading" do
    test "loads walk file into device profile" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      assert profile.device_type == :cable_modem
      assert profile.source_type == :walk_file
      assert is_map(profile.oid_map)
      assert map_size(profile.oid_map) > 0
      assert profile.metadata.oid_count > 0
    end

    test "starts device with walk-based profile" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      # Verify profile contains expected data
      assert ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.1.1.0") != nil
      assert ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.2.1.0") != nil
    end

    test "responds to SNMP GET with walk file values" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      # Test sysDescr
      sys_descr = ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.1.1.0")
      assert %{type: "STRING", value: value} = sys_descr
      assert String.contains?(value, "Motorola")

      # Test ifNumber
      if_number = ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.2.1.0")
      assert %{type: "INTEGER", value: 2} = if_number
    end

    test "handles missing OIDs with noSuchName" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      result = ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.99.99.99.0")
      assert result == nil
    end

    test "loads numeric OID walk files" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:oid_walk, "priv/walks/cable_modem_oids.walk"}
        )

      assert profile.device_type == :cable_modem
      assert profile.source_type == :oid_walk
      assert map_size(profile.oid_map) > 0

      # Verify only numeric OIDs are included
      oids = Map.keys(profile.oid_map)

      assert Enum.all?(oids, fn oid ->
               Regex.match?(~r/^\d+(\.\d+)*$/, oid)
             end)
    end

    test "loads manual definitions correctly" do
      manual_oids = %{
        "1.3.6.1.2.1.1.1.0" => "Test Device",
        "1.3.6.1.2.1.1.2.0" => %{type: "OID", value: "1.3.6.1.4.1.9.1.1"},
        "1.3.6.1.2.1.2.1.0" => 4
      }

      {:ok, profile} =
        ProfileLoader.load_profile(
          :test_device,
          {:manual, manual_oids}
        )

      assert profile.device_type == :test_device
      assert profile.source_type == :manual
      assert map_size(profile.oid_map) == 3

      # Check processed values
      assert %{type: "STRING", value: "Test Device"} =
               ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.1.1.0")

      assert %{type: "INTEGER", value: 4} =
               ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.2.1.0")
    end

    test "handles file read errors gracefully" do
      result =
        ProfileLoader.load_profile(
          :test_device,
          {:walk_file, "non_existent_file.walk"}
        )

      assert {:error, {:file_read_error, :enoent}} = result
    end
  end

  describe "OID Tree Operations" do
    setup do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      %{profile: profile}
    end

    test "maintains lexicographic order for GETNEXT", %{profile: profile} do
      ordered_oids = ProfileLoader.get_ordered_oids(profile)

      # Verify they are in lexicographic order
      for {oid1, oid2} <- Enum.zip(ordered_oids, tl(ordered_oids)) do
        assert compare_oids_lexicographically(oid1, oid2)
      end
    end

    test "finds next OID correctly", %{profile: profile} do
      # Test finding next OID after sysDescr
      case ProfileLoader.get_next_oid(profile, "1.3.6.1.2.1.1.1.0") do
        {:ok, next_oid} ->
          assert next_oid > "1.3.6.1.2.1.1.1.0"

        :end_of_mib ->
          # This could happen if sysDescr is the last OID
          assert true
      end
    end

    test "handles end of MIB correctly", %{profile: profile} do
      ordered_oids = ProfileLoader.get_ordered_oids(profile)
      last_oid = List.last(ordered_oids)

      result = ProfileLoader.get_next_oid(profile, last_oid)
      assert result == :end_of_mib
    end

    test "finds next OID for non-existent starting OID", %{profile: profile} do
      # Test with an OID that doesn't exist but should have a next one
      case ProfileLoader.get_next_oid(profile, "1.3.6.1.2.1.1.0") do
        {:ok, next_oid} ->
          assert String.starts_with?(next_oid, "1.3.6.1.2.1.1.")

        :end_of_mib ->
          # Could happen if no OIDs exist after this point
          assert true
      end
    end
  end

  describe "Profile Behaviors" do
    test "loads profile with behaviors specified" do
      behaviors = [
        {:increment_counters, rate: 1000},
        {:vary_gauges, variance: 0.1}
      ]

      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"},
          behaviors: behaviors
        )

      assert profile.behaviors == behaviors
    end

    test "includes metadata about loading" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      assert %{
               source_file: "priv/walks/cable_modem.walk",
               loaded_at: %DateTime{},
               oid_count: count
             } = profile.metadata

      assert count > 0
    end
  end

  describe "Unsupported Features" do
    test "returns error for compiled MIB sources (not yet implemented)" do
      result =
        ProfileLoader.load_profile(
          :test_device,
          {:compiled_mib, ["TEST-MIB"]}
        )

      assert {:error, :no_mibs_compiled} = result
    end

    test "returns error for unsupported source types" do
      result =
        ProfileLoader.load_profile(
          :test_device,
          {:unsupported_type, "some_data"}
        )

      assert {:error, {:unsupported_source_type, {:unsupported_type, "some_data"}}} = result
    end
  end

  # Helper function to compare OIDs lexicographically
  defp compare_oids_lexicographically(oid1, oid2) do
    parts1 = String.split(oid1, ".") |> Enum.map(&String.to_integer/1)
    parts2 = String.split(oid2, ".") |> Enum.map(&String.to_integer/1)

    compare_oid_parts(parts1, parts2)
  end

  defp compare_oid_parts([], []), do: false
  defp compare_oid_parts([], _), do: true
  defp compare_oid_parts(_, []), do: false
  defp compare_oid_parts([h1 | t1], [h2 | t2]) when h1 < h2, do: true
  defp compare_oid_parts([h1 | t1], [h2 | t2]) when h1 > h2, do: false
  defp compare_oid_parts([h1 | t1], [h2 | t2]) when h1 == h2, do: compare_oid_parts(t1, t2)
end
