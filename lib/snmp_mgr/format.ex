defmodule SnmpMgr.Format do
  @moduledoc """
  SNMP data formatting and presentation utilities.
  
  This module provides user-friendly formatting functions for SNMP data types,
  delegating to the underlying SnmpLib.Types functions while maintaining a
  clean SnmpMgr API surface.
  
  All functions work with the 3-tuple format `{oid_string, type, value}` that
  SnmpMgr uses throughout the library.
  
  ## Examples
  
      # Format uptime from SNMP result
      {:ok, {_oid, :timeticks, ticks}} = SnmpMgr.get("router.local", "sysUpTime.0")
      SnmpMgr.Format.uptime(ticks)
      # => "5 days, 12 hours, 34 minutes, 56 seconds"
      
      # Format IP address
      SnmpMgr.Format.ip_address(<<192, 168, 1, 1>>)
      # => "192.168.1.1"
      
      # Pretty print any SNMP result
      {:ok, result} = SnmpMgr.get("router.local", "sysDescr.0")
      SnmpMgr.Format.pretty_print(result)
      # => {"1.3.6.1.2.1.1.1.0", :octet_string, "Cisco IOS Router"}
  """

  # Delegate core formatting functions to SnmpLib.Types
  # These have negligible performance overhead (~1-2ns per call)
  
  @doc """
  Formats timeticks (hundredths of seconds) into human-readable uptime.
  
  ## Examples
  
      iex> SnmpMgr.Format.uptime(12345678)
      "1 day, 10 hours, 17 minutes, 36 seconds"
      
      iex> SnmpMgr.Format.uptime(4200)
      "42 seconds"
  """
  defdelegate uptime(ticks), to: SnmpLib.Types, as: :format_timeticks_uptime

  @doc """
  Formats IP address bytes into dotted decimal notation.
  
  ## Examples
  
      iex> SnmpMgr.Format.ip_address(<<192, 168, 1, 1>>)
      "192.168.1.1"
      
      iex> SnmpMgr.Format.ip_address({10, 0, 0, 1})
      "10.0.0.1"
  """
  def ip_address(ip_bytes) when is_binary(ip_bytes) do
    SnmpLib.Types.format_ip_address(ip_bytes)
  end
  
  def ip_address({a, b, c, d}) when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 do
    SnmpLib.Types.format_ip_address(<<a, b, c, d>>)
  end
  
  def ip_address(other), do: inspect(other)

  @doc """
  Pretty prints an SNMP result with type-aware formatting.
  
  Takes a 3-tuple `{oid_string, type, value}` and returns a formatted version
  with human-readable values based on the SNMP type.
  
  ## Examples
  
      iex> SnmpMgr.Format.pretty_print({"1.3.6.1.2.1.1.3.0", :timeticks, 12345678})
      {"1.3.6.1.2.1.1.3.0", :timeticks, "1 day, 10 hours, 17 minutes, 36 seconds"}
      
      iex> SnmpMgr.Format.pretty_print({"1.3.6.1.2.1.4.20.1.1.192.168.1.1", :ip_address, <<192, 168, 1, 1>>})
      {"1.3.6.1.2.1.4.20.1.1.192.168.1.1", :ip_address, "192.168.1.1"}
  """
  def pretty_print({oid, type, value}) do
    formatted_value = case type do
      :timeticks -> 
        uptime(value)
      :ip_address -> 
        ip_address(value)
      :counter32 -> 
        "#{value} (Counter32)"
      :counter64 -> 
        "#{value} (Counter64)"
      :gauge32 -> 
        "#{value} (Gauge32)"
      :unsigned32 -> 
        "#{value} (Unsigned32)"
      :octet_string -> 
        inspect(value)
      :object_identifier ->
        case value do
          oid_list when is_list(oid_list) -> Enum.join(oid_list, ".")
          oid_string when is_binary(oid_string) -> oid_string
          other -> inspect(other)
        end
      _ -> 
        inspect(value)
    end
    
    {oid, type, formatted_value}
  end
  
  @doc """
  Pretty prints a list of SNMP results.
  
  ## Examples
  
      iex> results = [
      ...>   {"1.3.6.1.2.1.1.3.0", :timeticks, 12345678},
      ...>   {"1.3.6.1.2.1.1.1.0", :octet_string, "Router"}
      ...> ]
      iex> SnmpMgr.Format.pretty_print_all(results)
      [
        {"1.3.6.1.2.1.1.3.0", :timeticks, "1 day, 10 hours, 17 minutes, 36 seconds"},
        {"1.3.6.1.2.1.1.1.0", :octet_string, "\"Router\""}
      ]
  """
  def pretty_print_all(results) when is_list(results) do
    Enum.map(results, &pretty_print/1)
  end

  @doc """
  Automatically formats a value based on its SNMP type.
  
  This function provides a single entry point for type-aware formatting,
  automatically choosing the appropriate formatting function based on the type.
  
  ## Examples
  
      iex> SnmpMgr.Format.format_by_type(:timeticks, 126691300)
      "14 days 15 hours 55 minutes 13 seconds"
      
      iex> SnmpMgr.Format.format_by_type(:gauge32, 1000000000)
      "1 GB"
      
      iex> SnmpMgr.Format.format_by_type(:octet_string, "Hello")
      "Hello"
      
  """
  @spec format_by_type(atom(), any()) :: String.t()
  def format_by_type(:timeticks, value), do: uptime(value)
  def format_by_type(:gauge32, value) when is_integer(value) and value > 1_000_000, do: bytes(value)
  def format_by_type(:counter32, value) when is_integer(value) and value > 1_000_000, do: speed(value)
  def format_by_type(:counter64, value) when is_integer(value) and value > 1_000_000, do: speed(value)
  def format_by_type(:integer, 1), do: interface_status(1)
  def format_by_type(:integer, 2), do: interface_status(2)
  def format_by_type(:integer, value) when is_integer(value) and value in 1..200, do: interface_type(value)
  def format_by_type(:ip_address, value), do: ip_address(value)
  def format_by_type(:mac_address, value), do: mac_address(value)
  # Auto-detect MAC addresses in octet strings (6 bytes = MAC address)
  def format_by_type(:octet_string, value) when is_binary(value) and byte_size(value) == 6, do: mac_address(value)
  def format_by_type(_type, value) when is_binary(value), do: value
  def format_by_type(_type, value) when is_integer(value), do: Integer.to_string(value)
  def format_by_type(_type, value) when is_atom(value), do: Atom.to_string(value)
  def format_by_type(_type, value), do: inspect(value)

  @doc """
  Formats byte counts into human-readable sizes.
  
  ## Examples
  
      iex> SnmpMgr.Format.bytes(1024)
      "1.0 KB"
      
      iex> SnmpMgr.Format.bytes(1073741824)
      "1.0 GB"
  """
  def bytes(byte_count) when is_integer(byte_count) and byte_count >= 0 do
    cond do
      byte_count >= 1_099_511_627_776 -> "#{Float.round(byte_count / 1_099_511_627_776, 1)} TB"
      byte_count >= 1_073_741_824 -> "#{Float.round(byte_count / 1_073_741_824, 1)} GB"
      byte_count >= 1_048_576 -> "#{Float.round(byte_count / 1_048_576, 1)} MB"
      byte_count >= 1_024 -> "#{Float.round(byte_count / 1_024, 1)} KB"
      true -> "#{byte_count} bytes"
    end
  end
  
  def bytes(other), do: inspect(other)

  @doc """
  Formats network speeds (bits per second) into human-readable rates.
  
  ## Examples
  
      iex> SnmpMgr.Format.speed(100_000_000)
      "100.0 Mbps"
      
      iex> SnmpMgr.Format.speed(1_000_000_000)
      "1.0 Gbps"
  """
  def speed(bps) when is_integer(bps) and bps >= 0 do
    cond do
      bps >= 1_000_000_000_000 -> "#{Float.round(bps / 1_000_000_000_000, 1)} Tbps"
      bps >= 1_000_000_000 -> "#{Float.round(bps / 1_000_000_000, 1)} Gbps"
      bps >= 1_000_000 -> "#{Float.round(bps / 1_000_000, 1)} Mbps"
      bps >= 1_000 -> "#{Float.round(bps / 1_000, 1)} Kbps"
      true -> "#{bps} bps"
    end
  end
  
  def speed(other), do: inspect(other)

  @doc """
  Formats SNMP interface status values into readable strings.
  
  ## Examples
  
      iex> SnmpMgr.Format.interface_status(1)
      "up"
      
      iex> SnmpMgr.Format.interface_status(2)
      "down"
  """
  def interface_status(1), do: "up"
  def interface_status(2), do: "down"
  def interface_status(3), do: "testing"
  def interface_status(4), do: "unknown"
  def interface_status(5), do: "dormant"
  def interface_status(6), do: "notPresent"
  def interface_status(7), do: "lowerLayerDown"
  def interface_status(other), do: "unknown(#{other})"

  @doc """
  Formats SNMP interface types into readable strings.
  
  ## Examples
  
      iex> SnmpMgr.Format.interface_type(6)
      "ethernetCsmacd"
      
      iex> SnmpMgr.Format.interface_type(24)
      "softwareLoopback"
  """
  def interface_type(1), do: "other"
  def interface_type(6), do: "ethernetCsmacd"
  def interface_type(24), do: "softwareLoopback"
  def interface_type(131), do: "tunnel"
  def interface_type(161), do: "ieee80211"
  def interface_type(other), do: "type#{other}"

  @doc """
  Formats MAC addresses into standard colon-separated hex format.
  
  Handles both binary and list representations of MAC addresses commonly
  found in SNMP responses.
  
  ## Examples
  
      iex> SnmpMgr.Format.mac_address(<<0x00, 0x1B, 0x21, 0x3C, 0x4D, 0x5E>>)
      "00:1b:21:3c:4d:5e"
      
      iex> SnmpMgr.Format.mac_address([0, 27, 33, 60, 77, 94])
      "00:1b:21:3c:4d:5e"
      
      iex> SnmpMgr.Format.mac_address("\\x00\\x1B\\x21\\x3C\\x4D\\x5E")
      "00:1b:21:3c:4d:5e"
      
  """
  @spec mac_address(binary() | list() | String.t()) :: String.t()
  def mac_address(mac) when is_binary(mac) and byte_size(mac) == 6 do
    mac
    |> :binary.bin_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(":")
  end
  
  def mac_address(mac) when is_list(mac) and length(mac) == 6 do
    mac
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(":")
  end
  
  def mac_address(mac) when is_binary(mac) do
    # Handle string representation with escape sequences
    case String.length(mac) do
      6 ->
        mac
        |> String.to_charlist()
        |> Enum.map(&Integer.to_string(&1, 16))
        |> Enum.map(&String.downcase/1)
        |> Enum.map(&String.pad_leading(&1, 2, "0"))
        |> Enum.join(":")
      _ ->
        # If it's already formatted or unknown format, return as-is
        to_string(mac)
    end
  end
  
  def mac_address(mac), do: inspect(mac)
end
