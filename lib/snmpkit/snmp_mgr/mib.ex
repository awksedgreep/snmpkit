defmodule SnmpKit.SnmpMgr.MIB do
  @moduledoc """
  MIB compilation and symbolic name resolution.

  This module provides MIB compilation using Erlang's :snmpc when available,
  and includes a built-in registry of standard MIB objects for basic operations.
  """

  use GenServer

  alias SnmpKit.MIB.{Builtin, Import, Resolver}

  ## Public API

  @doc """
  Starts the MIB registry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Compiles a MIB file using SnmpKit.MIB.Compiler pure Elixir implementation.

  Enhanced to use SnmpKit.MIB.Compiler for improved compilation with better error handling.

  ## Examples

      iex> SnmpKit.SnmpMgr.MIB.compile("SNMPv2-MIB.mib")
      {:ok, "SNMPv2-MIB.bin"}

      iex> SnmpKit.SnmpMgr.MIB.compile("nonexistent.mib")
      {:error, :file_not_found}
  """
  def compile(mib_file, opts \\ []) do
    # Try SnmpKit.MIB.Compiler first for enhanced compilation
    case compile_with_snmp_lib(mib_file, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compiles all `.mib` files in a directory with `SnmpKit.MIB.Compiler`.
  """
  def compile_dir(directory, opts \\ []) do
    if File.exists?(directory) do
      compile_all_with_snmp_lib(directory, opts)
    else
      {:error, {:directory_error, :enoent}}
    end
  end

  @doc """
  Returns enriched MIB metadata for an object by name or OID.

  Input may be a dotted OID string (with or without instance), an OID list,
  or a base name (optionally with an instance suffix like "ifDescr.6").

  Returns a map with at least: name (base symbol), base oid, and optional instance
  fields when input includes an instance. Includes curated syntax metadata for a
  subset of high-value IF-MIB objects as a stopgap until full compiler metadata
  is wired in.
  """
  @spec object_info(String.t() | [integer]) :: {:ok, map()} | {:error, term()}
  def object_info(name_or_oid) do
    with {:ok, input_oid} <- normalize_to_oid_list(name_or_oid),
         {:ok, base_name, _maybe_index} <- base_name_and_index(input_oid),
         {:ok, base_oid} <- name_to_oid(base_name) do
      # Prefer compiled/parsed metadata when available
      compiled_meta = GenServer.call(__MODULE__, {:get_metadata, base_name})

      syntax =
        case compiled_meta do
          %{syntax_base: base} = m ->
            %{
              base: base,
              textual_convention: Map.get(m, :textual_convention),
              display_hint: Map.get(m, :display_hint),
              enumerations: Map.get(m, :enumerations)
            }

          _ ->
            Builtin.syntax(base_name)
        end

      base_map = %{
        name: base_name,
        module: Builtin.module_for(base_name),
        oid: base_oid,
        syntax: syntax
      }

      enriched = maybe_put_instance(base_map, input_oid, base_oid)

      # Optionally add access/status/description if we have compiled metadata
      enriched =
        case compiled_meta do
          nil ->
            enriched

          m ->
            enriched
            |> maybe_put(:access, Map.get(m, :access))
            |> maybe_put(:status, Map.get(m, :status))
            |> maybe_put(:description, Map.get(m, :description))
        end

      {:ok, enriched}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Alias for object_info/1 to match proposal naming.
  """
  @spec reverse_lookup_enriched(String.t() | [integer]) :: {:ok, map()} | {:error, term()}
  def reverse_lookup_enriched(name_or_oid), do: object_info(name_or_oid)

  @doc """
  Batch variant of object_info/1.
  Returns {:ok, list_of_maps} or {:error, reason} if any lookup fails.
  """
  @spec object_info_many([String.t() | [integer]]) :: {:ok, [map()]} | {:error, term()}
  def object_info_many(list) when is_list(list) do
    results = Enum.map(list, &object_info/1)

    case Enum.find(results, fn
           {:error, _} -> true
           _ -> false
         end) do
      {:error, reason} -> {:error, reason}
      _ -> {:ok, Enum.map(results, fn {:ok, m} -> m end)}
    end
  end

  @doc """
  Parses a MIB file to extract object definitions using SnmpKit.MIB.Parser.

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
  Parses MIB content string using SnmpKit.MIB.Parser.

  ## Examples

      iex> content = "sysDescr OBJECT-TYPE SYNTAX DisplayString ACCESS read-only STATUS mandatory"
      iex> SnmpKit.SnmpMgr.MIB.parse_mib_content(content)
      {:ok, %{tokens: [...], parsed_objects: [...]}}
  """
  def parse_mib_content(content, opts \\ []) when is_binary(content) do
    # Use SnmpKit.MIB.Parser for enhanced parsing
    case SnmpKit.MIB.Parser.tokenize(content) do
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
  Loads a compiled MIB file using SnmpKit.MIB.load_compiled with fallback.
  """
  def load(%{symbols: _} = compiled_mib) do
    GenServer.call(__MODULE__, {:register_loaded_mib, compiled_mib})
  end

  def load(compiled_mib_path) when is_binary(compiled_mib_path) do
    # Try SnmpKit.MIB.load_compiled first for enhanced loading
    case load_with_snmp_lib(compiled_mib_path) do
      {:ok, result} ->
        GenServer.call(__MODULE__, {:register_loaded_mib, result})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reverse lookup that also returns the object's metadata (syntax base,
  textual convention, DISPLAY-HINT, enumerations) in one call. Used by the
  formatter; `{:ok, name, meta}` where `meta` may be `nil`.
  """
  @spec reverse_lookup_with_meta([non_neg_integer()] | String.t()) ::
          {:ok, String.t(), map() | nil} | {:error, term()}
  def reverse_lookup_with_meta(oid) when is_list(oid) do
    GenServer.call(__MODULE__, {:reverse_lookup_with_meta, oid})
  end

  def reverse_lookup_with_meta(oid_string) when is_binary(oid_string) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid_string) do
      {:ok, oid_list} -> reverse_lookup_with_meta(oid_list)
      error -> error
    end
  end

  @doc """
  Column names and INDEX descriptions of a table, for `SnmpKit.SnmpMgr.Table`
  named rows. `table` is the table's OID (list or string) or name.

      {:ok, %{entry: "ifEntry", columns: %{1 => "ifIndex", 2 => "ifDescr", ...},
              indexes: [%{name: "ifIndex", base: :integer, size: nil, implied: false}]}}
  """
  @spec table_layout([non_neg_integer()] | String.t()) :: {:ok, map()} | {:error, term()}
  def table_layout(table) do
    with {:ok, table_oid} <- normalize_to_oid_list(table) do
      GenServer.call(__MODULE__, {:table_layout, table_oid})
    end
  end

  @doc """
  Enhanced MIB object resolution with parsed MIB data integration.

  Returns enriched object information including OID, syntax, module, and more.
  Leverages both standard MIBs and any loaded/parsed MIB files for comprehensive resolution.

  ## Examples

      iex> SnmpKit.SnmpMgr.MIB.resolve_enhanced("sysDescr")
      {:ok, %{name: "sysDescr", oid: [1, 3, 6, 1, 2, 1, 1, 1], module: "SNMPv2-MIB", syntax: %{...}}}

      iex> SnmpKit.SnmpMgr.MIB.resolve_enhanced("sysDescr.0")
      {:ok, %{name: "sysDescr", oid: [1, 3, 6, 1, 2, 1, 1, 1], instance_oid: [1, 3, 6, 1, 2, 1, 1, 1, 0], ...}}
  """
  def resolve_enhanced(name, _opts \\ []) do
    # Use object_info for enriched resolution
    object_info(name)
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
    reverse_map = Resolver.build_reverse_map(Builtin.name_to_oid())

    state = %{
      name_to_oid: Builtin.name_to_oid(),
      oid_to_name: reverse_map,
      name_to_meta: %{},
      loaded_mibs: [:standard]
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:resolve, name}, _from, state) do
    result = Resolver.resolve_name(name, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reverse_lookup, oid}, _from, state) do
    result = Resolver.reverse_lookup_oid(oid, state.oid_to_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reverse_lookup_with_meta, oid}, _from, state) do
    case Resolver.reverse_lookup_oid(oid, state.oid_to_name) do
      {:ok, name} ->
        base = Resolver.strip_instance_suffix(name)
        {:reply, {:ok, name, metadata_for(base, state)}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:children, oid}, _from, state) do
    result = Resolver.find_children(oid, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:walk_tree, root_oid, _opts}, _from, state) do
    result = Resolver.walk_tree_from_root(root_oid, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:load_mib, mib_path}, _from, state) do
    case Import.load_mib_file_and_extract_mappings(mib_path) do
      {:ok, mib_data} ->
        {:reply, :ok, merge_snmp_lib_mib_data(state, mib_data)}

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
    # Register MIB data loaded via SnmpKit.MIB.load_compiled
    new_state = merge_snmp_lib_mib_data(state, mib_data)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:table_layout, table_oid}, _from, state) do
    entry_oid = table_oid ++ [1]
    entry_len = length(entry_oid)

    columns =
      state.name_to_oid
      |> Enum.filter(fn {_name, oid} ->
        length(oid) == entry_len + 1 and List.starts_with?(oid, entry_oid)
      end)
      |> Map.new(fn {name, oid} -> {List.last(oid), name} end)

    entry_name =
      case Resolver.reverse_lookup_oid(entry_oid, state.oid_to_name) do
        {:ok, name} -> name
        _ -> nil
      end

    indexes =
      entry_name
      |> row_index_names(state, 0)
      |> Enum.map(fn {name, implied} ->
        meta = metadata_for(name, state) || %{}

        %{
          name: name,
          base: Map.get(meta, :syntax_base),
          size: Map.get(meta, :size),
          implied: implied
        }
      end)

    if map_size(columns) == 0 and entry_name == nil do
      {:reply, {:error, :unknown_table}, state}
    else
      {:reply, {:ok, %{entry: entry_name, columns: columns, indexes: indexes}}, state}
    end
  end

  @impl true
  def handle_call({:get_metadata, base_name}, _from, state) do
    {:reply, metadata_for(base_name, state), state}
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
    case SnmpKit.MIB.Compiler.compile(mib_file, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:snmp_lib_compilation_failed, reason}}
    end
  end

  defp compile_all_with_snmp_lib(directory, opts) do
    case File.ls(directory) do
      {:ok, files} ->
        mib_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".mib"))
          |> Enum.map(&Path.join(directory, &1))

        case SnmpKit.MIB.Compiler.compile_all(mib_files, opts) do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, {:snmp_lib_batch_compilation_failed, reason}}
        end

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

  # INDEX names of a row, following AUGMENTS (bounded depth)
  defp row_index_names(nil, _state, _depth), do: []
  defp row_index_names(_entry, _state, depth) when depth > 5, do: []

  defp row_index_names(entry_name, state, depth) do
    case metadata_for(entry_name, state) do
      %{indexes: [_ | _] = indexes} ->
        indexes

      %{augments: augmented} when is_binary(augmented) ->
        row_index_names(augmented, state, depth + 1)

      _ ->
        []
    end
  end

  # Loaded MIB metadata wins; the built-in tables fill anything it lacks.
  defp metadata_for(base_name, state) do
    builtin = Builtin.meta(base_name)

    case Map.get(state.name_to_meta, base_name) do
      nil ->
        if builtin.syntax_base || builtin.enumerations || builtin.indexes, do: builtin, else: nil

      loaded ->
        Map.merge(builtin, loaded, fn _k, b, l -> l || b end)
    end
  end

  defp load_with_snmp_lib(compiled_mib_path) do
    case SnmpKit.MIB.Compiler.load_compiled(compiled_mib_path) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:snmp_lib_load_failed, reason}}
    end
  end

  defp merge_snmp_lib_mib_data(state, mib_data) do
    # Accept either compiled format with :symbols or a parsed map with name_to_oid/name_to_meta
    {add_map, add_meta} =
      cond do
        is_map(mib_data) and Map.has_key?(mib_data, :symbols) ->
          symbols = Map.get(mib_data, :symbols, %{})

          {Import.extract_name_to_oid_from_symbols(symbols, state.name_to_oid),
           Import.extract_meta_from_symbols(symbols)}

        is_map(mib_data) and Map.has_key?(mib_data, :name_to_oid) ->
          raw = Map.get(mib_data, :name_to_oid, %{})
          meta = Map.get(mib_data, :name_to_meta, %{})
          {Resolver.normalize_name_to_oid(raw), meta}

        true ->
          {%{}, %{}}
      end

    merged_name_to_oid = Map.merge(state.name_to_oid, add_map)
    merged_oid_to_name = Resolver.build_reverse_map(merged_name_to_oid)
    merged_name_to_meta = Map.merge(state.name_to_meta, add_meta)

    state
    |> Map.put(:name_to_oid, merged_name_to_oid)
    |> Map.put(:oid_to_name, merged_oid_to_name)
    |> Map.put(:name_to_meta, merged_name_to_meta)
    |> Map.update(:snmp_lib_mibs, [mib_data], fn list -> [mib_data | list] end)
  end

  defp resolve_with_loaded_mibs(name, state) do
    case Map.get(state, :name_to_oid) do
      %{} = m when is_binary(name) ->
        case Map.get(m, name) do
          nil -> {:error, :not_found}
          oid -> {:ok, oid}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp integrate_parsed_mib_data(state, mib_file, parsed_data) do
    # Integrate parsed MIB objects into our name resolution
    integrated_mibs = Map.get(state, :integrated_mibs, %{})
    new_integrated = Map.put(integrated_mibs, mib_file, parsed_data)
    Map.put(state, :integrated_mibs, new_integrated)
  end

  defp normalize_to_oid_list(oid_any) when is_list(oid_any) do
    case SnmpKit.SnmpLib.OID.valid_oid?(oid_any) do
      :ok -> {:ok, oid_any}
      error -> error
    end
  end

  defp normalize_to_oid_list(oid_any) when is_binary(oid_any) do
    cond do
      String.contains?(oid_any, ".") and String.match?(oid_any, ~r/^\.?\d+(?:\.\d+)*$/) ->
        SnmpKit.SnmpLib.OID.string_to_list(oid_any)

      true ->
        case String.split(oid_any, ".", parts: 2) do
          [base] ->
            case resolve(base) do
              {:ok, base_oid} -> {:ok, base_oid}
              error -> error
            end

          [base, instance_str] ->
            with {:ok, base_oid} <- resolve(base),
                 {:ok, instance_index} <- Resolver.parse_instance(instance_str) do
              {:ok, base_oid ++ instance_index}
            else
              {:error, _} = err -> err
              _ -> {:error, :invalid_instance}
            end
        end
    end
  end

  defp normalize_to_oid_list(_), do: {:error, :invalid_input}

  defp base_name_and_index(oid_list) do
    case reverse_lookup(oid_list) do
      {:ok, name_with_index} ->
        # Strip instance suffix to get the true base name (e.g., "sysDescr.0" -> "sysDescr")
        base_name = Resolver.strip_instance_suffix(name_with_index)

        case name_to_oid(base_name) do
          {:ok, base_oid} ->
            base_len = length(base_oid)

            if length(oid_list) > base_len do
              {:ok, base_name, Enum.drop(oid_list, base_len)}
            else
              {:ok, base_name, nil}
            end

          {:error, _} = err ->
            err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp name_to_oid(name) when is_binary(name) do
    case resolve(name) do
      {:ok, oid} -> {:ok, oid}
      error -> error
    end
  end

  defp maybe_put_instance(map, input_oid, base_oid) do
    base_len = length(base_oid)

    if length(input_oid) > base_len do
      instance = Enum.drop(input_oid, base_len)

      instance_index =
        case instance do
          [i] -> i
          list -> list
        end

      map
      |> Map.put(:instance_index, instance_index)
      |> Map.put(:instance_oid, input_oid)
    else
      map
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
