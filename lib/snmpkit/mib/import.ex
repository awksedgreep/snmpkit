defmodule SnmpKit.MIB.Import do
  @moduledoc """
  Turns parsed or compiled MIB data into the `name_to_oid` / `name_to_meta`
  maps the registry merges: object OIDs, base syntax, textual conventions,
  display hints, access, status and description.
  """

  @doc """
  Name-to-OID map for a compiled symbol table. Relative OIDs are resolved
  against the other symbols and against `known` (names already registered,
  such as the built-in `enterprises` or `ifEntry`).
  """
  def extract_name_to_oid_from_symbols(symbols, known \\ %{}) when is_map(symbols) do
    SnmpKit.MIB.Resolver.resolve_definition_oids(symbols, known)
  end

  def extract_meta_from_symbols(symbols) when is_map(symbols) do
    definitions = symbols |> Map.values() |> Enum.filter(&is_map/1)
    tc_map = SnmpKit.MIB.Syntax.textual_conventions(definitions)

    Enum.reduce(definitions, %{}, fn defn, acc ->
      case Map.get(defn, :__type__) do
        :object_type -> Map.put(acc, Map.get(defn, :name), object_meta(defn, tc_map))
        _ -> acc
      end
    end)
  end

  # Metadata for one OBJECT-TYPE definition: syntax description plus access,
  # status and description
  def object_meta(defn, tc_map) do
    desc = SnmpKit.MIB.Syntax.describe(Map.get(defn, :syntax), tc_map)

    {indexes, augments} = row_indexes(Map.get(defn, :kind))

    %{
      syntax_base: desc.base,
      textual_convention: desc.textual_convention,
      display_hint: desc.display_hint,
      enumerations: desc.enumerations,
      size: desc.size,
      indexes: indexes,
      augments: augments,
      access: Map.get(defn, :max_access),
      status: Map.get(defn, :status),
      description: Map.get(defn, :description)
    }
  end

  # INDEX / AUGMENTS of a conceptual row: [{name, implied?}] and the augmented row
  defp row_indexes({:table_entry, {:indexes, indexes}}) when is_list(indexes) do
    {Enum.map(indexes, fn
       {:implied, name} -> {to_string(name), true}
       name -> {to_string(name), false}
     end), nil}
  end

  defp row_indexes({:table_entry, {:augments, entry}}), do: {nil, to_string(entry)}
  defp row_indexes(_), do: {nil, nil}

  # Derive base syntax from parsed syntax term
  def syntax_base_from(syntax) do
    case syntax do
      :integer ->
        :integer

      :octet_string ->
        :octet_string

      :object_identifier ->
        :object_identifier

      :timeticks ->
        :timeticks

      :counter32 ->
        :counter32

      :counter64 ->
        :counter64

      :gauge32 ->
        :gauge32

      :ip_address ->
        :ip_address

      {:integer, _} ->
        :integer

      {:octet_string, _} ->
        :octet_string

      {:object_identifier, _} ->
        :object_identifier

      {:type, t} when is_atom(t) ->
        case t do
          :"octet string" -> :octet_string
          :"object identifier" -> :object_identifier
          other -> other
        end

      _ ->
        nil
    end
  end

  # Best-effort textual convention detection from syntax term
  def textual_convention_from(syntax) do
    case syntax do
      {:type, t} when is_atom(t) -> Atom.to_string(t)
      _ -> nil
    end
  end

  def load_mib_file_and_extract_mappings(mib_path) do
    case SnmpKit.SnmpSim.SafeFile.read(mib_path) do
      {:ok, mib_content} ->
        case SnmpKit.MIB.Parser.parse(mib_content) do
          {:ok, parsed_mib_data} -> {:ok, extract_mib_mappings(parsed_mib_data)}
          {:error, reason} -> {:error, {:mib_parse_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read_failed, reason}}
    end
  end

  def extract_mib_mappings(mib_data, known \\ SnmpKit.MIB.Builtin.name_to_oid()) do
    # Extract name-to-OID mappings and metadata from parsed MIB data
    definitions = Map.get(mib_data, :definitions, [])
    tc_map = SnmpKit.MIB.Syntax.textual_conventions(definitions)

    name_to_meta =
      definitions
      |> Enum.filter(&(Map.get(&1, :__type__) == :object_type))
      |> Map.new(&{Map.get(&1, :name), object_meta(&1, tc_map)})

    %{
      name_to_oid: SnmpKit.MIB.Resolver.resolve_definition_oids(definitions, known),
      name_to_meta: name_to_meta
    }
  end
end
