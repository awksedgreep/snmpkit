defmodule SnmpKit.MIB.Import do
  @moduledoc """
  Turns parsed or compiled MIB data into the `name_to_oid` / `name_to_meta`
  maps the registry merges: object OIDs, base syntax, textual conventions,
  display hints, access, status and description.
  """

  def extract_name_to_oid_from_symbols(symbols) when is_map(symbols) do
    symbols
    |> Enum.reduce(%{}, fn {name, defn}, acc ->
      case defn do
        %{} ->
          case Map.get(defn, :oid) do
            nil ->
              acc

            oid_any ->
              case SnmpKit.MIB.Resolver.normalize_parsed_oid(oid_any) do
                {:ok, oid_list} -> Map.put(acc, name, oid_list)
                _ -> acc
              end
          end

        _ ->
          acc
      end
    end)
  end

  def extract_meta_from_symbols(symbols) when is_map(symbols) do
    symbols
    |> Enum.reduce(%{}, fn {name, defn}, acc ->
      case defn do
        %{} ->
          case Map.get(defn, :__type__) do
            :object_type ->
              syntax_any = Map.get(defn, :syntax)
              access = Map.get(defn, :max_access)
              status = Map.get(defn, :status)
              description = Map.get(defn, :description)

              meta = %{
                syntax_base: syntax_base_from(syntax_any),
                textual_convention: textual_convention_from(syntax_any),
                display_hint: nil,
                access: access,
                status: status,
                description: description
              }

              Map.put(acc, name, meta)

            _ ->
              acc
          end

        _ ->
          acc
      end
    end)
  end

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

  def extract_mib_mappings(mib_data) do
    # Extract name-to-OID mappings and basic metadata from parsed MIB data
    definitions = Map.get(mib_data, :definitions, [])

    # Build TC map first
    tc_map =
      definitions
      |> Enum.filter(&(Map.get(&1, :__type__) == :textual_convention))
      |> Enum.reduce(%{}, fn tc, acc ->
        tc_name = Map.get(tc, :name)
        tc_syntax = Map.get(tc, :syntax)
        display_hint = Map.get(tc, :display_hint)

        acc
        |> Map.put(tc_name, %{
          syntax_base: syntax_base_from(tc_syntax),
          display_hint: display_hint
        })
      end)

    primitives = [
      :integer,
      :octet_string,
      :object_identifier,
      :timeticks,
      :counter32,
      :counter64,
      :gauge32,
      :ip_address
    ]

    {name_to_oid_map, name_to_meta} =
      definitions
      |> Enum.reduce({%{}, %{}}, fn defn, {oid_acc, meta_acc} ->
        case Map.get(defn, :__type__) do
          :object_type ->
            name = Map.get(defn, :name)
            oid_any = Map.get(defn, :oid)
            syntax_any = Map.get(defn, :syntax)
            access = Map.get(defn, :max_access)
            status = Map.get(defn, :status)
            description = Map.get(defn, :description)

            oid_acc2 =
              case {name, SnmpKit.MIB.Resolver.normalize_parsed_oid(oid_any)} do
                {name, {:ok, oid_list}} when is_binary(name) -> Map.put(oid_acc, name, oid_list)
                _ -> oid_acc
              end

            {syntax_base, textual_convention, display_hint} =
              case syntax_any do
                # Named type referencing a TC like :DisplayString
                t when is_atom(t) ->
                  if t in primitives do
                    {syntax_base_from(syntax_any), textual_convention_from(syntax_any), nil}
                  else
                    tc_key = Atom.to_string(t)

                    case Map.get(tc_map, tc_key) do
                      %{syntax_base: base, display_hint: hint} ->
                        {base, tc_key, hint}

                      _ ->
                        {syntax_base_from(syntax_any), textual_convention_from(syntax_any), nil}
                    end
                  end

                _ ->
                  {syntax_base_from(syntax_any), textual_convention_from(syntax_any), nil}
              end

            meta = %{
              syntax_base: syntax_base,
              textual_convention: textual_convention,
              display_hint: display_hint,
              access: access,
              status: status,
              description: description
            }

            {oid_acc2, Map.put(meta_acc, name, meta)}

          _ ->
            {oid_acc, meta_acc}
        end
      end)

    %{name_to_oid: name_to_oid_map, name_to_meta: name_to_meta}
  end
end
