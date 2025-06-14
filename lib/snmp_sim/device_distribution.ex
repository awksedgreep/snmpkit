defmodule SnmpSim.DeviceDistribution do
  @moduledoc """
  Device Type Distribution for realistic device type assignment across port ranges.
  Supports mixed device populations for authentic testing environments.

  Features:
  - Realistic device type distribution patterns
  - Flexible port range assignment strategies
  - Support for custom device mixes
  - Population density calculations
  - Device type metadata and characteristics
  """

  @type device_type :: :cable_modem | :mta | :switch | :router | :cmts | :server
  @type port_range :: Range.t()
  @type device_mix :: %{device_type() => non_neg_integer()}
  @type port_assignments :: %{device_type() => port_range()}

  @doc """
  Get the default device type port ranges for large-scale simulation.
  Optimized for 10K device populations with realistic distribution.
  """
  @spec default_port_assignments() :: port_assignments()
  def default_port_assignments do
    %{
      # 8,000 cable modems (80%)
      cable_modem: 30_000..37_999,
      # 1,500 MTAs (15%)
      mta: 38_000..39_499,
      # 400 switches (4%)
      switch: 39_500..39_899,
      # 50 routers (0.5%)
      router: 39_900..39_949,
      # 25 CMTS devices (0.25%)
      cmts: 39_950..39_974,
      # 25 servers (0.25%)
      server: 39_975..39_999
    }
  end

  @doc """
  Get common device mix patterns for different testing scenarios.
  """
  @spec get_device_mix(atom()) :: device_mix()
  def get_device_mix(:cable_network) do
    %{
      cable_modem: 8000,
      mta: 1500,
      cmts: 25,
      server: 10
    }
  end

  def get_device_mix(:enterprise_network) do
    %{
      switch: 500,
      router: 100,
      server: 200,
      # Guest network
      cable_modem: 50
    }
  end

  def get_device_mix(:isp_network) do
    %{
      cable_modem: 5000,
      mta: 1000,
      switch: 200,
      router: 50,
      cmts: 20,
      server: 30
    }
  end

  def get_device_mix(:small_test) do
    %{
      cable_modem: 10,
      switch: 3,
      router: 2,
      server: 1
    }
  end

  def get_device_mix(:medium_test) do
    %{
      cable_modem: 100,
      mta: 20,
      switch: 10,
      router: 5,
      cmts: 2,
      server: 3
    }
  end

  @doc """
  Determine device type for a given port based on port assignments.
  """
  @spec determine_device_type(non_neg_integer(), port_assignments()) :: device_type() | nil
  def determine_device_type(port, port_assignments) do
    Enum.find_value(port_assignments, fn {device_type, range} ->
      if port in range, do: device_type, else: nil
    end)
  end

  @doc """
  Build port assignments from a device mix and port range.
  Distributes devices across the port range maintaining the specified ratios.
  """
  @spec build_port_assignments(device_mix(), port_range()) :: port_assignments()
  def build_port_assignments(device_mix, port_range) do
    total_devices = Enum.sum(Map.values(device_mix))
    port_list = Enum.to_list(port_range)
    available_ports = length(port_list)

    if total_devices > available_ports do
      raise ArgumentError,
            "Not enough ports (#{available_ports}) for device count (#{total_devices})"
    end

    {assignments, _remaining_ports} =
      device_mix
      # Largest first
      |> Enum.sort_by(fn {_type, count} -> -count end)
      |> Enum.reduce({%{}, port_list}, fn {device_type, count}, {acc, remaining} ->
        {assigned_ports, new_remaining} = Enum.split(remaining, count)

        if length(assigned_ports) > 0 do
          range = build_range(assigned_ports)
          {Map.put(acc, device_type, range), new_remaining}
        else
          {acc, new_remaining}
        end
      end)

    assignments
  end

  @doc """
  Calculate population density statistics for device assignments.
  """
  @spec calculate_density_stats(port_assignments()) :: %{atom() => any()}
  def calculate_density_stats(port_assignments) do
    total_ports = count_total_ports(port_assignments)

    device_stats =
      port_assignments
      |> Enum.map(fn {device_type, range} ->
        count = Enum.count(range)
        percentage = if total_ports > 0, do: count / total_ports * 100, else: 0

        {device_type,
         %{
           count: count,
           percentage: Float.round(percentage, 2),
           port_range: range,
           density: calculate_density_category(percentage)
         }}
      end)
      |> Map.new()

    %{
      total_devices: total_ports,
      device_types: map_size(port_assignments),
      distribution: device_stats,
      largest_group: find_largest_group(device_stats),
      smallest_group: find_smallest_group(device_stats)
    }
  end

  @doc """
  Get device type characteristics and metadata.
  """
  @spec get_device_characteristics(device_type()) :: %{atom() => any()}
  def get_device_characteristics(:cable_modem) do
    %{
      typical_interfaces: 2,
      primary_protocols: [:docsis, :ethernet],
      expected_uptime_days: 30,
      traffic_pattern: :residential,
      signal_monitoring: true,
      error_rates: %{low: 0.001, medium: 0.01, high: 0.1}
    }
  end

  def get_device_characteristics(:mta) do
    %{
      typical_interfaces: 2,
      primary_protocols: [:docsis, :voip],
      expected_uptime_days: 30,
      traffic_pattern: :voice,
      signal_monitoring: true,
      error_rates: %{low: 0.0005, medium: 0.005, high: 0.05}
    }
  end

  def get_device_characteristics(:switch) do
    %{
      typical_interfaces: 24,
      primary_protocols: [:ethernet, :vlan],
      expected_uptime_days: 365,
      traffic_pattern: :aggregation,
      signal_monitoring: false,
      error_rates: %{low: 0.0001, medium: 0.001, high: 0.01}
    }
  end

  def get_device_characteristics(:router) do
    %{
      typical_interfaces: 8,
      primary_protocols: [:ip, :bgp, :ospf],
      expected_uptime_days: 365,
      traffic_pattern: :routing,
      signal_monitoring: false,
      error_rates: %{low: 0.0001, medium: 0.001, high: 0.01}
    }
  end

  def get_device_characteristics(:cmts) do
    %{
      typical_interfaces: 32,
      primary_protocols: [:docsis, :ethernet, :ip],
      expected_uptime_days: 365,
      traffic_pattern: :headend,
      signal_monitoring: true,
      error_rates: %{low: 0.00001, medium: 0.0001, high: 0.001}
    }
  end

  def get_device_characteristics(:server) do
    %{
      typical_interfaces: 4,
      primary_protocols: [:tcp, :http, :snmp],
      expected_uptime_days: 365,
      traffic_pattern: :server,
      signal_monitoring: false,
      error_rates: %{low: 0.0001, medium: 0.001, high: 0.01}
    }
  end

  def get_device_characteristics(_unknown) do
    %{
      typical_interfaces: 1,
      primary_protocols: [:unknown],
      expected_uptime_days: 1,
      traffic_pattern: :unknown,
      signal_monitoring: false,
      error_rates: %{low: 0.01, medium: 0.1, high: 1.0}
    }
  end

  @doc """
  Generate device ID with type-specific formatting.
  """
  @spec generate_device_id(device_type(), non_neg_integer(), keyword()) :: String.t()
  def generate_device_id(device_type, port, opts \\ []) do
    format = Keyword.get(opts, :format, :default)

    case format do
      :default -> "#{device_type}_#{port}"
      :mac_based -> generate_mac_based_id(device_type, port)
      :hostname -> generate_hostname_id(device_type, port)
      :serial -> generate_serial_id(device_type, port)
    end
  end

  @doc """
  Validate port assignments for consistency and coverage.
  """
  @spec validate_port_assignments(port_assignments()) :: :ok | {:error, term()}
  def validate_port_assignments(port_assignments) do
    with :ok <- validate_no_overlaps(port_assignments),
         :ok <- validate_all_ranges_valid(port_assignments),
         :ok <- validate_reasonable_distribution(port_assignments) do
      :ok
    end
  end

  # Private Functions

  defp build_range([]), do: 0..0
  defp build_range([single]), do: single..single

  defp build_range(ports) do
    min_port = Enum.min(ports)
    max_port = Enum.max(ports)

    # Check if ports are contiguous
    if max_port - min_port + 1 == length(ports) do
      min_port..max_port
    else
      # Non-contiguous, create range from min to max anyway
      # This could be enhanced to support multiple ranges per device type
      min_port..max_port
    end
  end

  defp count_total_ports(port_assignments) do
    Enum.reduce(port_assignments, 0, fn {_type, range}, acc ->
      acc + Enum.count(range)
    end)
  end

  defp calculate_density_category(percentage) when percentage >= 50, do: :dominant
  defp calculate_density_category(percentage) when percentage >= 20, do: :major
  defp calculate_density_category(percentage) when percentage >= 5, do: :moderate
  defp calculate_density_category(percentage) when percentage >= 1, do: :minor
  defp calculate_density_category(_percentage), do: :trace

  defp find_largest_group(device_stats) do
    device_stats
    |> Enum.max_by(fn {_type, stats} -> stats.count end)
    |> case do
      {type, stats} -> %{type: type, count: stats.count}
      nil -> nil
    end
  end

  defp find_smallest_group(device_stats) do
    device_stats
    |> Enum.min_by(fn {_type, stats} -> stats.count end)
    |> case do
      {type, stats} -> %{type: type, count: stats.count}
      nil -> nil
    end
  end

  defp generate_mac_based_id(device_type, port) do
    # Generate deterministic MAC-like ID based on device type and port
    type_code = get_type_code(device_type)
    port_hex = Integer.to_string(port, 16) |> String.pad_leading(4, "0")
    "#{type_code}:#{String.slice(port_hex, 0..1)}:#{String.slice(port_hex, 2..3)}:#{port_hex}"
  end

  defp generate_hostname_id(device_type, port) do
    prefix = get_hostname_prefix(device_type)
    "#{prefix}-#{String.pad_leading(Integer.to_string(port), 6, "0")}"
  end

  defp generate_serial_id(device_type, port) do
    prefix = get_serial_prefix(device_type)
    checksum = rem(port, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{prefix}#{String.pad_leading(Integer.to_string(port), 8, "0")}#{checksum}"
  end

  defp get_type_code(:cable_modem), do: "CM"
  defp get_type_code(:mta), do: "MT"
  defp get_type_code(:switch), do: "SW"
  defp get_type_code(:router), do: "RT"
  defp get_type_code(:cmts), do: "CT"
  defp get_type_code(:server), do: "SV"
  defp get_type_code(_), do: "UK"

  defp get_hostname_prefix(:cable_modem), do: "cm"
  defp get_hostname_prefix(:mta), do: "mta"
  defp get_hostname_prefix(:switch), do: "sw"
  defp get_hostname_prefix(:router), do: "rtr"
  defp get_hostname_prefix(:cmts), do: "cmts"
  defp get_hostname_prefix(:server), do: "srv"
  defp get_hostname_prefix(_), do: "unk"

  defp get_serial_prefix(:cable_modem), do: "SB"
  defp get_serial_prefix(:mta), do: "EM"
  defp get_serial_prefix(:switch), do: "WS"
  defp get_serial_prefix(:router), do: "ISR"
  defp get_serial_prefix(:cmts), do: "UBR"
  defp get_serial_prefix(:server), do: "DL"
  defp get_serial_prefix(_), do: "UNK"

  defp validate_no_overlaps(port_assignments) do
    ranges = Map.values(port_assignments)

    overlaps =
      for {range1, i} <- Enum.with_index(ranges),
          {range2, j} <- Enum.with_index(ranges),
          i < j,
          ranges_overlap?(range1, range2) do
        {range1, range2}
      end

    if length(overlaps) > 0 do
      {:error, {:overlapping_ranges, overlaps}}
    else
      :ok
    end
  end

  defp validate_all_ranges_valid(port_assignments) do
    invalid_ranges =
      Enum.filter(port_assignments, fn {_type, range} ->
        Range.size(range) <= 0 or range.first > range.last
      end)

    if length(invalid_ranges) > 0 do
      {:error, {:invalid_ranges, invalid_ranges}}
    else
      :ok
    end
  end

  defp validate_reasonable_distribution(port_assignments) do
    total_ports = count_total_ports(port_assignments)

    cond do
      map_size(port_assignments) == 0 ->
        {:error, :no_device_types}

      total_ports == 0 ->
        {:error, :empty_distribution}

      total_ports > 100_000 ->
        {:error, {:too_many_devices, total_ports}}

      true ->
        :ok
    end
  end

  defp ranges_overlap?(range1, range2) do
    not Range.disjoint?(range1, range2)
  end
end
