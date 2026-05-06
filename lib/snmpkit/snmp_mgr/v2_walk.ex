defmodule SnmpKit.SnmpMgr.V2Walk do
  @moduledoc """
  Handles iterative SNMP walks for one or many targets.

  Single-target walks still run synchronously in the caller, while multi-target
  walks can share one caller process and one UDP socket without spawning a task
  per target.
  """

  require Logger

  alias SnmpKit.SnmpLib.{PDU, Transport}
  alias SnmpKit.SnmpMgr.{EngineV2, RequestIdGenerator, SocketManager}

  @default_timeout 30_000
  @default_walk_timeout 1_200_000
  @max_walk_timeout 1_800_000
  @default_max_repetitions 30
  @default_adaptive_max_repetitions 100
  @default_min_repetitions 5
  @default_fast_response_ms 150
  @default_slow_response_ms 750
  @doc """
  Performs a full SNMP walk for a given target and root OID.
  """
  def walk(request, timeout) do
    case build_walk_state(request, timeout, 0) do
      {:ok, state} -> walk_loop(state)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs bounded multi-target SNMP walks using a shared UDP socket.

  Returns one ordered result per request, preserving input order.
  """
  def walk_multi(requests, opts \\ []) do
    if requests == [] do
      []
    else
      socket = SocketManager.get_socket()
      max_concurrent = max(1, Keyword.get(opts, :max_concurrent, 10))
      global_timeout = Keyword.get(opts, :timeout, @default_timeout)

      state = %{
        socket: socket,
        queue: :queue.from_list(Enum.with_index(requests)),
        active: %{},
        results: %{},
        total: length(requests),
        global_timeout: global_timeout,
        max_concurrent: max_concurrent
      }

      state
      |> launch_walks()
      |> await_walks()
      |> ordered_results()
    end
  end

  defp walk_loop(state) do
    case send_walk_request(SocketManager.get_socket(), state) do
      {:ok, state} ->
        receive_timeout = min(state.timeout, remaining_walk_time(state))

        receive do
          {:snmp_response, request_id, response_data} ->
            if request_id == state.request_id do
              handle_walk_response(state, response_data, &walk_loop/1)
            else
              walk_loop(state)
            end

          {:snmp_timeout, request_id} ->
            if request_id == state.request_id do
              Logger.warning(
                "SNMP walk request timeout for target #{inspect(state.request.target)}"
              )

              {:error, :timeout}
            else
              walk_loop(state)
            end
        after
          receive_timeout ->
            EngineV2.unregister_request(EngineV2, state.request_id)

            Logger.warning(
              "SNMP walk internal timeout for target #{inspect(state.request.target)}"
            )

            {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp launch_walks(state) do
    if map_size(state.active) >= state.max_concurrent or :queue.is_empty(state.queue) do
      state
    else
      {{:value, {request, index}}, queue} = :queue.out(state.queue)

      state =
        case build_walk_state(request, state.global_timeout, index) do
          {:ok, walk_state} ->
            case send_walk_request(state.socket, walk_state) do
              {:ok, active_state} ->
                %{state | active: Map.put(state.active, active_state.request_id, active_state)}

              {:error, reason} ->
                %{state | results: Map.put(state.results, index, {:error, reason})}
            end

          {:error, reason} ->
            %{state | results: Map.put(state.results, index, {:error, reason})}
        end

      launch_walks(%{state | queue: queue})
    end
  end

  defp await_walks(state) do
    cond do
      map_size(state.results) == state.total ->
        state

      map_size(state.active) == 0 ->
        state

      true ->
        receive_timeout = receive_timeout(state.active)

        receive do
          {:snmp_response, request_id, response_data} ->
            state
            |> handle_multi_response(request_id, response_data)
            |> launch_walks()
            |> await_walks()

          {:snmp_timeout, request_id} ->
            state
            |> handle_multi_timeout(request_id)
            |> launch_walks()
            |> await_walks()
        after
          receive_timeout ->
            state
            |> expire_walks()
            |> launch_walks()
            |> await_walks()
        end
    end
  end

  defp handle_multi_response(state, request_id, response_data) do
    case Map.pop(state.active, request_id) do
      {nil, active} ->
        %{state | active: active}

      {walk_state, active} ->
        case handle_walk_response(walk_state, response_data, fn next_state ->
               {:continue, next_state}
             end) do
          {:ok, results} ->
            %{
              state
              | active: active,
                results: Map.put(state.results, walk_state.index, {:ok, results})
            }

          {:continue, next_state} ->
            case send_walk_request(state.socket, next_state) do
              {:ok, active_state} ->
                %{state | active: Map.put(active, active_state.request_id, active_state)}

              {:error, reason} ->
                %{
                  state
                  | active: active,
                    results: Map.put(state.results, walk_state.index, {:error, reason})
                }
            end

          {:error, reason} ->
            %{
              state
              | active: active,
                results: Map.put(state.results, walk_state.index, {:error, reason})
            }
        end
    end
  end

  defp handle_multi_timeout(state, request_id) do
    case Map.pop(state.active, request_id) do
      {nil, active} ->
        %{state | active: active}

      {walk_state, active} ->
        Logger.warning(
          "SNMP walk request timeout for target #{inspect(walk_state.request.target)}"
        )

        %{
          state
          | active: active,
            results: Map.put(state.results, walk_state.index, {:error, :timeout})
        }
    end
  end

  defp expire_walks(state) do
    now = now_ms()

    Enum.reduce(state.active, %{state | active: %{}}, fn {request_id, walk_state}, acc ->
      cond do
        walk_expired?(walk_state, now) ->
          EngineV2.unregister_request(EngineV2, request_id)

          Logger.warning(
            "SNMP walk exceeded walk_timeout for target #{inspect(walk_state.request.target)}"
          )

          %{acc | results: Map.put(acc.results, walk_state.index, {:error, :timeout})}

        request_expired?(walk_state, now) ->
          EngineV2.unregister_request(EngineV2, request_id)

          Logger.warning(
            "SNMP walk internal timeout for target #{inspect(walk_state.request.target)}"
          )

          %{acc | results: Map.put(acc.results, walk_state.index, {:error, :timeout})}

        true ->
          %{acc | active: Map.put(acc.active, request_id, walk_state)}
      end
    end)
  end

  defp ordered_results(state) do
    0..(state.total - 1)
    |> Enum.map(fn index -> Map.get(state.results, index, {:error, :timeout}) end)
  end

  defp receive_timeout(active) do
    now = now_ms()

    active
    |> Map.values()
    |> Enum.map(fn walk_state ->
      min(walk_state.deadline_ms - now, walk_state.request_deadline_ms - now)
    end)
    |> Enum.min(fn -> @default_timeout end)
    |> max(0)
    |> Kernel.+(50)
  end

  defp send_walk_request(socket, walk_state) do
    request_id = RequestIdGenerator.next_id()
    per_pdu_timeout = min(walk_state.timeout, remaining_walk_time(walk_state))

    if per_pdu_timeout <= 0 do
      {:error, :timeout}
    else
      EngineV2.register_request(EngineV2, request_id, self(), per_pdu_timeout)

      case build_and_send_get_bulk(socket, walk_state, request_id) do
        :ok ->
          request_started_ms = now_ms()

          {:ok,
           %{
             walk_state
             | request_id: request_id,
               request_started_ms: request_started_ms,
               request_deadline_ms: request_started_ms + per_pdu_timeout,
               request_count: walk_state.request_count + 1
           }}

        {:error, reason} ->
          EngineV2.unregister_request(EngineV2, request_id)
          {:error, reason}
      end
    end
  end

  defp build_walk_state(request, global_timeout, index) do
    timeout = request_timeout(request, global_timeout)
    walk_timeout = walk_timeout(request, global_timeout)

    case SnmpKit.SnmpMgr.Core.parse_oid(request.oid) do
      {:ok, root_oid_list} ->
        now = now_ms()

        {:ok,
         %{
           index: index,
           request: request,
           timeout: timeout,
           walk_timeout: walk_timeout,
           root_oid: root_oid_list,
           next_oid: root_oid_list,
           result_chunks_rev: [],
           adaptive_max_repetitions: Keyword.get(request.opts, :adaptive_max_repetitions, false),
           current_max_repetitions: initial_max_repetitions(request),
           min_repetitions: min_repetitions(request),
           max_repetitions_ceiling: max_repetitions_ceiling(request),
           request_count: 0,
           deadline_ms: now + walk_timeout,
           request_deadline_ms: now + timeout,
           request_started_ms: now,
           request_id: nil
         }}

      {:error, reason} ->
        {:error, {:invalid_root_oid, request.oid, reason}}
    end
  end

  defp handle_walk_response(state, [], _continue_fun), do: {:ok, finalize_results(state)}

  defp handle_walk_response(state, varbinds, continue_fun) do
    last_valid_varbind_index =
      Enum.find_index(varbinds, fn {oid, type, _value} ->
        is_end_of_mib_view?(type) or end_of_walk?(state.root_oid, oid)
      end)

    case last_valid_varbind_index do
      nil ->
        last_oid = elem(List.last(varbinds), 0)
        last_oid_list = if is_list(last_oid), do: last_oid, else: [last_oid]

        state =
          state
          |> append_chunk(varbinds)
          |> maybe_adjust_max_repetitions(length(varbinds))

        continue_fun.(%{state | next_oid: last_oid_list})

      0 ->
        {:ok, finalize_results(state)}

      index ->
        valid_varbinds = Enum.take(varbinds, index)
        {:ok, state |> append_chunk(valid_varbinds) |> finalize_results()}
    end
  end

  defp build_and_send_get_bulk(
         socket,
         %{request: request, next_oid: oid, current_max_repetitions: max_repetitions},
         request_id
       ) do
    try do
      target = resolve_target(request.target)
      community = Keyword.get(request.opts, :community, "public")
      version = Keyword.get(request.opts, :version, :v2c)
      oid_list = if is_list(oid), do: oid, else: [oid]
      pdu = PDU.build_get_bulk_request(oid_list, request_id, 0, max_repetitions)
      message = PDU.build_message(pdu, community, version)

      case PDU.encode_message(message) do
        {:ok, encoded_message} ->
          Transport.send_packet(socket, target.host, target.port, encoded_message)

        {:error, reason} ->
          Logger.error("Failed to build walk message: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error in build_and_send_get_bulk: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp remaining_walk_time(walk_state), do: max(walk_state.deadline_ms - now_ms(), 0)

  defp walk_expired?(walk_state, now), do: now >= walk_state.deadline_ms
  defp request_expired?(walk_state, now), do: now >= walk_state.request_deadline_ms

  defp end_of_walk?(root_oid_list, response_oid_list) do
    not List.starts_with?(response_oid_list, root_oid_list)
  end

  defp is_end_of_mib_view?(:end_of_mib_view), do: true
  defp is_end_of_mib_view?(_), do: false

  defp request_timeout(request, global_timeout) do
    timeout = Keyword.get(request.opts, :timeout, global_timeout)
    if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout
  end

  defp initial_max_repetitions(request) do
    request.opts
    |> Keyword.get(:max_repetitions, @default_max_repetitions)
    |> normalize_positive_int(@default_max_repetitions)
  end

  defp min_repetitions(request) do
    default_min = min(@default_min_repetitions, initial_max_repetitions(request))

    request.opts
    |> Keyword.get(:min_max_repetitions, default_min)
    |> normalize_positive_int(default_min)
    |> min(initial_max_repetitions(request))
    |> max(1)
  end

  defp max_repetitions_ceiling(request) do
    default_max =
      if Keyword.has_key?(request.opts, :max_repetitions) do
        initial_max_repetitions(request)
      else
        @default_adaptive_max_repetitions
      end

    request.opts
    |> Keyword.get(:max_max_repetitions, default_max)
    |> normalize_positive_int(default_max)
    |> max(initial_max_repetitions(request))
  end

  defp maybe_adjust_max_repetitions(
         %{adaptive_max_repetitions: true} = state,
         response_count
       ) do
    elapsed = max(now_ms() - state.request_started_ms, 0)

    fast_ms =
      Keyword.get(state.request.opts, :adaptive_fast_response_ms, @default_fast_response_ms)

    slow_ms =
      Keyword.get(state.request.opts, :adaptive_slow_response_ms, @default_slow_response_ms)

    new_size =
      cond do
        elapsed >= slow_ms and state.current_max_repetitions > state.min_repetitions ->
          max(div(state.current_max_repetitions, 2), state.min_repetitions)

        response_count >= state.current_max_repetitions and elapsed <= fast_ms and
            state.current_max_repetitions < state.max_repetitions_ceiling ->
          min(
            state.current_max_repetitions + max(div(state.current_max_repetitions, 2), 1),
            state.max_repetitions_ceiling
          )

        response_count <= div(max(state.current_max_repetitions, 2), 1) and
            state.current_max_repetitions > state.min_repetitions ->
          max(div(state.current_max_repetitions * 3, 4), state.min_repetitions)

        true ->
          state.current_max_repetitions
      end

    %{state | current_max_repetitions: max(new_size, 1)}
  end

  defp maybe_adjust_max_repetitions(state, _response_count), do: state

  defp append_chunk(state, []), do: state

  defp append_chunk(state, varbinds) do
    %{state | result_chunks_rev: [varbinds | state.result_chunks_rev]}
  end

  defp finalize_results(state) do
    state.result_chunks_rev
    |> Enum.reverse()
    |> List.flatten()
  end

  defp walk_timeout(request, global_timeout) do
    default_timeout = max(global_timeout * 10, @default_walk_timeout)

    request.opts
    |> Keyword.get(:walk_timeout, default_timeout)
    |> normalize_walk_timeout(default_timeout)
  end

  defp normalize_walk_timeout(timeout, _fallback) when is_integer(timeout) and timeout > 0 do
    min(timeout, @max_walk_timeout)
  end

  defp normalize_walk_timeout(_, fallback), do: min(fallback, @max_walk_timeout)

  defp normalize_positive_int(value, _fallback) when is_integer(value) and value > 0, do: value
  defp normalize_positive_int(_, fallback), do: fallback

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp resolve_target(target), do: SnmpKit.SnmpMgr.Target.resolve(target)
end
