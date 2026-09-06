defmodule SnmpKit.MIB.Syntax do
  @moduledoc """
  Turns the syntax terms produced by the MIB grammar into a small
  description: base type, textual convention, DISPLAY-HINT and enumeration
  labels.

      %{
        base: :integer,
        textual_convention: "RowStatus",
        display_hint: nil,
        enumerations: %{1 => "active", 2 => "notInService", ...}
      }

  The registry and the formatter use these descriptions to render values the
  way `snmpwalk` does: enumeration labels instead of numbers, MAC addresses
  from `1x:` hints, dates from DateAndTime.
  """

  @type description :: %{
          base: atom() | nil,
          textual_convention: String.t() | nil,
          display_hint: String.t() | nil,
          enumerations: %{integer() => String.t()} | nil,
          size: {non_neg_integer(), non_neg_integer()} | nil
        }

  @empty %{base: nil, textual_convention: nil, display_hint: nil, enumerations: nil, size: nil}

  # Textual conventions the grammar knows as reserved words (SNMPv2-TC)
  @builtin_tcs %{
    "DisplayString" => %{base: :octet_string, display_hint: "255a", enumerations: nil},
    "PhysAddress" => %{base: :octet_string, display_hint: "1x:", enumerations: nil},
    "MacAddress" => %{base: :octet_string, display_hint: "1x:", enumerations: nil, size: {6, 6}},
    "TruthValue" => %{
      base: :integer,
      display_hint: nil,
      enumerations: %{1 => "true", 2 => "false"}
    },
    "TestAndIncr" => %{base: :integer, display_hint: nil, enumerations: nil},
    "AutonomousType" => %{base: :object_identifier, display_hint: nil, enumerations: nil},
    "InstancePointer" => %{base: :object_identifier, display_hint: nil, enumerations: nil},
    "VariablePointer" => %{base: :object_identifier, display_hint: nil, enumerations: nil},
    "RowPointer" => %{base: :object_identifier, display_hint: nil, enumerations: nil},
    "RowStatus" => %{
      base: :integer,
      display_hint: nil,
      enumerations: %{
        1 => "active",
        2 => "notInService",
        3 => "notReady",
        4 => "createAndGo",
        5 => "createAndWait",
        6 => "destroy"
      }
    },
    "TimeStamp" => %{base: :timeticks, display_hint: nil, enumerations: nil},
    "TimeInterval" => %{base: :integer, display_hint: nil, enumerations: nil},
    "DateAndTime" => %{
      base: :octet_string,
      display_hint: "2d-1d-1d,1d:1d:1d.1d,1a1d:1d",
      enumerations: nil
    },
    "StorageType" => %{
      base: :integer,
      display_hint: nil,
      enumerations: %{
        1 => "other",
        2 => "volatile",
        3 => "nonVolatile",
        4 => "permanent",
        5 => "readOnly"
      }
    },
    "TDomain" => %{base: :object_identifier, display_hint: nil, enumerations: nil},
    "TAddress" => %{base: :octet_string, display_hint: nil, enumerations: nil}
  }

  @doc "The SNMPv2-TC textual conventions built into the parser, by name."
  @spec builtin_textual_conventions() :: %{String.t() => map()}
  def builtin_textual_conventions, do: @builtin_tcs

  @doc """
  Describes a syntax term. `tc_map` maps textual-convention names to
  descriptions (as built by `textual_conventions/1`) so references resolve.
  """
  @spec describe(term(), %{String.t() => map()}) :: description()
  def describe(syntax, tc_map \\ %{})

  # grammar terms carry their line: {term, line}
  def describe({term, line}, tc_map) when is_integer(line), do: describe(term, tc_map)

  def describe({:type, name}, tc_map), do: named(name, tc_map)

  def describe({:type_with_size, name, size}, tc_map),
    do: %{named(name, tc_map) | size: size_range(size)}

  def describe({:type_with_enum, _base, bits}, _tc_map),
    do: %{@empty | base: :integer, enumerations: enumerations(bits)}

  def describe({:bits, bits}, _tc_map),
    do: %{@empty | base: :bits, enumerations: enumerations(bits)}

  def describe({:integer, _constraints}, _), do: %{@empty | base: :integer}
  def describe({:octet_string, _size}, _), do: %{@empty | base: :octet_string}
  def describe({:object_identifier, _}, _), do: %{@empty | base: :object_identifier}
  def describe(atom, tc_map) when is_atom(atom), do: named(atom, tc_map)
  def describe(_other, _tc_map), do: @empty

  @doc """
  Builds the textual-convention map for a parsed MIB: the built-in SNMPv2-TC
  conventions plus every TEXTUAL-CONVENTION and type assignment in
  `definitions`, each resolved through the conventions it derives from.
  """
  @spec textual_conventions([map()]) :: %{String.t() => map()}
  def textual_conventions(definitions) when is_list(definitions) do
    tcs = Enum.filter(definitions, &(Map.get(&1, :__type__) == :textual_convention))

    # Resolve in passes so a TC defined in terms of another TC (in any order) settles
    Enum.reduce(1..3, @builtin_tcs, fn _, acc ->
      Enum.reduce(tcs, acc, fn tc, acc ->
        desc = describe(Map.get(tc, :syntax), acc)

        entry = %{
          base: desc.base,
          display_hint: Map.get(tc, :display_hint) || desc.display_hint,
          enumerations: desc.enumerations,
          size: desc.size
        }

        Map.put(acc, Map.get(tc, :name), entry)
      end)
    end)
  end

  ## helpers

  defp named(name, tc_map) when is_binary(name) do
    case Map.get(tc_map, name) do
      %{} = tc ->
        %{
          base: tc.base,
          textual_convention: name,
          display_hint: tc.display_hint,
          enumerations: tc.enumerations,
          size: Map.get(tc, :size)
        }

      nil ->
        %{@empty | textual_convention: name}
    end
  end

  defp named(atom, tc_map) when is_atom(atom) do
    case atom do
      :INTEGER -> %{@empty | base: :integer}
      :Integer32 -> %{@empty | base: :integer}
      :integer -> %{@empty | base: :integer}
      :"OCTET STRING" -> %{@empty | base: :octet_string}
      :"octet string" -> %{@empty | base: :octet_string}
      :octet_string -> %{@empty | base: :octet_string}
      :"OBJECT IDENTIFIER" -> %{@empty | base: :object_identifier}
      :"object identifier" -> %{@empty | base: :object_identifier}
      :object_identifier -> %{@empty | base: :object_identifier}
      :"BIT STRING" -> %{@empty | base: :bits}
      :BITS -> %{@empty | base: :bits}
      :Counter -> %{@empty | base: :counter32}
      :Counter32 -> %{@empty | base: :counter32}
      :counter32 -> %{@empty | base: :counter32}
      :Counter64 -> %{@empty | base: :counter64}
      :counter64 -> %{@empty | base: :counter64}
      :Gauge -> %{@empty | base: :gauge32}
      :Gauge32 -> %{@empty | base: :gauge32}
      :gauge32 -> %{@empty | base: :gauge32}
      :Unsigned32 -> %{@empty | base: :gauge32}
      :TimeTicks -> %{@empty | base: :timeticks}
      :timeticks -> %{@empty | base: :timeticks}
      :IpAddress -> %{@empty | base: :ip_address}
      :NetworkAddress -> %{@empty | base: :ip_address}
      :ip_address -> %{@empty | base: :ip_address}
      :Opaque -> %{@empty | base: :opaque}
      :NULL -> %{@empty | base: :null}
      other -> named(Atom.to_string(other), tc_map)
    end
  end

  # grammar: {range, Min, Max}; SIZE (6) gives {range, 6, 6}
  defp size_range({:range, min, max}) when is_integer(min) and is_integer(max), do: {min, max}
  defp size_range(_), do: nil

  defp enumerations(bits) when is_list(bits) do
    Map.new(bits, fn {label, value} -> {value, to_string(label)} end)
  end

  defp enumerations(_), do: nil
end
