defmodule SnmpSim.ProfileLoader do
  @moduledoc """
  Flexible profile loading supporting multiple sources and progressive enhancement.
  Start with simple walk files, upgrade to MIB-based simulation when ready.
  """

  require Logger
  alias SnmpSim.WalkParser

  defstruct [
    :device_type,
    :source_type,
    :oid_map,
    :behaviors,
    :metadata
  ]

  @doc """
  Load a device profile from various source types.

  Supported source types:
  - `{:walk_file, path}` - SNMP walk files (both named and numeric formats)
  - `{:oid_walk, path}` - Raw OID dumps (numeric OIDs only)  
  - `{:json_profile, path}` - Structured JSON profiles
  - `{:manual, oid_map}` - Manual OID definitions (for testing)
  - `{:compiled_mib, mib_files}` - Advanced MIB compilation (future)

  ## Examples

      # Load from SNMP walk file
      profile = SnmpSim.ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      # Load with behaviors
      profile = SnmpSim.ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: [
          {:increment_counters, rate: 1000},
          {:vary_gauges, variance: 0.1}
        ]
      )
      
  """
  def load_profile(device_type, source, opts \\ []) do
    case source do
      {:walk_file, path} ->
        load_from_snmp_walk(device_type, path, opts)

      {:oid_walk, path} ->
        load_from_oid_walk(device_type, path, opts)

      {:json_profile, path} ->
        load_from_json_profile(device_type, path, opts)

      {:manual, oid_map} ->
        load_from_manual_definitions(device_type, oid_map, opts)

      {:compiled_mib, mib_files} ->
        load_from_compiled_mibs(device_type, mib_files, opts)

      _ ->
        {:error, {:unsupported_source_type, source}}
    end
  end

  @doc """
  Get the value for a specific OID from a loaded profile.

  ## Examples

      value = SnmpSim.ProfileLoader.get_oid_value(profile, "1.3.6.1.2.1.1.1.0")
      
  """
  def get_oid_value(%__MODULE__{oid_map: oid_map}, oid) do
    Map.get(oid_map, oid)
  end

  @doc """
  Get all OIDs in lexicographic order for GETNEXT operations.
  """
  def get_ordered_oids(%__MODULE__{oid_map: oid_map}) do
    oid_map
    |> Map.keys()
    |> Enum.sort(&compare_oids/2)
  end

  @doc """
  Find the next OID after the given OID for GETNEXT operations.
  """
  def get_next_oid(%__MODULE__{} = profile, oid) do
    ordered_oids = get_ordered_oids(profile)

    case Enum.find_index(ordered_oids, &(&1 == oid)) do
      nil ->
        # OID not found - find the next lexicographically larger OID
        case Enum.find(ordered_oids, &compare_oids(oid, &1)) do
          nil -> :end_of_mib
          next_oid -> {:ok, next_oid}
        end

      index ->
        # OID found - return the next one
        case Enum.at(ordered_oids, index + 1) do
          nil -> :end_of_mib
          next_oid -> {:ok, next_oid}
        end
    end
  end

  # Private functions for different source types

  defp load_from_snmp_walk(device_type, path, opts) do
    case WalkParser.parse_walk_file(path) do
      {:ok, oid_map} ->
        # Apply behavior enhancement to walk file data
        enhanced_oid_map =
          case Keyword.get(opts, :behaviors) do
            nil ->
              # Apply default intelligent behavior analysis
              SnmpSim.MIB.BehaviorAnalyzer.enhance_walk_file_behaviors(oid_map)

            behavior_configs ->
              # Apply custom behavior configurations
              temp_profile = %__MODULE__{oid_map: oid_map}

              enhanced_profile =
                SnmpSim.BehaviorConfig.apply_behaviors(temp_profile, behavior_configs)

              enhanced_profile.oid_map
          end

        {:ok,
         %__MODULE__{
           device_type: device_type,
           source_type: :walk_file,
           oid_map: enhanced_oid_map,
           behaviors: Keyword.get(opts, :behaviors, []),
           metadata: %{
             source_file: path,
             loaded_at: DateTime.utc_now(),
             oid_count: map_size(enhanced_oid_map),
             enhancement_applied: true
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_from_oid_walk(device_type, path, opts) do
    # OID walk files are similar to walk files but only contain numeric OIDs
    # We can reuse the walk parser since it handles both formats
    case WalkParser.parse_walk_file(path) do
      {:ok, oid_map} ->
        # Filter to ensure only numeric OIDs (no named MIB entries)
        numeric_oid_map =
          oid_map
          |> Enum.filter(fn {oid, _value} ->
            Regex.match?(~r/^\d+(\.\d+)*$/, oid)
          end)
          |> Map.new()

        {:ok,
         %__MODULE__{
           device_type: device_type,
           source_type: :oid_walk,
           oid_map: numeric_oid_map,
           behaviors: Keyword.get(opts, :behaviors, []),
           metadata: %{
             source_file: path,
             loaded_at: DateTime.utc_now(),
             oid_count: map_size(numeric_oid_map)
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_from_json_profile(device_type, path, opts) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, profile_data} ->
            oid_map = parse_json_profile(profile_data)

            {:ok,
             %__MODULE__{
               device_type: device_type,
               source_type: :json_profile,
               oid_map: oid_map,
               behaviors: Keyword.get(opts, :behaviors, []),
               metadata: %{
                 source_file: path,
                 loaded_at: DateTime.utc_now(),
                 oid_count: map_size(oid_map),
                 profile_data: profile_data
               }
             }}

          {:error, json_error} ->
            {:error, {:json_decode_error, json_error}}
        end

      {:error, file_error} ->
        {:error, {:file_read_error, file_error}}
    end
  end

  defp load_from_manual_definitions(device_type, oid_map, opts) when is_map(oid_map) do
    # Convert simple string values to full value maps
    processed_oid_map =
      oid_map
      |> Enum.map(fn
        {oid, value} when is_binary(value) ->
          {oid, %{type: "STRING", value: value}}

        {oid, value} when is_integer(value) ->
          {oid, %{type: "INTEGER", value: value}}

        {oid, value} when is_map(value) ->
          {oid, value}

        {oid, value} ->
          {oid, %{type: "STRING", value: to_string(value)}}
      end)
      |> Map.new()

    {:ok,
     %__MODULE__{
       device_type: device_type,
       source_type: :manual,
       oid_map: processed_oid_map,
       behaviors: Keyword.get(opts, :behaviors, []),
       metadata: %{
         loaded_at: DateTime.utc_now(),
         oid_count: map_size(processed_oid_map)
       }
     }}
  end

  defp load_from_compiled_mibs(device_type, mib_files, opts) do
    # Compile MIB files and extract successful compilations
    compiled_mibs =
      mib_files
      |> SnmpSim.MIB.Compiler.compile_mib_files()
      |> Enum.filter(fn {_file, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {_file, {:ok, compiled}} -> compiled end)

    if Enum.empty?(compiled_mibs) do
      {:error, :no_mibs_compiled}
    else
      # Extract object definitions from successfully compiled MIBs
      all_objects =
        compiled_mibs
        |> Enum.map(&extract_mib_objects/1)
        |> Enum.reduce(%{}, &Map.merge/2)

      # Analyze behaviors automatically
      {:ok, enhanced_objects} = SnmpSim.MIB.BehaviorAnalyzer.analyze_mib_behaviors(all_objects)

      # Apply any additional behavior configurations
      final_objects =
        case Keyword.get(opts, :behaviors) do
          nil ->
            enhanced_objects

          behavior_configs ->
            apply_behavior_configs(enhanced_objects, behavior_configs)
        end

      # Return the final result
      {:ok,
       %__MODULE__{
         device_type: device_type,
         source_type: :compiled_mib,
         oid_map: final_objects,
         behaviors: Keyword.get(opts, :behaviors, []),
         metadata: %{
           mib_files: mib_files,
           loaded_at: DateTime.utc_now(),
           oid_count: map_size(final_objects),
           compilation_method: :erlang_snmpc
         }
       }}
    end
  end

  # Parse JSON profile format
  defp parse_json_profile(%{"oids" => oids}) when is_map(oids) do
    oids
    |> Enum.map(fn {oid, value_data} ->
      parsed_value = parse_json_value(value_data)
      {oid, parsed_value}
    end)
    |> Map.new()
  end

  defp parse_json_profile(_profile_data) do
    # Handle other JSON profile formats as needed
    %{}
  end

  # Parse individual value entries from JSON
  defp parse_json_value(%{"type" => "counter", "value" => value}) when is_integer(value) do
    %{
      type: "counter",
      value: value,
      metadata: %{counter_type: :counter32}
    }
  end

  defp parse_json_value(%{"type" => _type, "value" => _value} = data) do
    %{
      type: data["type"],
      value: data["value"],
      metadata: Map.get(data, "metadata", %{})
    }
  end

  defp parse_json_value(value) when is_binary(value) or is_integer(value) do
    %{type: "STRING", value: value}
  end

  # Apply behavior configurations to MIB objects
  defp apply_behavior_configs(objects, behavior_configs)
       when is_map(objects) and is_list(behavior_configs) do
    Enum.reduce(behavior_configs, objects, fn config, acc ->
      case config do
        %{oid: oid, behavior: behavior, params: params} ->
          case Map.get(acc, oid) do
            # Skip if OID not found
            nil ->
              acc

            object ->
              updated_object =
                Map.merge(object, %{
                  behavior: behavior,
                  behavior_params: params
                })

              Map.put(acc, oid, updated_object)
          end

        # Skip invalid configs
        _ ->
          acc
      end
    end)
  end

  # Compare OIDs lexicographically for proper SNMP ordering
  defp compare_oids(oid1, oid2) do
    parts1 = String.split(oid1, ".") |> Enum.map(&String.to_integer/1)
    parts2 = String.split(oid2, ".") |> Enum.map(&String.to_integer/1)

    compare_oid_parts(parts1, parts2)
  end

  defp compare_oid_parts([], []), do: false
  defp compare_oid_parts([], _), do: true
  defp compare_oid_parts(_, []), do: false
  defp compare_oid_parts([h1 | _t1], [h2 | _t2]) when h1 < h2, do: true
  defp compare_oid_parts([h1 | _t1], [h2 | _t2]) when h1 > h2, do: false
  defp compare_oid_parts([h1 | t1], [h2 | t2]) when h1 == h2, do: compare_oid_parts(t1, t2)

  # Helper function to extract MIB objects from compiled MIB data
  defp extract_mib_objects(compiled_mib) do
    # This would extract actual objects from the compiled MIB structure
    # For now, return empty map - this would be implemented based on actual MIB format
    Logger.info("Extracting objects from compiled MIB: #{inspect(compiled_mib.bin_file)}")
    %{}
  end
end
