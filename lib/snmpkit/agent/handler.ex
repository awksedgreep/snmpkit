defmodule SnmpKit.Agent.Handler do
  @moduledoc """
  Behaviour for a module that serves one subtree of an agent's MIB.

  A handler is registered at an OID prefix with `SnmpKit.Agent.register/4`.
  The agent strips the prefix before calling it, so every callback works with
  the *suffix* below the prefix: for a handler at `ifEntry`
  (`1.3.6.1.2.1.2.2.1`) a GET of `ifDescr.3` arrives as `[2, 3]`.

  `ctx` is whatever `c:init/1` returned at registration (or the registration
  options themselves when the module has no `init/1`). Callbacks run in the
  request's worker process, concurrently with other requests, so a handler
  that keeps state should read it from ETS, an Agent, or a GenServer rather
  than from its `ctx`.

      defmodule MyApp.QueueStats do
        @behaviour SnmpKit.Agent.Handler

        # .1.0 = depth, .2.0 = processed; suffixes kept in lexicographic order
        @objects [
          {[1, 0], :gauge32, &MyApp.Queue.depth/0},
          {[2, 0], :counter32, &MyApp.Queue.processed/0}
        ]

        def get(suffix, _ctx) do
          case List.keyfind(@objects, suffix, 0) do
            {_, type, fun} -> {:ok, {type, fun.()}}
            nil -> {:error, :no_such_instance}
          end
        end

        def get_next(suffix, _ctx) do
          case Enum.find(@objects, fn {s, _, _} -> s > suffix end) do
            {s, type, fun} -> {:ok, {s, {type, fun.()}}}
            nil -> :end_of_subtree
          end
        end
      end

  `SnmpKit.Agent.Store` (scalars kept in ETS) and `SnmpKit.Agent.Table`
  (rows produced by a function) are ready-made handlers for the common cases.

  ## Values

  Values are `{type, value}` with the types used everywhere else in SnmpKit:
  `:integer`, `:octet_string` (or `:string`), `:object_identifier`,
  `:counter32`, `:gauge32` (or `:unsigned32`), `:timeticks`, `:counter64`,
  `:ip_address` (a 4-tuple or 4 octets), `:opaque`, `:null`.

  ## SET

  A SET request runs in two phases. `c:check_set/3` is called for every
  varbind first, and nothing is written unless all of them return `:ok`;
  then `c:set/3` is called in order. A handler without `set/3` makes its
  subtree read-only (`notWritable`). Error reasons map to SNMP error-status
  values: `:no_access`, `:wrong_type`, `:wrong_length`, `:wrong_encoding`,
  `:wrong_value`, `:no_creation`, `:inconsistent_value`,
  `:resource_unavailable`, `:commit_failed`, `:undo_failed`,
  `:not_writable`, `:inconsistent_name`, `:gen_err`.
  """

  @type suffix :: [non_neg_integer()]
  @type value :: {atom(), term()}
  @type ctx :: term()
  @type set_error ::
          :no_access
          | :wrong_type
          | :wrong_length
          | :wrong_encoding
          | :wrong_value
          | :no_creation
          | :inconsistent_value
          | :resource_unavailable
          | :commit_failed
          | :undo_failed
          | :not_writable
          | :inconsistent_name
          | :gen_err

  @doc "Turns the registration options into the `ctx` passed to the other callbacks."
  @callback init(opts :: keyword()) :: {:ok, ctx()} | {:error, term()}

  @doc """
  The value of the object at `suffix`. `{:error, :no_such_instance}` when the
  object exists but this instance does not, `{:error, :no_such_object}` when
  nothing of that name exists in the subtree.
  """
  @callback get(suffix(), ctx()) ::
              {:ok, value()} | {:error, :no_such_object | :no_such_instance}

  @doc """
  The first object whose suffix is lexicographically greater than `suffix`
  (`[]` asks for the first object in the subtree), or `:end_of_subtree`.
  """
  @callback get_next(suffix(), ctx()) :: {:ok, {suffix(), value()}} | :end_of_subtree

  @doc "Validates a SET without applying it."
  @callback check_set(suffix(), value(), ctx()) :: :ok | {:error, set_error()}

  @doc "Applies a SET."
  @callback set(suffix(), value(), ctx()) :: :ok | {:error, set_error()}

  @optional_callbacks init: 1, check_set: 3, set: 3
end
