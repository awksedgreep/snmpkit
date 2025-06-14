defmodule SnmpKit.SnmpLib.MIB.Registry do
  @moduledoc """
  Standard SNMP MIB registry with name/OID resolution functions.

  Provides the standard SNMP MIB objects and core resolution functionality
  that can be used by any SNMP application (managers, simulators, etc.).
  """

  require Logger

  @standard_mibs %{
    # System group (1.3.6.1.2.1.1)
    "sysDescr" => [1, 3, 6, 1, 2, 1, 1, 1],
    "sysObjectID" => [1, 3, 6, 1, 2, 1, 1, 2],
    "sysUpTime" => [1, 3, 6, 1, 2, 1, 1, 3],
    "sysContact" => [1, 3, 6, 1, 2, 1, 1, 4],
    "sysName" => [1, 3, 6, 1, 2, 1, 1, 5],
    "sysLocation" => [1, 3, 6, 1, 2, 1, 1, 6],
    "sysServices" => [1, 3, 6, 1, 2, 1, 1, 7],

    # Interface group (1.3.6.1.2.1.2)
    "ifNumber" => [1, 3, 6, 1, 2, 1, 2, 1],
    "ifTable" => [1, 3, 6, 1, 2, 1, 2, 2],
    "ifEntry" => [1, 3, 6, 1, 2, 1, 2, 2, 1],
    "ifIndex" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 1],
    "ifDescr" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 2],
    "ifType" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 3],
    "ifMtu" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 4],
    "ifSpeed" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 5],
    "ifPhysAddress" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 6],
    "ifAdminStatus" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 7],
    "ifOperStatus" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 8],
    "ifLastChange" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 9],
    "ifInOctets" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 10],
    "ifInUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 11],
    "ifInNUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 12],
    "ifInDiscards" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 13],
    "ifInErrors" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 14],
    "ifInUnknownProtos" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 15],
    "ifOutOctets" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 16],
    "ifOutUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 17],
    "ifOutNUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 18],
    "ifOutDiscards" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 19],
    "ifOutErrors" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 20],
    "ifOutQLen" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 21],
    "ifSpecific" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 22],

    # IP group (1.3.6.1.2.1.4)
    "ipForwarding" => [1, 3, 6, 1, 2, 1, 4, 1],
    "ipDefaultTTL" => [1, 3, 6, 1, 2, 1, 4, 2],
    "ipInReceives" => [1, 3, 6, 1, 2, 1, 4, 3],
    "ipInHdrErrors" => [1, 3, 6, 1, 2, 1, 4, 4],
    "ipInAddrErrors" => [1, 3, 6, 1, 2, 1, 4, 5],

    # SNMP group (1.3.6.1.2.1.11)
    "snmpInPkts" => [1, 3, 6, 1, 2, 1, 11, 1],
    "snmpOutPkts" => [1, 3, 6, 1, 2, 1, 11, 2],
    "snmpInBadVersions" => [1, 3, 6, 1, 2, 1, 11, 3],
    "snmpInBadCommunityNames" => [1, 3, 6, 1, 2, 1, 11, 4],
    "snmpInBadCommunityUses" => [1, 3, 6, 1, 2, 1, 11, 5],
    "snmpInASNParseErrs" => [1, 3, 6, 1, 2, 1, 11, 6],
    "snmpInTooBigs" => [1, 3, 6, 1, 2, 1, 11, 8],
    "snmpInNoSuchNames" => [1, 3, 6, 1, 2, 1, 11, 9],
    "snmpInBadValues" => [1, 3, 6, 1, 2, 1, 11, 10],
    "snmpInReadOnlys" => [1, 3, 6, 1, 2, 1, 11, 11],
    "snmpInGenErrs" => [1, 3, 6, 1, 2, 1, 11, 12],
    "snmpInTotalReqVars" => [1, 3, 6, 1, 2, 1, 11, 13],
    "snmpInTotalSetVars" => [1, 3, 6, 1, 2, 1, 11, 14],
    "snmpInGetRequests" => [1, 3, 6, 1, 2, 1, 11, 15],
    "snmpInGetNexts" => [1, 3, 6, 1, 2, 1, 11, 16],
    "snmpInSetRequests" => [1, 3, 6, 1, 2, 1, 11, 17],
    "snmpInGetResponses" => [1, 3, 6, 1, 2, 1, 11, 18],
    "snmpInTraps" => [1, 3, 6, 1, 2, 1, 11, 19],
    "snmpOutTooBigs" => [1, 3, 6, 1, 2, 1, 11, 20],
    "snmpOutNoSuchNames" => [1, 3, 6, 1, 2, 1, 11, 21],
    "snmpOutBadValues" => [1, 3, 6, 1, 2, 1, 11, 22],
    "snmpOutGenErrs" => [1, 3, 6, 1, 2, 1, 11, 24],
    "snmpOutGetRequests" => [1, 3, 6, 1, 2, 1, 11, 25],
    "snmpOutGetNexts" => [1, 3, 6, 1, 2, 1, 11, 26],
    "snmpOutSetRequests" => [1, 3, 6, 1, 2, 1, 11, 27],
    "snmpOutGetResponses" => [1, 3, 6, 1, 2, 1, 11, 28],
    "snmpOutTraps" => [1, 3, 6, 1, 2, 1, 11, 29],
    "snmpEnableAuthenTraps" => [1, 3, 6, 1, 2, 1, 11, 30],

    # TCP group (1.3.6.1.2.1.6)
    "tcpRtoAlgorithm" => [1, 3, 6, 1, 2, 1, 6, 1],
    "tcpRtoMin" => [1, 3, 6, 1, 2, 1, 6, 2],
    "tcpRtoMax" => [1, 3, 6, 1, 2, 1, 6, 3],
    "tcpMaxConn" => [1, 3, 6, 1, 2, 1, 6, 4],
    "tcpActiveOpens" => [1, 3, 6, 1, 2, 1, 6, 5],
    "tcpPassiveOpens" => [1, 3, 6, 1, 2, 1, 6, 6],
    "tcpAttemptFails" => [1, 3, 6, 1, 2, 1, 6, 7],
    "tcpEstabResets" => [1, 3, 6, 1, 2, 1, 6, 8],
    "tcpCurrEstab" => [1, 3, 6, 1, 2, 1, 6, 9],
    "tcpInSegs" => [1, 3, 6, 1, 2, 1, 6, 10],
    "tcpOutSegs" => [1, 3, 6, 1, 2, 1, 6, 11],
    "tcpRetransSegs" => [1, 3, 6, 1, 2, 1, 6, 12],
    "tcpConnTable" => [1, 3, 6, 1, 2, 1, 6, 13],
    "tcpInErrs" => [1, 3, 6, 1, 2, 1, 6, 14],
    "tcpOutRsts" => [1, 3, 6, 1, 2, 1, 6, 15],

    # UDP group (1.3.6.1.2.1.7)
    "udpInDatagrams" => [1, 3, 6, 1, 2, 1, 7, 1],
    "udpNoPorts" => [1, 3, 6, 1, 2, 1, 7, 2],
    "udpInErrors" => [1, 3, 6, 1, 2, 1, 7, 3],
    "udpOutDatagrams" => [1, 3, 6, 1, 2, 1, 7, 4],
    "udpTable" => [1, 3, 6, 1, 2, 1, 7, 5],

    # Host Resources MIB (1.3.6.1.2.1.25)
    "hrSystemUptime" => [1, 3, 6, 1, 2, 1, 25, 1, 1],
    "hrSystemDate" => [1, 3, 6, 1, 2, 1, 25, 1, 2],
    "hrSystemInitialLoadDevice" => [1, 3, 6, 1, 2, 1, 25, 1, 3],
    "hrSystemInitialLoadParameters" => [1, 3, 6, 1, 2, 1, 25, 1, 4],
    "hrSystemNumUsers" => [1, 3, 6, 1, 2, 1, 25, 1, 5],
    "hrSystemProcesses" => [1, 3, 6, 1, 2, 1, 25, 1, 6],
    "hrSystemMaxProcesses" => [1, 3, 6, 1, 2, 1, 25, 1, 7],
    "hrMemorySize" => [1, 3, 6, 1, 2, 1, 25, 2, 2],
    "hrStorageTable" => [1, 3, 6, 1, 2, 1, 25, 2, 3],
    "hrDeviceTable" => [1, 3, 6, 1, 2, 1, 25, 3, 2],
    "hrProcessorTable" => [1, 3, 6, 1, 2, 1, 25, 3, 3],
    "hrNetworkTable" => [1, 3, 6, 1, 2, 1, 25, 3, 4],
    "hrPrinterTable" => [1, 3, 6, 1, 2, 1, 25, 3, 5],
    "hrDiskStorageTable" => [1, 3, 6, 1, 2, 1, 25, 3, 6],

    # Common Enterprise OIDs
    "enterprises" => [1, 3, 6, 1, 4, 1],

    # Cisco Enterprise OIDs (1.3.6.1.4.1.9)
    "cisco" => [1, 3, 6, 1, 4, 1, 9],
    "ciscoMgmt" => [1, 3, 6, 1, 4, 1, 9, 9],
    "ciscoCPUTotal5min" => [1, 3, 6, 1, 4, 1, 9, 9, 109, 1, 1, 1, 1, 8],
    "ciscoMemoryPoolUsed" => [1, 3, 6, 1, 4, 1, 9, 9, 48, 1, 1, 1, 5],
    "ciscoMemoryPoolFree" => [1, 3, 6, 1, 4, 1, 9, 9, 48, 1, 1, 1, 6],

    # HP Enterprise OIDs (1.3.6.1.4.1.11)
    "hp" => [1, 3, 6, 1, 4, 1, 11],

    # Dell Enterprise OIDs (1.3.6.1.4.1.674)
    "dell" => [1, 3, 6, 1, 4, 1, 674],

    # IBM Enterprise OIDs (1.3.6.1.4.1.2)
    "ibm" => [1, 3, 6, 1, 4, 1, 2],

    # Microsoft Enterprise OIDs (1.3.6.1.4.1.311)
    "microsoft" => [1, 3, 6, 1, 4, 1, 311],

    # Net-SNMP Enterprise OIDs (1.3.6.1.4.1.8072)
    "netSnmp" => [1, 3, 6, 1, 4, 1, 8072],
    "netSnmpAgentOIDs" => [1, 3, 6, 1, 4, 1, 8072, 3, 2],
    "ucdExperimental" => [1, 3, 6, 1, 4, 1, 2021, 13]
  }

  @doc """
  Get the standard MIB registry map.
  """
  def standard_mibs, do: @standard_mibs

  @doc """
  Get the reverse lookup map (OID -> name).
  """
  def standard_mibs_reverse, do: build_reverse_map(@standard_mibs)

  @doc """
  Resolve a MIB name to an OID list.
  Handles instance notation like "sysDescr.0".

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Registry.resolve_name("sysDescr.0")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}

      iex> SnmpKit.SnmpLib.MIB.Registry.resolve_name("sysDescr")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1]}

      iex> SnmpKit.SnmpLib.MIB.Registry.resolve_name("unknownName")
      {:error, :not_found}
  """
  def resolve_name(name), do: resolve_name(name, @standard_mibs)

  @doc """
  Reverse lookup an OID to get the MIB name.
  Handles partial matches and instances.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:ok, "sysDescr.0"}

      iex> SnmpKit.SnmpLib.MIB.Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1])
      {:ok, "sysDescr"}
  """
  def reverse_lookup(oid), do: reverse_lookup_oid(oid, standard_mibs_reverse())

  @doc """
  Find direct children of a parent OID.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Registry.children([1, 3, 6, 1, 2, 1, 1])
      {:ok, ["sysContact", "sysDescr", "sysLocation", "sysName", "sysObjectID", "sysServices", "sysUpTime"]}
  """
  def children(parent_oid), do: find_children(parent_oid, @standard_mibs)

  @doc """
  Walk the MIB tree from a root OID.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Registry.walk_tree([1, 3, 6, 1, 2, 1, 1])
      {:ok, [{"sysDescr", [1, 3, 6, 1, 2, 1, 1, 1]}, {"sysObjectID", [1, 3, 6, 1, 2, 1, 1, 2]}, ...]}
  """
  def walk_tree(root_oid), do: walk_tree_from_root(root_oid, @standard_mibs)

  # Private helper functions

  defp resolve_name(name, name_to_oid_map) do
    cond do
      # Handle nil or invalid names first
      is_nil(name) or not is_binary(name) ->
        {:error, :invalid_name}

      # Direct match
      Map.has_key?(name_to_oid_map, name) ->
        {:ok, Map.get(name_to_oid_map, name)}

      # Name with instance (e.g., "sysDescr.0")
      String.contains?(name, ".") ->
        [base_name | instance_parts] = String.split(name, ".")

        case Map.get(name_to_oid_map, base_name) do
          nil ->
            {:error, :not_found}

          base_oid ->
            try do
              instance_oids = Enum.map(instance_parts, &String.to_integer/1)
              {:ok, base_oid ++ instance_oids}
            rescue
              _error -> {:error, :invalid_instance}
            end
        end

      true ->
        {:error, :not_found}
    end
  end

  defp reverse_lookup_oid(oid, oid_to_name_map) do
    case Map.get(oid_to_name_map, oid) do
      nil ->
        # Try to find a partial match
        find_partial_reverse_match(oid, oid_to_name_map)

      name ->
        {:ok, name}
    end
  end

  defp find_partial_reverse_match(oid, oid_to_name_map) do
    # Handle case where oid might be a string instead of list
    if is_binary(oid) do
      {:error, :invalid_oid_format}
    else
      # Handle empty list case
      if Enum.empty?(oid) do
        {:error, :empty_oid}
      else
        # Try progressively shorter OIDs to find a base match
        find_partial_match(oid, oid_to_name_map, length(oid) - 1)
      end
    end
  end

  defp find_partial_match(_oid, _map, length) when length <= 0, do: {:error, :not_found}

  defp find_partial_match(oid, oid_to_name_map, length) do
    partial_oid = Enum.take(oid, length)

    case Map.get(oid_to_name_map, partial_oid) do
      nil ->
        find_partial_match(oid, oid_to_name_map, length - 1)

      base_name ->
        instance_part = Enum.drop(oid, length)

        if Enum.empty?(instance_part) do
          {:ok, base_name}
        else
          instance_string = Enum.join(instance_part, ".")
          {:ok, "#{base_name}.#{instance_string}"}
        end
    end
  end

  defp find_children(parent_oid, name_to_oid_map) do
    normalized_oid =
      cond do
        is_nil(parent_oid) ->
          []

        is_binary(parent_oid) ->
          case SnmpLib.OID.string_to_list(parent_oid) do
            {:ok, oid_list} -> oid_list
            {:error, _} -> []
          end

        is_list(parent_oid) ->
          parent_oid

        true ->
          []
      end

    # Return error for invalid OIDs
    if normalized_oid == [] and not is_nil(parent_oid) do
      {:error, :invalid_parent_oid}
    else
      children =
        name_to_oid_map
        |> Enum.filter(fn {_name, oid} ->
          is_list(oid) and is_list(normalized_oid) and
            length(oid) == length(normalized_oid) + 1 and
            List.starts_with?(oid, normalized_oid)
        end)
        |> Enum.map(fn {name, _oid} -> name end)
        |> Enum.sort()

      {:ok, children}
    end
  end

  defp walk_tree_from_root(root_oid, name_to_oid_map) do
    root_oid =
      cond do
        is_binary(root_oid) ->
          case SnmpLib.OID.string_to_list(root_oid) do
            {:ok, oid_list} -> oid_list
            {:error, _} -> []
          end

        is_list(root_oid) ->
          root_oid

        is_nil(root_oid) ->
          []

        true ->
          []
      end

    descendants =
      name_to_oid_map
      |> Enum.filter(fn {_name, oid} ->
        is_list(oid) and List.starts_with?(oid, root_oid)
      end)
      |> Enum.map(fn {name, oid} -> {name, oid} end)
      |> Enum.sort_by(fn {_name, oid} -> oid end)

    {:ok, descendants}
  end

  defp build_reverse_map(name_to_oid_map) do
    name_to_oid_map
    |> Enum.map(fn {name, oid} -> {oid, name} end)
    |> Enum.into(%{})
  end
end
