defmodule SnmpKit.MIB.Lint do
  @moduledoc """
  Semantic checks for a parsed or compiled MIB, in the spirit of libsmi's
  `smilint` levels 1 and 2. The parser only decides whether a file is
  syntactically a MIB; this module checks whether it makes sense: do all
  OIDs resolve, are the referenced types and objects defined or imported, do
  table rows have indexes, do SEQUENCE fields match their columns, and is
  the module consistent with the SMI version it claims.

      {:ok, report} = SnmpKit.MIB.Lint.check("priv/mibs/MY-MIB.mib")
      report.errors    #=> 0
      report.warnings  #=> 2
      Enum.each(report.findings, &IO.puts(SnmpKit.MIB.Lint.format(&1)))

  ## Findings

  Each finding is `%{severity: :error | :warning, code: atom, name: String.t
  | nil, line: pos_integer | nil, message: String.t}`. Codes:

  | Code | Severity | Meaning |
  |------|----------|---------|
  | `:parser_warning` | warning | a lexical or vendor-construct warning recorded by the parser |
  | `:duplicate_name` | error | the same identifier is defined twice |
  | `:duplicate_oid` | error | two definitions register the same OID |
  | `:unresolved_parent` | error | an OID's parent is neither defined, imported nor known |
  | `:unknown_import` | warning | an imported symbol's module is not available to the check |
  | `:unknown_type` | error | a SYNTAX names a type that is not defined, imported or built in |
  | `:smiv1_in_smiv2` | warning | `ACCESS`/`mandatory`/`optional` (SMIv1) inside an SMIv2 module |
  | `:missing_module_identity` | warning | an SMIv2 module without MODULE-IDENTITY |
  | `:row_without_index` | error | a conceptual row without INDEX or AUGMENTS |
  | `:index_without_size` | warning | a string or OID index object without a SIZE restriction |
  | `:sequence_field_undefined` | warning | a SEQUENCE field with no matching column object |
  | `:column_not_in_sequence` | warning | a column object missing from the row's SEQUENCE |
  | `:sequence_type_mismatch` | warning | a column's SYNTAX differs from its SEQUENCE field |
  | `:unknown_object` | warning | a notification or group lists an object that is not defined or imported |

  ## Options

  - `:context` - other compiled MIBs (as returned by `SnmpKit.MIB.compile/1`)
    whose symbols satisfy imports
  - `:known` - `%{name => oid}` of names already available (defaults to the
    built-in tables plus whatever the registry has loaded)
  """

  alias SnmpKit.MIB.{Builtin, Resolver, Syntax}

  @type finding :: %{
          severity: :error | :warning,
          code: atom(),
          name: String.t() | nil,
          line: pos_integer() | nil,
          message: String.t()
        }

  @type report :: %{
          name: String.t(),
          findings: [finding()],
          errors: non_neg_integer(),
          warnings: non_neg_integer()
        }

  @smiv2_modules ["SNMPv2-SMI", "SNMPv2-TC", "SNMPv2-CONF"]
  @macros ~w(OBJECT-TYPE MODULE-IDENTITY OBJECT-IDENTITY NOTIFICATION-TYPE TEXTUAL-CONVENTION
             OBJECT-GROUP NOTIFICATION-GROUP MODULE-COMPLIANCE AGENT-CAPABILITIES TRAP-TYPE)
  @builtin_types ~w(Integer32 Unsigned32 Counter32 Counter64 Gauge32 TimeTicks IpAddress Opaque
                    Counter Gauge NetworkAddress BITS)

  @doc "Checks a compiled MIB map, a parsed MIB map, a file path or MIB text."
  @spec check(map() | Path.t() | String.t(), keyword()) :: {:ok, report()} | {:error, term()}
  def check(source, opts \\ [])

  def check(%{symbols: symbols} = compiled, opts) when is_map(symbols) do
    definitions = symbols |> Map.values() |> Enum.filter(&is_map/1)

    mib = %{
      name: Map.get(compiled, :name, "?"),
      version: Map.get(compiled, :version),
      imports: Map.get(compiled, :imports, []),
      definitions: definitions,
      warnings: Map.get(compiled, :warnings, [])
    }

    {:ok, run(mib, opts)}
  end

  def check(%{definitions: definitions} = parsed, opts) when is_list(definitions) do
    {:ok, run(parsed, opts)}
  end

  def check(source, opts) when is_binary(source) do
    text =
      if String.contains?(source, "\n") or not File.regular?(source),
        do: {:ok, source},
        else: File.read(source)

    # Parse rather than compile: the compiled symbol table is keyed by name and
    # would hide duplicate definitions.
    with {:ok, text} <- text,
         {:ok, parsed} <- SnmpKit.MIB.Parser.parse(text) do
      check(parsed, opts)
    end
  end

  @doc "One line per finding: `MIB-NAME:LINE: severity: [code] message`."
  @spec format(finding(), String.t() | nil) :: String.t()
  def format(finding, prefix \\ nil) do
    location =
      [prefix, finding.line && Integer.to_string(finding.line)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    location = if location == "", do: "", else: location <> ": "
    "#{location}#{finding.severity}: [#{finding.code}] #{finding.message}"
  end

  ## checks

  defp run(mib, opts) do
    definitions = Enum.filter(mib.definitions, &(is_map(&1) and is_binary(Map.get(&1, :name))))
    context_names = context_names(Keyword.get(opts, :context, []))
    known = Map.merge(default_known(opts), context_names)
    imports = imports(mib)
    version = smi_version(mib, imports)
    by_name = Enum.group_by(definitions, & &1.name)
    resolved = Resolver.resolve_definition_oids(definitions, known)
    tcs = Syntax.textual_conventions(definitions)

    env = %{
      definitions: definitions,
      by_name: by_name,
      known: known,
      imports: imports,
      imported: MapSet.new(Enum.flat_map(imports, fn {_module, symbols} -> symbols end)),
      context_names: context_names,
      version: version,
      resolved: resolved,
      tcs: tcs
    }

    findings =
      parser_warnings(mib) ++
        duplicate_names(by_name) ++
        oid_findings(env) ++
        type_findings(env) ++
        smi_findings(env) ++
        table_findings(env) ++
        reference_findings(env)

    findings = Enum.sort_by(findings, &{&1.line || 0, &1.code})

    %{
      name: Map.get(mib, :name, "?"),
      findings: findings,
      errors: Enum.count(findings, &(&1.severity == :error)),
      warnings: Enum.count(findings, &(&1.severity == :warning))
    }
  end

  defp parser_warnings(mib) do
    for {line, message} <- Map.get(mib, :warnings, []) do
      finding(:warning, :parser_warning, nil, line, message)
    end
  end

  defp duplicate_names(by_name) do
    for {name, [_, _ | _] = defs} <- by_name do
      finding(
        :error,
        :duplicate_name,
        name,
        line_of(List.last(defs)),
        "`#{name}' is defined more than once"
      )
    end
  end

  defp oid_findings(env) do
    unresolved =
      env.definitions
      |> Enum.filter(&has_oid?/1)
      |> Enum.reject(&Map.has_key?(env.resolved, &1.name))
      |> Enum.map(fn defn ->
        parent = parent_name(defn)

        cond do
          # the parent is defined here but could not be resolved itself: that
          # definition carries the finding, not its descendants
          parent != nil and Map.has_key?(env.by_name, parent) ->
            nil

          parent != nil and MapSet.member?(env.imported, parent) ->
            finding(
              :warning,
              :unknown_import,
              defn.name,
              line_of(defn),
              "parent `#{parent}' is imported from a module that is not available"
            )

          parent != nil ->
            finding(
              :error,
              :unresolved_parent,
              defn.name,
              line_of(defn),
              "parent `#{parent}' of `#{defn.name}' is not defined, imported or known"
            )

          true ->
            finding(
              :error,
              :unresolved_parent,
              defn.name,
              line_of(defn),
              "the OID of `#{defn.name}' cannot be resolved"
            )
        end
      end)

    duplicates =
      env.resolved
      |> Enum.group_by(fn {_name, oid} -> oid end, fn {name, _} -> name end)
      |> Enum.filter(fn {_oid, names} -> length(names) > 1 end)
      |> Enum.map(fn {oid, names} ->
        [first | others] = Enum.sort(names)
        name = List.last(others)

        finding(
          :error,
          :duplicate_oid,
          name,
          line_of(Map.get(env.by_name, name, [%{}]) |> hd()),
          "`#{name}' has the same OID as `#{first}' (#{Enum.join(oid, ".")})"
        )
      end)

    Enum.reject(unresolved, &is_nil/1) ++ duplicates
  end

  defp type_findings(env) do
    env.definitions
    |> Enum.filter(&(&1.__type__ in [:object_type, :textual_convention]))
    |> Enum.flat_map(fn defn ->
      case named_type(Map.get(defn, :syntax)) do
        nil ->
          []

        type ->
          cond do
            type in @builtin_types or Map.has_key?(env.tcs, type) or
                Map.has_key?(env.by_name, type) ->
              []

            Map.has_key?(env.context_names, type) ->
              []

            MapSet.member?(env.imported, type) ->
              [
                finding(
                  :warning,
                  :unknown_import,
                  defn.name,
                  line_of(defn),
                  "type `#{type}' is imported from a module that is not available"
                )
              ]

            true ->
              [
                finding(
                  :error,
                  :unknown_type,
                  defn.name,
                  line_of(defn),
                  "type `#{type}' used by `#{defn.name}' is not defined, imported or built in"
                )
              ]
          end
      end
    end)
    |> Enum.uniq_by(&{&1.code, &1.name, &1.message})
  end

  defp smi_findings(%{version: :v2} = env) do
    v1_objects =
      env.definitions
      |> Enum.filter(
        &(&1.__type__ == :object_type and Map.get(&1, :status) in [:mandatory, :optional])
      )
      |> Enum.map(fn defn ->
        finding(
          :warning,
          :smiv1_in_smiv2,
          defn.name,
          line_of(defn),
          "`#{defn.name}' uses SMIv1 ACCESS/STATUS (#{defn.status}) in an SMIv2 module"
        )
      end)

    identity =
      if Enum.any?(env.definitions, &(&1.__type__ == :module_identity)),
        do: [],
        else: [
          finding(
            :warning,
            :missing_module_identity,
            nil,
            nil,
            "SMIv2 module without a MODULE-IDENTITY"
          )
        ]

    v1_objects ++ identity
  end

  defp smi_findings(_env), do: []

  defp table_findings(env) do
    sequences =
      env.definitions |> Enum.filter(&(&1.__type__ == :sequence)) |> Map.new(&{&1.name, &1})

    objects =
      env.definitions |> Enum.filter(&(&1.__type__ == :object_type)) |> Map.new(&{&1.name, &1})

    # a row's SYNTAX is the SEQUENCE type itself; the table's is SEQUENCE OF it
    rows =
      Enum.filter(objects, fn {_name, defn} ->
        case row_type(Map.get(defn, :syntax)) do
          nil -> false
          type -> Map.has_key?(sequences, type)
        end
      end)

    Enum.flat_map(rows, fn {row_name, row} ->
      sequence = Map.fetch!(sequences, row_type(row.syntax))
      row_oid = Map.get(env.resolved, row_name)

      columns =
        if row_oid do
          objects
          |> Enum.filter(fn {name, _} ->
            case Map.get(env.resolved, name) do
              oid when is_list(oid) ->
                length(oid) == length(row_oid) + 1 and List.starts_with?(oid, row_oid)

              _ ->
                false
            end
          end)
          |> Map.new()
        else
          %{}
        end

      index_findings(row, env) ++ sequence_findings(row, sequence, columns, env)
    end)
  end

  defp index_findings(row, env) do
    case Map.get(row, :kind) do
      {:table_entry, {:indexes, indexes}} ->
        Enum.flat_map(indexes, fn
          {:implied, _name} ->
            []

          name ->
            name = to_string(name)

            case Map.get(env.by_name, name) do
              [%{__type__: :object_type} = index_object | _] ->
                desc = Syntax.describe(index_object.syntax, env.tcs)

                if desc.base in [:octet_string, :object_identifier] and desc.size == nil and
                     desc.textual_convention == nil do
                  [
                    finding(
                      :warning,
                      :index_without_size,
                      name,
                      line_of(index_object),
                      "index object `#{name}' of row `#{row.name}' has no SIZE restriction"
                    )
                  ]
                else
                  []
                end

              _ ->
                if MapSet.member?(env.imported, name) or Map.has_key?(env.known, name),
                  do: [],
                  else: [
                    finding(
                      :warning,
                      :unknown_object,
                      row.name,
                      line_of(row),
                      "index object `#{name}' of row `#{row.name}' is not defined"
                    )
                  ]
            end
        end)

      {:table_entry, {:augments, _}} ->
        []

      _ ->
        [
          finding(
            :error,
            :row_without_index,
            row.name,
            line_of(row),
            "row `#{row.name}' has neither INDEX nor AUGMENTS"
          )
        ]
    end
  end

  defp sequence_findings(row, sequence, columns, env) do
    field_names = Enum.map(sequence.fields, fn {name, _} -> name end)

    undefined =
      for name <- field_names,
          not Map.has_key?(columns, name) and not Map.has_key?(env.by_name, name) do
        finding(
          :warning,
          :sequence_field_undefined,
          sequence.name,
          line_of(sequence),
          "SEQUENCE `#{sequence.name}' lists `#{name}', which is not a column of `#{row.name}'"
        )
      end

    missing =
      for {name, column} <- columns, name not in field_names do
        finding(
          :warning,
          :column_not_in_sequence,
          name,
          line_of(column),
          "column `#{name}' of `#{row.name}' is missing from SEQUENCE `#{sequence.name}'"
        )
      end

    mismatched =
      for {name, field_syntax} <- sequence.fields,
          column = Map.get(columns, name),
          column != nil do
        field_base = Syntax.describe(field_syntax, env.tcs).base
        column_base = Syntax.describe(column.syntax, env.tcs).base

        if field_base != nil and column_base != nil and field_base != column_base do
          [
            finding(
              :warning,
              :sequence_type_mismatch,
              name,
              line_of(column),
              "`#{name}' is #{column_base} but its SEQUENCE field is #{field_base}"
            )
          ]
        else
          []
        end
      end
      |> List.flatten()

    undefined ++ missing ++ mismatched
  end

  defp reference_findings(env) do
    env.definitions
    |> Enum.filter(&(&1.__type__ in [:notification, :object_group, :notification_group, :trap]))
    |> Enum.flat_map(fn defn ->
      for name <- Map.get(defn, :objects, []),
          not Map.has_key?(env.by_name, name),
          not MapSet.member?(env.imported, name),
          not Map.has_key?(env.known, name) do
        finding(
          :warning,
          :unknown_object,
          defn.name,
          line_of(defn),
          "`#{defn.name}' references `#{name}', which is not defined or imported"
        )
      end
    end)
  end

  ## helpers

  defp finding(severity, code, name, line, message),
    do: %{severity: severity, code: code, name: name, line: line, message: message}

  defp line_of(%{line: line}) when is_integer(line), do: line
  defp line_of(_), do: nil

  defp has_oid?(%{__type__: :object_identifier}), do: true
  defp has_oid?(%{oid: oid}) when oid != nil, do: true
  defp has_oid?(_), do: false

  defp parent_name(%{parent: parent}) when is_binary(parent), do: parent
  defp parent_name(%{oid: {parent, _}}) when is_binary(parent), do: parent
  defp parent_name(_), do: nil

  defp row_type({term, line}) when is_integer(line), do: row_type(term)
  defp row_type({:type, name}) when is_binary(name), do: name
  defp row_type(_), do: nil

  defp named_type({term, line}) when is_integer(line), do: named_type(term)
  defp named_type({:type, name}) when is_binary(name), do: name
  defp named_type({:type_with_size, name, _}) when is_binary(name), do: name
  defp named_type({:sequence_of, name}), do: to_string(name)
  defp named_type(_), do: nil

  defp imports(mib) do
    mib
    |> Map.get(:imports, [])
    |> Enum.flat_map(fn
      %{from_module: module, symbols: symbols} ->
        [{module, Enum.map(symbols, &to_string/1) -- @macros}]

      _ ->
        []
    end)
  end

  defp smi_version(mib, imports) do
    cond do
      Map.get(mib, :version) == :v2_mib ->
        :v2

      Enum.any?(imports, fn {module, _} -> module in @smiv2_modules end) ->
        :v2

      Enum.any?(
        Map.get(mib, :definitions, []),
        &(is_map(&1) and Map.get(&1, :__type__) == :module_identity)
      ) ->
        :v2

      true ->
        :v1
    end
  end

  defp context_names(context) do
    Enum.reduce(context, %{}, fn
      %{symbols: symbols}, acc ->
        Map.merge(acc, Resolver.resolve_definition_oids(symbols, Builtin.name_to_oid()))
        |> Map.merge(symbols |> Map.keys() |> Map.new(&{&1, nil}), fn _k, oid, _ -> oid end)

      _, acc ->
        acc
    end)
  end

  defp default_known(opts) do
    case Keyword.get(opts, :known) do
      %{} = known ->
        known

      nil ->
        registry =
          if Process.whereis(SnmpKit.SnmpMgr.MIB),
            do: registry_names(),
            else: %{}

        Map.merge(Builtin.name_to_oid(), registry)
    end
  end

  defp registry_names do
    case SnmpKit.SnmpMgr.MIB.walk_tree([1]) do
      {:ok, entries} -> Map.new(entries)
      _ -> %{}
    end
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end
end
