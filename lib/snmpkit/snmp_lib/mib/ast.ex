defmodule SnmpKit.SnmpLib.MIB.AST do
  @moduledoc """
  Abstract Syntax Tree definitions for MIB compilation.

  Faithfully ported from Erlang OTP snmpc_mib_gram.yrl and related structures.
  Provides the complete AST representation needed for SNMP MIB compilation.
  """

  @type line_number :: integer()

  # Top-level MIB structure
  @type mib :: %{
          __type__: :mib,
          name: binary(),
          last_updated: binary() | nil,
          organization: binary() | nil,
          contact_info: binary() | nil,
          description: binary() | nil,
          revision_history: [revision()],
          imports: [import()],
          definitions: [definition()],
          oid_tree: oid_tree(),
          metadata: metadata()
        }

  @type revision :: %{
          __type__: :revision,
          date: binary(),
          description: binary(),
          line: line_number()
        }

  # Import statement from other MIBs
  @type import :: %{
          __type__: :import,
          symbols: [binary()],
          from_module: binary(),
          line: line_number()
        }

  # MIB definitions (various types)
  @type definition ::
          object_type()
          | object_identity()
          | object_group()
          | notification_type()
          | notification_group()
          | module_identity()
          | module_compliance()
          | agent_capabilities()
          | textual_convention()
          | trap_type()
          | object_identifier_assignment()

  # Object Type Definition (OBJECT-TYPE)
  @type object_type :: %{
          __type__: :object_type,
          name: binary(),
          syntax: syntax(),
          units: binary() | nil,
          max_access: access_level(),
          status: status(),
          description: binary(),
          reference: binary() | nil,
          index: index_spec() | nil,
          augments: binary() | nil,
          defval: default_value() | nil,
          oid: oid(),
          line: line_number()
        }

  # Object Identity Definition (OBJECT-IDENTITY)
  @type object_identity :: %{
          __type__: :object_identity,
          name: binary(),
          status: status(),
          description: binary(),
          reference: binary() | nil,
          oid: oid(),
          line: line_number()
        }

  # Module Identity Definition (MODULE-IDENTITY) - SNMPv2 only
  @type module_identity :: %{
          __type__: :module_identity,
          name: binary(),
          last_updated: binary(),
          organization: binary(),
          contact_info: binary(),
          description: binary(),
          revision_history: [revision()],
          oid: oid(),
          line: line_number()
        }

  # Object Group Definition (OBJECT-GROUP)
  @type object_group :: %{
          __type__: :object_group,
          name: binary(),
          objects: [binary()],
          status: status(),
          description: binary(),
          reference: binary() | nil,
          oid: oid(),
          line: line_number()
        }

  # Notification Type Definition (NOTIFICATION-TYPE)
  @type notification_type :: %{
          __type__: :notification_type,
          name: binary(),
          objects: [binary()],
          status: status(),
          description: binary(),
          reference: binary() | nil,
          oid: oid(),
          line: line_number()
        }

  # Notification Group Definition (NOTIFICATION-GROUP)
  @type notification_group :: %{
          __type__: :notification_group,
          name: binary(),
          notifications: [binary()],
          status: status(),
          description: binary(),
          reference: binary() | nil,
          oid: oid(),
          line: line_number()
        }

  # Module Compliance Definition (MODULE-COMPLIANCE)
  @type module_compliance :: %{
          __type__: :module_compliance,
          name: binary(),
          status: status(),
          description: binary(),
          reference: binary() | nil,
          modules: [compliance_module()],
          oid: oid(),
          line: line_number()
        }

  @type compliance_module :: %{
          module_name: binary(),
          mandatory_groups: [binary()],
          compliance_objects: [compliance_object()]
        }

  @type compliance_object :: %{
          object: binary(),
          syntax: syntax() | nil,
          write_syntax: syntax() | nil,
          access: access_level() | nil,
          description: binary() | nil
        }

  # Agent Capabilities Definition (AGENT-CAPABILITIES)
  @type agent_capabilities :: %{
          __type__: :agent_capabilities,
          name: binary(),
          product_release: binary(),
          status: status(),
          description: binary(),
          reference: binary() | nil,
          modules: [capability_module()],
          oid: oid(),
          line: line_number()
        }

  @type capability_module :: %{
          module_name: binary(),
          includes: [binary()],
          variations: [object_variation()]
        }

  @type object_variation :: %{
          object: binary(),
          syntax: syntax() | nil,
          write_syntax: syntax() | nil,
          access: access_level() | nil,
          creation: boolean(),
          defval: default_value() | nil,
          description: binary()
        }

  # Textual Convention Definition (TEXTUAL-CONVENTION)
  @type textual_convention :: %{
          __type__: :textual_convention,
          name: binary(),
          display_hint: binary() | nil,
          status: status(),
          description: binary(),
          reference: binary() | nil,
          syntax: syntax(),
          line: line_number()
        }

  # Trap Type Definition (TRAP-TYPE) - SNMPv1 only
  @type trap_type :: %{
          __type__: :trap_type,
          name: binary(),
          enterprise: oid(),
          variables: [binary()],
          description: binary() | nil,
          reference: binary() | nil,
          trap_number: integer(),
          line: line_number()
        }

  # Object Identifier Assignment
  @type object_identifier_assignment :: %{
          __type__: :object_identifier_assignment,
          name: binary(),
          oid: oid(),
          line: line_number()
        }

  # Syntax Definitions
  @type syntax ::
          primitive_syntax() | constructed_syntax() | named_syntax()

  @type primitive_syntax ::
          :integer
          | :octet_string
          | :object_identifier
          | :null
          | :real
          | {:integer, constraints()}
          | {:octet_string, constraints()}
          | {:object_identifier, constraints()}

  @type constructed_syntax ::
          {:sequence, [sequence_element()]}
          | {:sequence_of, syntax()}
          | {:choice, [choice_element()]}
          | {:bit_string, [named_bit()]}

  @type named_syntax ::
          {:named_type, binary()}
          | {:application_type, tag(), syntax()}
          | {:context_type, tag(), syntax()}

  @type sequence_element :: %{
          name: binary(),
          syntax: syntax(),
          optional: boolean(),
          default: default_value() | nil
        }

  @type choice_element :: %{
          name: binary(),
          syntax: syntax()
        }

  @type named_bit :: %{
          name: binary(),
          bit_number: integer()
        }

  @type tag :: integer()

  # Constraint Definitions
  @type constraints :: [constraint()]

  @type constraint ::
          {:size, size_constraint()}
          | {:range, range_constraint()}
          | {:named_values, [named_value()]}
          | {:contained_subtype, syntax()}

  @type size_constraint ::
          integer() | {integer(), integer()} | [size_range()]

  @type range_constraint ::
          {integer(), integer()} | [range_spec()]

  @type size_range :: integer() | {integer(), integer()}
  @type range_spec :: integer() | {integer(), integer()}

  @type named_value :: %{
          name: binary(),
          value: integer()
        }

  # Index Specifications
  @type index_spec ::
          {:index, [index_element()]}
          | {:implied, [index_element()]}

  @type index_element ::
          binary() | {:implied, binary()}

  # Access Levels
  @type access_level ::
          :not_accessible
          | :accessible_for_notify
          | :read_only
          | :read_write
          | :read_create
          # Legacy SNMPv1 access levels
          | :write_only

  # Status Values
  @type status :: :current | :deprecated | :obsolete | :mandatory

  # Default Values
  @type default_value ::
          nil
          | integer()
          | binary()
          | atom()
          | [default_value()]
          | {:named_value, binary()}
          | {:bit_string, [binary()]}

  # OID Representation
  @type oid :: [integer()] | [oid_element()]
  @type oid_element :: integer() | {binary(), integer()}

  # Performance: Use ETS for large OID trees in production
  @type oid_tree :: :ets.tid() | map()

  # Compilation Metadata
  @type metadata :: %{
          compile_time: DateTime.t(),
          compiler_version: binary(),
          source_file: Path.t(),
          snmp_version: :v1 | :v2c,
          dependencies: [binary()],
          warnings: [binary()],
          line_count: integer()
        }

  # Helper Functions for AST Construction

  @doc """
  Create a new MIB AST node.
  """
  @spec new_mib(binary(), keyword()) :: mib()
  def new_mib(name, opts \\ []) do
    %{
      __type__: :mib,
      name: name,
      last_updated: opts[:last_updated],
      organization: opts[:organization],
      contact_info: opts[:contact_info],
      description: opts[:description],
      revision_history: opts[:revision_history] || [],
      imports: opts[:imports] || [],
      definitions: opts[:definitions] || [],
      oid_tree: opts[:oid_tree] || %{},
      metadata: opts[:metadata] || %{}
    }
  end

  @doc """
  Create a new object type definition.
  """
  @spec new_object_type(binary(), keyword()) :: object_type()
  def new_object_type(name, opts) do
    %{
      __type__: :object_type,
      name: name,
      syntax: opts[:syntax],
      units: opts[:units],
      max_access: opts[:max_access],
      status: opts[:status],
      description: opts[:description],
      reference: opts[:reference],
      index: opts[:index],
      augments: opts[:augments],
      defval: opts[:defval],
      oid: opts[:oid],
      line: opts[:line]
    }
  end

  @doc """
  Create a new object identity definition.
  """
  @spec new_object_identity(binary(), keyword()) :: object_identity()
  def new_object_identity(name, opts) do
    %{
      __type__: :object_identity,
      name: name,
      status: opts[:status],
      description: opts[:description],
      reference: opts[:reference],
      oid: opts[:oid],
      line: opts[:line]
    }
  end

  @doc """
  Create a new import statement.
  """
  @spec new_import([binary()], binary(), line_number()) :: import()
  def new_import(symbols, from_module, line) do
    %{
      __type__: :import,
      symbols: symbols,
      from_module: from_module,
      line: line
    }
  end

  @doc """
  Determine SNMP version based on MIB content.

  Per Erlang implementation: presence of MODULE-IDENTITY indicates SNMPv2.
  """
  @spec determine_snmp_version([definition()]) :: :v1 | :v2c
  def determine_snmp_version(definitions) do
    has_module_identity =
      Enum.any?(definitions, fn
        %{__type__: :module_identity} -> true
        _ -> false
      end)

    if has_module_identity, do: :v2c, else: :v1
  end

  @doc """
  Build an OID tree from definitions for fast lookups.
  """
  @spec build_oid_tree([definition()]) :: oid_tree()
  def build_oid_tree(definitions) do
    # Use ETS for performance with large MIBs
    tid = :ets.new(:oid_tree, [:set, :protected])

    Enum.each(definitions, fn definition ->
      case extract_oid_mapping(definition) do
        {name, oid} when is_list(oid) ->
          :ets.insert(tid, {oid, name})
          :ets.insert(tid, {name, oid})

        nil ->
          :ok
      end
    end)

    tid
  end

  # Extract OID mapping from definition
  defp extract_oid_mapping(%{name: name, oid: oid}) when is_list(oid) do
    {name, oid}
  end

  defp extract_oid_mapping(_), do: nil

  @doc """
  Validate AST node structure.
  """
  @spec validate_node(term()) :: {:ok, term()} | {:error, binary()}
  def validate_node(%{__type__: type} = node)
      when type in [
             :mib,
             :object_type,
             :object_identity,
             :module_identity,
             :object_group,
             :notification_type,
             :notification_group,
             :module_compliance,
             :agent_capabilities,
             :textual_convention,
             :trap_type,
             :object_identifier_assignment,
             :import,
             :revision
           ] do
    {:ok, node}
  end

  def validate_node(node) do
    {:error, "Invalid AST node: #{inspect(node)}"}
  end

  @doc """
  Pretty print AST node for debugging.
  """
  @spec pretty_print(term()) :: binary()
  def pretty_print(%{__type__: type, name: name}) do
    "#{type}: #{name}"
  end

  def pretty_print(%{__type__: type}) do
    "#{type}"
  end

  def pretty_print(other) do
    inspect(other)
  end
end
