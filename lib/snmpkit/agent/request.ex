defmodule SnmpKit.Agent.Request do
  @moduledoc """
  Answers one request PDU against an agent's registered subtrees: GET,
  GETNEXT, GETBULK and SET with SNMPv1 and SNMPv2c/v3 semantics (RFC 1157,
  RFC 3416, and the v1/v2 error mapping of RFC 3584). Used by
  `SnmpKit.Agent`; it has no state of its own.
  """

  require Logger

  alias SnmpKit.SnmpLib.PDU
  alias SnmpKit.SnmpSim.PDUHelper

  # RFC 3416 error-status values
  @errors %{
    too_big: 1,
    no_such_name: 2,
    bad_value: 3,
    read_only: 4,
    gen_err: 5,
    no_access: 6,
    wrong_type: 7,
    wrong_length: 8,
    wrong_encoding: 9,
    wrong_value: 10,
    no_creation: 11,
    inconsistent_value: 12,
    resource_unavailable: 13,
    commit_failed: 14,
    undo_failed: 15,
    authorization_error: 16,
    not_writable: 17,
    inconsistent_name: 18
  }

  # RFC 3584 4.4: SNMPv2 error-status values a v1 manager cannot receive
  @v1_bad_value [:wrong_type, :wrong_length, :wrong_encoding, :wrong_value, :inconsistent_value]
  @v1_no_such_name [
    :no_access,
    :no_creation,
    :not_writable,
    :inconsistent_name,
    :authorization_error
  ]

  # UDP payload minus headroom for the message envelope
  @max_response_bytes 65_000
  @max_shadow_hops 10_000

  @type subtree :: %{prefix: [non_neg_integer()], module: module(), ctx: term()}

  @doc """
  Handles `pdu` (as delivered by `SnmpKit.SnmpSim.Core.Server`) and returns
  the response PDU. `subtrees` must be sorted by prefix, longest first;
  `level` is the requester's access, `:read` or `:write`.
  """
  @spec handle(map(), [subtree()], :read | :write) :: map()
  def handle(pdu, subtrees, level) do
    version = PDUHelper.snmp_version(pdu)

    try do
      case pdu.type do
        :get_request -> get(pdu, subtrees, version)
        :get_next_request -> get_next(pdu, subtrees, version)
        :get_bulk_request when version == :v2c -> get_bulk(pdu, subtrees)
        :set_request -> set(pdu, subtrees, version, level)
        _ -> error_response(pdu, :gen_err, 0)
      end
    rescue
      error ->
        Logger.error(
          "SNMP agent handler crashed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )

        error_response(pdu, :gen_err, 0)
    end
  end

  @doc "The value at `oid`, as the agent would answer a GET for it."
  @spec lookup([non_neg_integer()], [subtree()]) ::
          {:ok, {atom(), term()}} | {:error, :no_such_object | :no_such_instance}
  def lookup(oid, subtrees) do
    case get_one(oid, subtrees) do
      {^oid, type, _value} when type in [:no_such_object, :no_such_instance] -> {:error, type}
      {^oid, type, value} -> {:ok, {type, value}}
    end
  end

  @doc "The object after `oid`, as the agent would answer a GETNEXT."
  @spec next([non_neg_integer()], [subtree()]) ::
          {:ok, {[non_neg_integer()], atom(), term()}} | :end_of_mib_view
  def next(oid, subtrees) do
    case next_after(oid, subtrees, :v2c) do
      {:ok, entry} -> {:ok, entry}
      :end -> :end_of_mib_view
    end
  end

  ## GET

  defp get(pdu, subtrees, version) do
    varbinds =
      for oid <- request_oids(pdu) do
        case get_one(oid, subtrees) do
          {_, :counter64, _} when version == :v1 -> exception(oid, :no_such_instance)
          entry -> entry
        end
      end

    respond(pdu, varbinds, version)
  end

  defp get_one(oid, subtrees) do
    case owner(oid, subtrees) do
      nil ->
        exception(oid, :no_such_object)

      %{prefix: prefix, module: module, ctx: ctx} ->
        case module.get(Enum.drop(oid, length(prefix)), ctx) do
          {:ok, {type, value}} -> {oid, normalize_type(type), value}
          {:error, :no_such_instance} -> exception(oid, :no_such_instance)
          _ -> exception(oid, :no_such_object)
        end
    end
  end

  ## GETNEXT and GETBULK

  defp get_next(pdu, subtrees, version) do
    varbinds =
      for oid <- request_oids(pdu) do
        case next_after(oid, subtrees, version) do
          {:ok, entry} -> entry
          :end -> exception(oid, :end_of_mib_view)
        end
      end

    respond(pdu, varbinds, version)
  end

  defp get_bulk(pdu, subtrees) do
    oids = request_oids(pdu)
    non_repeaters = max(Map.get(pdu, :non_repeaters, 0), 0)
    max_repetitions = max(Map.get(pdu, :max_repetitions, 0), 0)
    {single, repeated} = Enum.split(oids, non_repeaters)

    head =
      for oid <- single do
        case next_after(oid, subtrees, :v2c) do
          {:ok, entry} -> entry
          :end -> exception(oid, :end_of_mib_view)
        end
      end

    columns = Enum.map(repeated, &repetitions(&1, subtrees, max_repetitions))
    rows = Enum.max(Enum.map(columns, &length/1), fn -> 0 end)

    tail =
      for row <- 0..(rows - 1)//1,
          {column, oid} <- Enum.zip(columns, repeated) do
        Enum.at(column, row) || exception(last_oid(column, oid), :end_of_mib_view)
      end

    pdu
    |> respond(head ++ tail, :v2c)
    |> fit_response(pdu, length(head))
  end

  # up to `max` successors of `oid`; one endOfMibView closes a short column
  defp repetitions(oid, subtrees, max) do
    Stream.unfold({oid, max}, fn
      {_current, 0} ->
        nil

      {current, left} ->
        case next_after(current, subtrees, :v2c) do
          {:ok, {next, _, _} = entry} -> {entry, {next, left - 1}}
          :end -> {exception(current, :end_of_mib_view), {current, 0}}
        end
    end)
    |> Enum.to_list()
  end

  defp last_oid([], oid), do: oid
  defp last_oid(column, _oid), do: column |> List.last() |> elem(0)

  # RFC 3416 4.2.3: drop trailing repetitions until the response fits
  defp fit_response(response, pdu, keep) do
    if length(response.varbinds) > 50 and encoded_size(response) > @max_response_bytes do
      {head, tail} = Enum.split(response.varbinds, keep)
      shrunk = Enum.take(tail, max(div(length(tail) * 3, 4), 1))
      fit_response(%{response | varbinds: head ++ shrunk}, pdu, keep)
    else
      response
    end
  end

  defp encoded_size(response) do
    case PDU.encode_message(PDU.build_message(response, "size", :v2c)) do
      {:ok, packet} -> byte_size(packet)
      {:error, _} -> @max_response_bytes + 1
    end
  end

  defp next_after(oid, subtrees, version),
    do: next_after(oid, subtrees, version, @max_shadow_hops)

  defp next_after(_oid, _subtrees, _version, 0), do: :end

  defp next_after(oid, subtrees, version, hops) do
    candidates =
      for subtree <- subtrees, entry = candidate(subtree, oid), entry != nil, do: entry

    case Enum.min_by(candidates, fn {{coid, _, _}, _} -> coid end, fn -> nil end) do
      nil ->
        :end

      {{coid, :counter64, _}, _subtree} when version == :v1 ->
        next_after(coid, subtrees, version, hops - 1)

      {{coid, _, _} = entry, subtree} ->
        # an object inside a more specific subtree is served by that subtree
        if owner(coid, subtrees) == subtree,
          do: {:ok, entry},
          else: next_after(coid, subtrees, version, hops - 1)
    end
  end

  defp candidate(%{prefix: prefix, module: module, ctx: ctx} = subtree, oid) do
    suffix =
      cond do
        List.starts_with?(oid, prefix) -> Enum.drop(oid, length(prefix))
        oid < prefix -> []
        true -> nil
      end

    with true <- suffix != nil,
         {:ok, {next_suffix, {type, value}}} <- module.get_next(suffix, ctx) do
      {{prefix ++ next_suffix, normalize_type(type), value}, subtree}
    else
      _ -> nil
    end
  end

  ## SET

  defp set(pdu, subtrees, version, level) do
    varbinds = typed_request_varbinds(pdu)

    with :ok <- check_access(level, version),
         {:ok, plan} <- plan_set(varbinds, subtrees),
         :ok <- run_phase(plan, :check_set),
         :ok <- run_phase(plan, :set) do
      respond(pdu, varbinds, version)
    else
      {:error, reason, index} -> error_response(pdu, v1_error(reason, version), index)
    end
  end

  defp check_access(:write, _version), do: :ok
  defp check_access(_level, :v1), do: {:error, :no_such_name, 1}
  defp check_access(_level, _version), do: {:error, :no_access, 1}

  defp plan_set(varbinds, subtrees) do
    varbinds
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{oid, type, value}, index}, {:ok, acc} ->
      case owner(oid, subtrees) do
        %{module: module} = subtree ->
          if function_exported?(module, :set, 3),
            do:
              {:cont,
               {:ok,
                [{subtree, Enum.drop(oid, length(subtree.prefix)), {type, value}, index} | acc]}},
            else: {:halt, {:error, :not_writable, index}}

        nil ->
          {:halt, {:error, :not_writable, index}}
      end
    end)
    |> case do
      {:ok, plan} -> {:ok, Enum.reverse(plan)}
      error -> error
    end
  end

  defp run_phase(plan, phase) do
    Enum.reduce_while(plan, :ok, fn {%{module: module, ctx: ctx}, suffix, value, index}, :ok ->
      result =
        if phase == :check_set and not function_exported?(module, :check_set, 3),
          do: :ok,
          else: apply(module, phase, [suffix, value, ctx])

      case result do
        :ok -> {:cont, :ok}
        {:error, reason} when is_map_key(@errors, reason) -> {:halt, {:error, reason, index}}
        {:error, _other} when phase == :set -> {:halt, {:error, :commit_failed, index}}
        {:error, _other} -> {:halt, {:error, :wrong_value, index}}
      end
    end)
  end

  defp v1_error(reason, :v1) when reason in @v1_bad_value, do: :bad_value
  defp v1_error(reason, :v1) when reason in @v1_no_such_name, do: :no_such_name

  defp v1_error(reason, :v1) when reason in [:resource_unavailable, :commit_failed, :undo_failed],
    do: :gen_err

  defp v1_error(reason, _version), do: reason

  ## responses

  defp respond(pdu, varbinds, version) do
    %{
      type: :get_response,
      version: pdu.version,
      community: pdu.community,
      request_id: pdu.request_id,
      error_status: 0,
      error_index: 0,
      varbinds: varbinds
    }
    |> PDUHelper.apply_v1_error_semantics(version, typed_request_varbinds(pdu))
  end

  defp error_response(pdu, reason, index) do
    %{
      type: :get_response,
      version: pdu.version,
      community: pdu.community,
      request_id: pdu.request_id,
      error_status: Map.fetch!(@errors, reason),
      error_index: index,
      varbinds: typed_request_varbinds(pdu)
    }
  end

  defp exception(oid, type), do: {oid, type, {type, nil}}

  ## request varbinds

  defp request_oids(pdu), do: Enum.map(typed_request_varbinds(pdu), &elem(&1, 0))

  defp typed_request_varbinds(pdu) do
    (Map.get(pdu, :typed_varbinds) || Map.get(pdu, :varbinds, []))
    |> Enum.map(fn
      {oid, type, value} -> {to_oid(oid), normalize_type(type), value}
      {oid, nil} -> {to_oid(oid), :null, nil}
      {oid, :null} -> {to_oid(oid), :null, nil}
      {oid, value} -> {to_oid(oid), guess_type(value), value}
    end)
  end

  defp to_oid(oid) when is_list(oid), do: oid

  defp to_oid(oid) when is_binary(oid) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid) do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp guess_type(value) when is_binary(value), do: :octet_string
  defp guess_type(value) when is_integer(value), do: :integer
  defp guess_type(_), do: :null

  defp normalize_type(:string), do: :octet_string
  defp normalize_type(:unsigned32), do: :gauge32
  defp normalize_type(:oid), do: :object_identifier
  defp normalize_type(:bits), do: :octet_string
  defp normalize_type(type), do: type

  ## subtrees

  # longest registered prefix that contains `oid`
  defp owner(oid, subtrees), do: Enum.find(subtrees, &List.starts_with?(oid, &1.prefix))
end
