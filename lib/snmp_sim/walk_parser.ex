defmodule SnmpSim.WalkParser do
  @moduledoc """
  Parse both named MIB and numeric OID walk file formats.
  Handle different snmpwalk output variations automatically.
  """

  @doc """
  Parse a walk file and return a map of OID -> value mappings.

  Supports both named MIB format and numeric OID format:
  - Named: "IF-MIB::ifInOctets.2 = Counter32: 1234567890"
  - Numeric: ".1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890"

  ## Examples

      {:ok, oid_map} = SnmpSim.WalkParser.parse_walk_file("priv/walks/cable_modem.walk")
      
  """
  def parse_walk_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        oid_map =
          content
          |> String.split("\n")
          |> Enum.map(&parse_walk_line/1)
          |> Enum.reject(&is_nil/1)
          |> Map.new()

        {:ok, oid_map}

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Parse a single line from a walk file.

  ## Examples

      # Named MIB format
      result = SnmpSim.WalkParser.parse_walk_line("IF-MIB::ifInOctets.2 = Counter32: 1234567890")
      # => {"1.3.6.1.2.1.2.2.1.10.2", %{type: "Counter32", value: 1234567890, mib_name: "IF-MIB::ifInOctets.2"}}
      
      # Numeric OID format  
      result = SnmpSim.WalkParser.parse_walk_line(".1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890")
      # => {"1.3.6.1.2.1.2.2.1.10.2", %{type: "Counter32", value: 1234567890}}
      
  """
  def parse_walk_line(line) do
    line = String.trim(line)

    cond do
      # Named MIB format: "IF-MIB::ifInOctets.2 = Counter32: 1234567890"
      String.contains?(line, "::") ->
        parse_named_mib_line(line)

      # Numeric OID format: ".1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890"
      String.starts_with?(line, ".") ->
        parse_numeric_oid_line(line)

      # Skip comments and empty lines
      String.starts_with?(line, "#") or line == "" ->
        nil

      # Try generic parsing for other formats
      true ->
        parse_generic_line(line)
    end
  end

  # Parse named MIB format lines
  defp parse_named_mib_line(line) do
    case Regex.run(~r/^(.+?)::(.+?)\s*=\s*([\w-]+):\s*(.+)$/, line) do
      [_, mib_name, oid_suffix, data_type, value] ->
        numeric_oid = resolve_mib_name(mib_name, oid_suffix)
        parsed_value = parse_typed_value(value, data_type)

        {numeric_oid,
         %{
           type: data_type,
           value: parsed_value,
           mib_name: "#{mib_name}::#{oid_suffix}"
         }}

      _ ->
        nil
    end
  end

  # Parse numeric OID format lines
  defp parse_numeric_oid_line(line) do
    case Regex.run(~r/^(\.[\d\.]+)\s*=\s*([\w-]+):\s*(.+)$/, line) do
      [_, oid, data_type, value] ->
        clean_oid = String.trim_leading(oid, ".")
        parsed_value = parse_typed_value(value, data_type)

        {clean_oid, %{type: data_type, value: parsed_value}}

      _ ->
        nil
    end
  end

  # Parse other potential formats
  defp parse_generic_line(line) do
    case Regex.run(~r/^(.+?)\s*=\s*([\w-]+):\s*(.+)$/, line) do
      [_, oid_part, data_type, value] ->
        oid = normalize_oid(oid_part)
        parsed_value = parse_typed_value(value, data_type)

        {oid, %{type: data_type, value: parsed_value}}

      _ ->
        nil
    end
  end

  # Parse and convert values based on their SNMP data type
  defp parse_typed_value(value, data_type) do
    cleaned_value = clean_value(value)

    case String.upcase(data_type) do
      "INTEGER" -> parse_integer(cleaned_value)
      "COUNTER32" -> parse_integer(cleaned_value)
      "COUNTER64" -> parse_integer(cleaned_value)
      "GAUGE32" -> parse_integer(cleaned_value)
      "GAUGE" -> parse_integer(cleaned_value)
      "TIMETICKS" -> parse_timeticks(cleaned_value)
      "STRING" -> cleaned_value
      "OCTET" -> cleaned_value
      "HEX-STRING" -> parse_hex_string(cleaned_value)
      "OID" -> parse_oid_value(cleaned_value)
      "IPADDRESS" -> parse_ip_address(cleaned_value)
      _ -> cleaned_value
    end
  end

  # Clean up raw value strings
  defp clean_value(value) do
    value
    |> String.trim()
    # Remove quotes from strings
    |> String.trim("\"")
  end

  # Parse integer values, including named enums like "ethernetCsmacd(6)"
  defp parse_integer(value) do
    # First try to extract number from parentheses (for named enums)
    case Regex.run(~r/\((\d+)\)/, value) do
      [_, number_str] ->
        case Integer.parse(number_str) do
          {int_val, _} -> int_val
          :error -> 0
        end

      nil ->
        # Try to parse as regular integer
        case Integer.parse(value) do
          {int_val, _} -> int_val
          :error -> 0
        end
    end
  end

  # Parse timeticks with format like "(12345600) 1 day, 10:17:36.00"
  defp parse_timeticks(value) do
    case Regex.run(~r/^\((\d+)\)/, value) do
      [_, ticks] -> parse_integer(ticks)
      _ -> parse_integer(value)
    end
  end

  # Parse hex strings like "00 1A 2B 3C 4D 5E"
  defp parse_hex_string(value) do
    if Regex.match?(~r/^[0-9A-Fa-f\s]+$/, value) do
      value
      |> String.replace(" ", "")
      |> String.upcase()
    else
      value
    end
  end

  # Parse OID values that may start with dots or contain MIB names
  defp parse_oid_value(value) do
    cleaned_value = String.trim_leading(value, ".")
    
    # Handle SNMPv2-SMI::enterprises prefix
    case String.starts_with?(cleaned_value, "SNMPv2-SMI::enterprises.") do
      true ->
        # Replace SNMPv2-SMI::enterprises with 1.3.6.1.4.1
        suffix = String.replace_prefix(cleaned_value, "SNMPv2-SMI::enterprises.", "")
        oid_string = "1.3.6.1.4.1.#{suffix}"
        # Convert to OID list for object_identifier types
        oid_string
        |> String.split(".")
        |> Enum.map(&String.to_integer/1)
      false ->
        # For other OID values, just clean and return as string
        cleaned_value
    end
  end

  # Parse IP addresses
  defp parse_ip_address(value) do
    # Remove any surrounding formatting and return the IP
    value
    |> String.trim()
    |> String.trim("\"")
  end

  # Normalize OID format (remove leading dots, handle different formats)
  defp normalize_oid(oid_part) do
    oid_part
    |> String.trim()
    |> String.trim_leading(".")
  end

  # Basic MIB name resolution (can be extended with more comprehensive mapping)
  defp resolve_mib_name(mib_name, oid_suffix) do
    base_oids = %{
      "SNMPv2-MIB" => "1.3.6.1.2.1.1",
      "IF-MIB" => "1.3.6.1.2.1.2",
      "IP-MIB" => "1.3.6.1.2.1.4",
      "TCP-MIB" => "1.3.6.1.2.1.6",
      "UDP-MIB" => "1.3.6.1.2.1.7",
      "HOST-RESOURCES-MIB" => "1.3.6.1.2.1.25",
      "BRIDGE-MIB" => "1.3.6.1.2.1.17",
      "ENTITY-MIB" => "1.3.6.1.2.1.47",
      "CISCO-SMI" => "1.3.6.1.4.1.9",
      "DOCS-CABLE-DEVICE-MIB" => "1.3.6.1.2.1.69",
      "DOCS-IF-MIB" => "1.3.6.1.2.1.10.127"
    }

    # Try to resolve known MIB names
    case Map.get(base_oids, mib_name) do
      nil ->
        # Unknown MIB - try to extract numeric portion from suffix
        extract_numeric_oid(oid_suffix)

      base_oid ->
        # Combine base OID with suffix
        combine_oid_parts(base_oid, oid_suffix)
    end
  end

  # Extract numeric OID from suffix like "sysDescr.0" -> "1.0" or "ifInOctets.2" -> "10.2"
  defp extract_numeric_oid(oid_suffix) do
    # Common object mappings within standard MIBs
    object_mappings = %{
      "sysDescr" => "1.3.6.1.2.1.1.1",
      "sysObjectID" => "1.3.6.1.2.1.1.2",
      "sysUpTime" => "1.3.6.1.2.1.1.3",
      "sysContact" => "1.3.6.1.2.1.1.4",
      "sysName" => "1.3.6.1.2.1.1.5",
      "sysLocation" => "1.3.6.1.2.1.1.6",
      "sysServices" => "1.3.6.1.2.1.1.7",
      "ifNumber" => "1.3.6.1.2.1.2.1",
      "ifIndex" => "1.3.6.1.2.1.2.2.1.1",
      "ifDescr" => "1.3.6.1.2.1.2.2.1.2",
      "ifType" => "1.3.6.1.2.1.2.2.1.3",
      "ifMtu" => "1.3.6.1.2.1.2.2.1.4",
      "ifSpeed" => "1.3.6.1.2.1.2.2.1.5",
      "ifPhysAddress" => "1.3.6.1.2.1.2.2.1.6",
      "ifAdminStatus" => "1.3.6.1.2.1.2.2.1.7",
      "ifOperStatus" => "1.3.6.1.2.1.2.2.1.8",
      "ifLastChange" => "1.3.6.1.2.1.2.2.1.9",
      "ifInOctets" => "1.3.6.1.2.1.2.2.1.10",
      "ifInUcastPkts" => "1.3.6.1.2.1.2.2.1.11",
      "ifInNUcastPkts" => "1.3.6.1.2.1.2.2.1.12",
      "ifInDiscards" => "1.3.6.1.2.1.2.2.1.13",
      "ifInErrors" => "1.3.6.1.2.1.2.2.1.14",
      "ifInUnknownProtos" => "1.3.6.1.2.1.2.2.1.15",
      "ifOutOctets" => "1.3.6.1.2.1.2.2.1.16",
      "ifOutUcastPkts" => "1.3.6.1.2.1.2.2.1.17",
      "ifOutNUcastPkts" => "1.3.6.1.2.1.2.2.1.18",
      "ifOutDiscards" => "1.3.6.1.2.1.2.2.1.19",
      "ifOutErrors" => "1.3.6.1.2.1.2.2.1.20",
      "ifOutQLen" => "1.3.6.1.2.1.2.2.1.21"
    }

    case Regex.run(~r/^([^.]+)\.(.+)$/, oid_suffix) do
      [_, object_name, instance] ->
        case Map.get(object_mappings, object_name) do
          # Return as-is if unknown
          nil -> oid_suffix
          base_oid -> "#{base_oid}.#{instance}"
        end

      _ ->
        # Return as-is if no instance part
        oid_suffix
    end
  end

  # Combine base OID with suffix intelligently
  defp combine_oid_parts(base_oid, oid_suffix) do
    # Handle different suffix formats
    case Regex.run(~r/^([^.]+)\.(.+)$/, oid_suffix) do
      [_, object_name, instance] ->
        # Map object names to their sub-OIDs within the MIB
        object_oid =
          case object_name do
            "sysDescr" -> "#{base_oid}.1"
            "sysObjectID" -> "#{base_oid}.2"
            "sysUpTime" -> "#{base_oid}.3"
            "sysContact" -> "#{base_oid}.4"
            "sysName" -> "#{base_oid}.5"
            "sysLocation" -> "#{base_oid}.6"
            "sysServices" -> "#{base_oid}.7"
            "ifNumber" -> "#{base_oid}.1"
            "ifIndex" -> "#{base_oid}.2.1.1"
            "ifDescr" -> "#{base_oid}.2.1.2"
            "ifType" -> "#{base_oid}.2.1.3"
            "ifMtu" -> "#{base_oid}.2.1.4"
            "ifSpeed" -> "#{base_oid}.2.1.5"
            "ifPhysAddress" -> "#{base_oid}.2.1.6"
            "ifAdminStatus" -> "#{base_oid}.2.1.7"
            "ifOperStatus" -> "#{base_oid}.2.1.8"
            "ifLastChange" -> "#{base_oid}.2.1.9"
            "ifInOctets" -> "#{base_oid}.2.1.10"
            "ifInUcastPkts" -> "#{base_oid}.2.1.11"
            "ifInNUcastPkts" -> "#{base_oid}.2.1.12"
            "ifInDiscards" -> "#{base_oid}.2.1.13"
            "ifInErrors" -> "#{base_oid}.2.1.14"
            "ifInUnknownProtos" -> "#{base_oid}.2.1.15"
            "ifOutOctets" -> "#{base_oid}.2.1.16"
            "ifOutUcastPkts" -> "#{base_oid}.2.1.17"
            "ifOutNUcastPkts" -> "#{base_oid}.2.1.18"
            "ifOutDiscards" -> "#{base_oid}.2.1.19"
            "ifOutErrors" -> "#{base_oid}.2.1.20"
            "ifOutQLen" -> "#{base_oid}.2.1.21"
            # Default
            _ -> "#{base_oid}.1"
          end

        "#{object_oid}.#{instance}"

      _ ->
        # Simple scalar object
        "#{base_oid}.0"
    end
  end
end
