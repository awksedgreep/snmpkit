defmodule SnmpKit.SnmpMgr.V2Walk do
  @moduledoc """
  Handles the logic for performing an SNMP walk for a single target.

  This module is designed to be called from a concurrent execution environment
  like `Task.async_stream`. It manages the state of an individual walk,
  iteratively sending GetBulk requests until the walk is complete or an
  error occurs.
  """

  require Logger

  alias SnmpKit.SnmpMgr.{EngineV2, RequestIdGenerator, SocketManager}
  alias SnmpKit.SnmpLib.{OID, PDU, Transport}

  @doc """
  Performs a full SNMP walk for a given target and root OID.

  This function performs a synchronous, iterative walk within the calling process.
  It repeatedly sends GetBulk requests until the end of the MIB subtree is
  reached, blocking until the walk is complete or an error occurs.

  ## Parameters
  - `request` - A map containing request details (target, oid, opts, etc.).
  - `timeout` - The timeout in milliseconds for each individual SNMP request.

  ## Returns
  - `{:ok, results}` - A list of `{oid, type, value}` tuples.
  - `{:error, reason}` - An error tuple if the walk fails.
  """
  def walk(request, timeout) do
    case OID.string_to_list(request.oid) do
      {:ok, root_oid_list} ->
        initial_state = %{
          request: request,
          timeout: timeout,
          root_oid: root_oid_list,
          next_oid: root_oid_list,
          results: []
        }

        walk_loop(initial_state)

      {:error, reason} ->
        {:error, {:invalid_root_oid, request.oid, reason}}
    end
  end

  # The main walk loop, implemented as a tail-recursive function.
  defp walk_loop(state) do
    request_id = RequestIdGenerator.next_id()
    socket = SocketManager.get_socket()

    EngineV2.register_request(EngineV2, request_id, self(), state.timeout)

    case build_and_send_get_bulk(socket, state, request_id) do
      :ok ->
        # Block and wait for the response for this single request.
        receive do
          {:snmp_response, ^request_id, response_data} ->
            handle_response(state, response_data)

          {:snmp_timeout, ^request_id} ->
            Logger.warning(
              "SNMP walk request timeout for target #{inspect(state.request.target)}"
            )

            {:error, :timeout}
        after
          state.timeout ->
            EngineV2.unregister_request(EngineV2, request_id)

            Logger.warning(
              "SNMP walk internal timeout for target #{inspect(state.request.target)}"
            )

            {:error, :timeout}
        end

      {:error, reason} ->
        EngineV2.unregister_request(EngineV2, request_id)
        {:error, reason}
    end
  end

  defp build_and_send_get_bulk(socket, %{request: request, next_oid: oid}, request_id) do
    try do
      target = resolve_target(request.target)
      community = Keyword.get(request.opts, :community, "public")
      version = Keyword.get(request.opts, :version, :v2c)
      max_repetitions = Keyword.get(request.opts, :max_repetitions, 30)

      # Ensure oid is in list format for PDU building
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

  defp handle_response(state, []) do
    {:ok, state.results}
  end

  defp handle_response(state, varbinds) do
    # GETBULK returns a list of varbinds. We process them until we go
    # past the root OID or hit the end of the MIB.
    last_valid_varbind_index =
      Enum.find_index(varbinds, fn {oid, type, _value} ->
        is_end_of_mib_view?(type) or end_of_walk?(state.root_oid, oid)
      end)

    case last_valid_varbind_index do
      nil ->
        # All varbinds are valid. Continue the walk from the last OID.
        new_results = state.results ++ varbinds
        last_oid = elem(List.last(varbinds), 0)
        # Ensure last_oid is in list format for next iteration
        last_oid_list = if is_list(last_oid), do: last_oid, else: [last_oid]
        new_state = %{state | results: new_results, next_oid: last_oid_list}
        walk_loop(new_state)

      0 ->
        # The very first varbind is outside our scope, so the walk is complete.
        {:ok, state.results}

      index ->
        # The walk is complete. Take the valid varbinds up to the index.
        valid_varbinds = Enum.take(varbinds, index)
        new_results = state.results ++ valid_varbinds
        {:ok, new_results}
    end
  end

  # Check if the response OID is still within the root OID's subtree.
  defp end_of_walk?(root_oid_list, response_oid_list) do
    not List.starts_with?(response_oid_list, root_oid_list)
  end

  # Check if the varbind type indicates the end of the MIB view.
  defp is_end_of_mib_view?(:end_of_mib_view), do: true
  defp is_end_of_mib_view?(_), do: false

  # --- Helper functions ---

  defp resolve_target(target) when is_binary(target) do
    case SnmpKit.SnmpMgr.Target.parse(target) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{host: target, port: 161}
    end
  end

  defp resolve_target(target), do: target
end
