defmodule SnmpKit.SnmpMgr.MIB do
  @compile {:no_warn_undefined, [:snmpc, :snmp_misc]}

  @moduledoc """
  MIB compilation and symbolic name resolution.

  This module provides MIB compilation using Erlang's :snmpc when available,
  and includes a built-in registry of standard MIB objects for basic operations.
  """

  use GenServer
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

    # Interface Extensions (ifX) group (1.3.6.1.2.1.31)
    "ifXTable" => [1, 3, 6, 1, 2, 1, 31, 1],
    "ifXEntry" => [1, 3, 6, 1, 2, 1, 31, 1, 1],
    "ifName" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 1],
    "ifInMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 2],
    "ifInBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 3],
    "ifOutMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 4],
    "ifOutBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 5],
    "ifHCInOctets" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 6],
    "ifHCInUcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 7],
    "ifHCInMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 8],
    "ifHCInBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 9],
    "ifHCOutOctets" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 10],
    "ifHCOutUcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 11],
    "ifHCOutMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 12],
    "ifHCOutBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 13],
    "ifLinkUpDownTrapEnable" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 14],
    "ifHighSpeed" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 15],
    "ifPromiscuousMode" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 16],
    "ifConnectorPresent" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 17],
    "ifAlias" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 18],
    "ifCounterDiscontinuityTime" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 19],

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

    # Common group prefixes for bulk walking
    "system" => [1, 3, 6, 1, 2, 1, 1],
    "interfaces" => [1, 3, 6, 1, 2, 1, 2],
    "if" => [1, 3, 6, 1, 2, 1, 2],
    "ifX" => [1, 3, 6, 1, 2, 1, 31],
    "ip" => [1, 3, 6, 1, 2, 1, 4],
    "icmp" => [1, 3, 6, 1, 2, 1, 5],
    "tcp" => [1, 3, 6, 1, 2, 1, 6],
    "udp" => [1, 3, 6, 1, 2, 1, 7],
    "snmp" => [1, 3, 6, 1, 2, 1, 11],
    "mib-2" => [1, 3, 6, 1, 2, 1],
    "mgmt" => [1, 3, 6, 1, 2],
    "internet" => [1, 3, 6, 1],

    # Common enterprise OIDs
    "enterprises" => [1, 3, 6, 1, 4, 1],
    "cisco" => [1, 3, 6, 1, 4, 1, 9],
    "hp" => [1, 3, 6, 1, 4, 1, 11],
    "3com" => [1, 3, 6, 1, 4, 1, 43],
    "sun" => [1, 3, 6, 1, 4, 1, 42],
    "dec" => [1, 3, 6, 1, 4, 1, 36],
    "ibm" => [1, 3, 6, 1, 4, 1, 2],
    "microsoft" => [1, 3, 6, 1, 4, 1, 311],
    "netapp" => [1, 3, 6, 1, 4, 1, 789],
    "juniper" => [1, 3, 6, 1, 4, 1, 2636],
    "fortinet" => [1, 3, 6, 1, 4, 1, 12356],
    "paloalto" => [1, 3, 6, 1, 4, 1, 25461],
    "mikrotik" => [1, 3, 6, 1, 4, 1, 14988],

    # Cable/DOCSIS industry OIDs
    "cablelabs" => [1, 3, 6, 1, 4, 1, 4491],
    "docsis" => [1, 3, 6, 1, 2, 1, 127],
    "cableDataPrivateMib" => [1, 3, 6, 1, 4, 1, 4491, 2, 1],
    "arris" => [1, 3, 6, 1, 4, 1, 4115],
    "motorola" => [1, 3, 6, 1, 4, 1, 1166],
    "scientificatlanta" => [1, 3, 6, 1, 4, 1, 1429],
    "broadcom" => [1, 3, 6, 1, 4, 1, 4413]
  }

  ## Public API

  @doc """
  Starts the MIB registry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Compiles a MIB file using SnmpKit.SnmpLib.MIB pure Elixir implementation.

  Enhanced to use SnmpKit.SnmpLib.MIB for improved compilation with better error handling.

  ## Examples

      iex> SnmpKit.SnmpMgr.MIB.compile("SNMPv2-MIB.mib")
      {:ok, "SNMPv2-MIB.bin"}

      iex> SnmpKit.SnmpMgr.MIB.compile("nonexistent.mib")
      {:error, :file_not_found}
  """
  def compile(mib_file, opts \\ []) do
    # Try SnmpKit.SnmpLib.MIB first for enhanced compilation
    case compile_with_snmp_lib(mib_file, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, :snmp_lib_not_available} ->
        {:error, :snmp_lib_not_available}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compiles all MIB files in a directory using enhanced SnmpKit.SnmpLib.MIB capabilities.
  """
  def compile_dir(directory, opts \\ []) do
    # Try SnmpKit.SnmpLib.MIB.compile_all first for enhanced batch compilation
    case File.exists?(directory) do
      true ->
        case compile_all_with_snmp_lib(directory, opts) do
          {:ok, results} ->
            {:ok, results}

          {:error, :snmp_lib_not_available} ->
            # Fallback to individual file compilation
            compile_dir_fallback(directory, opts)

          {:error, reason} ->
            {:error, reason}
        end

      false ->
        {:error, {:directory_error, :enoent}}
    end
  end

  @doc """
  Parses a MIB file to extract object definitions using SnmpKit.SnmpLib.MIB.Parser.

  This provides enhanced MIB analysis without requiring compilation.

  ## Examples

      iex> SnmpKit.SnmpMgr.MIB.parse_mib_file("SNMPv2-MIB.mib")
      {:ok, %{objects: [...], imports: [...], exports: [...]}}
  """
  def parse_mib_file(mib_file, opts \\ []) do
    case File.read(mib_file) do
      {:ok, content} ->
        parse_mib_content(content, opts)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Parses MIB content string using SnmpKit.SnmpLib.MIB.Parser.

  ## Examples

      iex> content = "sysDescr OBJECT-TYPE SYNTAX DisplayString ACCESS read-only STATUS mandatory"
      iex> SnmpKit.SnmpMgr.MIB.parse_mib_content(content)
      {:ok, %{tokens: [...], parsed_objects: [...]}}
  """
  def parse_mib_content(content, opts \\ []) when is_binary(content) do
    # Use SnmpKit.SnmpLib.MIB.Parser for enhanced parsing
    case SnmpKit.SnmpLib.MIB.Parser.tokenize(content) do
      {:ok, tokens} ->
        {:ok, objects} = parse_tokens_to_objects(tokens, opts)

        {:ok,
         %{
           tokens: tokens,
           parsed_objects: objects,
           parser: :snmp_lib_enhanced
         }}

      {:error, reason} ->
        {:error, {:tokenization_failed, reason}}
    end
  end

  @doc """
  Loads a compiled MIB file using SnmpKit.SnmpLib.MIB.load_compiled with fallback.
  """
  def load(compiled_mib_path) do
    # Try SnmpKit.SnmpLib.MIB.load_compiled first for enhanced loading
    case load_with_snmp_lib(compiled_mib_path) do
      {:ok, result} ->
        GenServer.call(__MODULE__, {:register_loaded_mib, result})

      {:error, :snmp_lib_not_available} ->
        GenServer.call(__MODULE__, {:load_mib, compiled_mib_path})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Enhanced MIB object resolution with parsed MIB data integration.

  Leverages both standard MIBs and any loaded/parsed MIB files for comprehensive name resolution.
  """
  def resolve_enhanced(name, opts \\ []) do
    # First try standard resolution
    case resolve(name) do
      {:ok, oid} ->
        {:ok, oid}

      {:error, :not_found} ->
        # Try enhanced resolution with loaded MIB data
        GenServer.call(__MODULE__, {:resolve_enhanced, name, opts})

      error ->
        error
    end
  end

  @doc """
  Loads and parses a MIB file, integrating it into the name resolution system.

  This combines compilation/loading with parsing for comprehensive MIB support.
  """
  def load_and_integrate_mib(mib_file, opts \\ []) do
    with {:ok, _compiled} <- compile(mib_file, opts),
         {:ok, parsed} <- parse_mib_file(mib_file, opts) do
      # Register both compiled and parsed data
      GenServer.call(__MODULE__, {:integrate_mib_data, mib_file, parsed})
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads standard MIBs that are built into the library.
  """
  def load_standard_mibs do
    GenServer.call(__MODULE__, :load_standard_mibs)
  end

  @doc """
  Resolves a symbolic name to an OID.

  ## Examples

      iex> SnmpKit.SnmpMgr.MIB.resolve("sysDescr.0")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}

      iex> SnmpKit.SnmpMgr.MIB.resolve("sysDescr")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1]}

      iex> SnmpKit.SnmpMgr.MIB.resolve("unknownName")
      {:error, :not_found}
  """
  def resolve(name) do
    GenServer.call(__MODULE__, {:resolve, name})
  end

  @doc """
  Performs reverse lookup from OID to symbolic name.

  ## Examples

      iex> SnmpKit.SnmpMgr.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:ok, "sysDescr.0"}

      iex> SnmpKit.SnmpMgr.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1])
      {:ok, "sysDescr"}
  """
  def reverse_lookup(oid) when is_list(oid) do
    GenServer.call(__MODULE__, {:reverse_lookup, oid})
  end

  def reverse_lookup(oid_string) when is_binary(oid_string) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid_string) do
      {:ok, oid_list} -> reverse_lookup(oid_list)
      error -> error
    end
  end

  @doc """
  Gets the children of an OID node.
  """
  def children(oid) do
    GenServer.call(__MODULE__, {:children, oid})
  end

  @doc """
  Gets the parent of an OID node.
  """
  def parent(oid) when is_list(oid) and length(oid) > 0 do
    {:ok, Enum.drop(oid, -1)}
  end

  def parent([]), do: {:error, :no_parent}

  def parent(oid_string) when is_binary(oid_string) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid_string) do
      {:ok, oid_list} -> parent(oid_list)
      error -> error
    end
  end

  @doc """
  Walks the MIB tree starting from a root OID.
  """
  def walk_tree(root_oid, opts \\ []) do
    GenServer.call(__MODULE__, {:walk_tree, root_oid, opts})
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    # Initialize with standard MIBs
    reverse_map = build_reverse_map(@standard_mibs)

    state = %{
      name_to_oid: @standard_mibs,
      oid_to_name: reverse_map,
      loaded_mibs: [:standard]
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:resolve, name}, _from, state) do
    result = resolve_name(name, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reverse_lookup, oid}, _from, state) do
    result = reverse_lookup_oid(oid, state.oid_to_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:children, oid}, _from, state) do
    result = find_children(oid, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:walk_tree, root_oid, _opts}, _from, state) do
    result = walk_tree_from_root(root_oid, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:load_mib, mib_path}, _from, state) do
    case load_mib_file(mib_path) do
      {:ok, mib_data} ->
        new_state = merge_mib_data(state, mib_data)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:load_standard_mibs, _from, state) do
    # Standard MIBs are already loaded in init
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:register_loaded_mib, mib_data}, _from, state) do
    # Register MIB data loaded via SnmpKit.SnmpLib.MIB.load_compiled
    new_state = merge_snmp_lib_mib_data(state, mib_data)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:resolve_enhanced, name, _opts}, _from, state) do
    # Enhanced resolution using loaded MIB data
    result = resolve_with_loaded_mibs(name, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:integrate_mib_data, mib_file, parsed_data}, _from, state) do
    # Integrate both compiled and parsed MIB data
    new_state = integrate_parsed_mib_data(state, mib_file, parsed_data)
    {:reply, :ok, new_state}
  end

  ## Private Functions

  defp compile_with_snmp_lib(mib_file, opts) do
    case SnmpKit.SnmpLib.MIB.compile(mib_file, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:snmp_lib_compilation_failed, reason}}
    end
  rescue
    UndefinedFunctionError -> {:error, :snmp_lib_not_available}
  end

  defp compile_all_with_snmp_lib(directory, opts) do
    case File.ls(directory) do
      {:ok, files} ->
        mib_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".mib"))
          |> Enum.map(&Path.join(directory, &1))

        case SnmpKit.SnmpLib.MIB.compile_all(mib_files, opts) do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, {:snmp_lib_batch_compilation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:directory_error, reason}}
    end
  rescue
    UndefinedFunctionError -> {:error, :snmp_lib_not_available}
  end

  defp compile_dir_fallback(directory, opts) do
    case File.ls(directory) do
      {:ok, files} ->
        mib_files = Enum.filter(files, &String.ends_with?(&1, ".mib"))

        results =
          Enum.map(mib_files, fn file ->
            file_path = Path.join(directory, file)
            {file, compile(file_path, opts)}
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, {:directory_error, reason}}
    end
  end

  defp parse_tokens_to_objects(tokens, _opts) do
    # Extract OBJECT-TYPE definitions from tokens
    objects = extract_object_definitions(tokens)
    {:ok, objects}
  end

  defp extract_object_definitions(tokens) do
    # Simple object extraction - can be enhanced further
    tokens
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.filter(fn
      [{:atom, _, name}, {:"OBJECT-TYPE", _}, _] ->
        %{name: name, type: :object}

      _ ->
        false
    end)
    |> Enum.map(fn [{:atom, _, name}, {:"OBJECT-TYPE", _}, _] ->
      %{name: name, type: :object_type}
    end)
  end

  defp load_with_snmp_lib(compiled_mib_path) do
    case SnmpKit.SnmpLib.MIB.load_compiled(compiled_mib_path) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:snmp_lib_load_failed, reason}}
    end
  rescue
    UndefinedFunctionError -> {:error, :snmp_lib_not_available}
  end

  defp merge_snmp_lib_mib_data(state, mib_data) do
    # Merge SnmpKit.SnmpLib.MIB loaded data with our state
    # This would extract name-to-OID mappings from the loaded MIB
    # For now, return state unchanged as implementation depends on SnmpKit.SnmpLib.MIB structure
    Map.put(state, :snmp_lib_mibs, [mib_data | Map.get(state, :snmp_lib_mibs, [])])
  end

  defp resolve_with_loaded_mibs(_name, state) do
    # Try to resolve using loaded MIB data
    loaded_mibs = Map.get(state, :snmp_lib_mibs, [])

    if Enum.empty?(loaded_mibs) do
      {:error, :not_found}
    else
      # For now, return not found as implementation depends on SnmpKit.SnmpLib.MIB data structure
      {:error, :not_found}
    end
  end

  defp integrate_parsed_mib_data(state, mib_file, parsed_data) do
    # Integrate parsed MIB objects into our name resolution
    integrated_mibs = Map.get(state, :integrated_mibs, %{})
    new_integrated = Map.put(integrated_mibs, mib_file, parsed_data)
    Map.put(state, :integrated_mibs, new_integrated)
  end

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
            case Enum.reduce_while(instance_parts, [], fn part, acc ->
                   case Integer.parse(part) do
                     {int, ""} -> {:cont, [int | acc]}
                     _ -> {:halt, :error}
                   end
                 end) do
              :error -> {:error, :invalid_instance}
              instance_oids -> {:ok, base_oid ++ Enum.reverse(instance_oids)}
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
          case SnmpKit.SnmpLib.OID.string_to_list(parent_oid) do
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
          case SnmpKit.SnmpLib.OID.string_to_list(root_oid) do
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

  defp load_mib_file(mib_path) do
    case File.read(mib_path) do
      {:ok, mib_content} ->
        case SnmpKit.SnmpLib.MIB.Parser.parse(mib_content) do
          {:ok, mib_data} -> {:ok, extract_mib_mappings(mib_data)}
          {:error, reason} -> {:error, {:mib_parse_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read_failed, reason}}
    end
  end

  defp extract_mib_mappings(mib_data) do
    # Extract name-to-OID mappings from parsed MIB data
    definitions = Map.get(mib_data, :definitions, [])

    name_to_oid_map =
      definitions
      |> Enum.filter(&(Map.get(&1, :__type__) == :object_type))
      |> Enum.reduce(%{}, fn definition, acc ->
        name = Map.get(definition, :name)
        oid = Map.get(definition, :oid)

        if name && oid do
          Map.put(acc, name, oid)
        else
          acc
        end
      end)

    %{name_to_oid: name_to_oid_map}
  end

  defp merge_mib_data(state, _mib_data) do
    # This would merge the new MIB data with existing state
    # For now, just return the current state
    state
  end
end
