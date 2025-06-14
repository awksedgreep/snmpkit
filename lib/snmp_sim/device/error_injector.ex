defmodule SnmpSim.Device.ErrorInjector do
  @moduledoc """
  Error injection functionality for SNMP device simulation.
  Handles various error conditions like timeouts, packet loss, SNMP errors, and malformed responses.
  """

  require Logger

  @doc """
  Check if any error conditions should be applied to the PDU.
  Returns appropriate error response or :continue to proceed normally.
  """
  def check_error_conditions(pdu, state) do
    cond do
      device_failure_active?(state) ->
        {:error, :device_failure}

      check_timeout_conditions(pdu, state) ->
        {:error, :timeout}

      check_packet_loss_conditions(pdu, state) ->
        {:error, :packet_loss}

      check_snmp_error_conditions(pdu, state) ->
        {:error, :snmp_error}

      check_malformed_conditions(pdu, state) ->
        {:error, :malformed}

      true ->
        :continue
    end
  end

  @doc """
  Check if device failure condition is active.
  """
  def device_failure_active?(state) do
    case Map.get(state.error_conditions, :device_failure) do
      nil -> false
      _config -> true
    end
  end

  @doc """
  Check if timeout conditions should be applied.
  """
  def check_timeout_conditions(pdu, state) do
    case Map.get(state.error_conditions, :timeout) do
      nil ->
        false

      config ->
        if should_apply_error?(config.probability) and
             oid_matches_target?(pdu, config.target_oids) do
          Logger.debug("Device #{state.device_id} applying timeout error injection")
          true
        else
          false
        end
    end
  end

  @doc """
  Check if packet loss conditions should be applied.
  """
  def check_packet_loss_conditions(pdu, state) do
    case Map.get(state.error_conditions, :packet_loss) do
      nil ->
        false

      config ->
        if should_apply_error?(config.probability) and
             oid_matches_target?(pdu, config.target_oids) do
          Logger.debug("Device #{state.device_id} applying packet loss error injection")
          true
        else
          false
        end
    end
  end

  @doc """
  Check if SNMP error conditions should be applied.
  """
  def check_snmp_error_conditions(pdu, state) do
    case Map.get(state.error_conditions, :snmp_error) do
      nil ->
        false

      config ->
        if should_apply_error?(config.probability) and
             oid_matches_target?(pdu, config.target_oids) do
          Logger.debug("Device #{state.device_id} applying SNMP error injection")
          true
        else
          false
        end
    end
  end

  @doc """
  Check if malformed response conditions should be applied.
  """
  def check_malformed_conditions(pdu, state) do
    case Map.get(state.error_conditions, :malformed) do
      nil ->
        false

      config ->
        if should_apply_error?(config.probability) and
             oid_matches_target?(pdu, config.target_oids) do
          Logger.debug("Device #{state.device_id} applying malformed response error injection")
          true
        else
          false
        end
    end
  end

  @doc """
  Determine if error should be applied based on probability.
  """
  def should_apply_error?(probability) do
    :rand.uniform() < probability
  end

  @doc """
  Check if PDU OIDs match target OIDs for error injection.
  """
  def oid_matches_target?(pdu, target_oids) when is_list(target_oids) do
    pdu_oids =
      case Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, [])) do
        [] ->
          []

        varbinds ->
          Enum.map(varbinds, fn
            {oid, _type, _value} -> oid
            {oid, _value} -> oid
            oid when is_binary(oid) -> oid
            oid when is_list(oid) -> Enum.join(oid, ".")
          end)
      end

    Enum.any?(target_oids, fn target_oid ->
      Enum.any?(pdu_oids, &String.starts_with?(&1, target_oid))
    end)
  end

  def oid_matches_target?(_pdu, _target_oids), do: true

  @doc """
  Create a malformed response based on the error configuration.
  """
  def create_malformed_response(pdu, config) do
    case config.malformation_type do
      :invalid_oid ->
        # Create response with invalid OID format
        variable_bindings =
          case Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, [])) do
            [] ->
              [{"invalid.oid.format", :octet_string, "error"}]

            varbinds ->
              Enum.map(varbinds, fn
                {_oid, type, _value} -> {"invalid.oid.format", type, "error"}
                {_oid, _value} -> {"invalid.oid.format", "error"}
              end)
          end

        %{
          type: :get_response,
          request_id: Map.get(pdu, :request_id, 0),
          error_status: 0,
          error_index: 0,
          varbinds: variable_bindings
        }

      :wrong_type ->
        # Create response with wrong data types
        variable_bindings =
          case Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, [])) do
            [] ->
              [{"1.3.6.1.2.1.1.1.0", :integer, "should_be_string"}]

            varbinds ->
              Enum.map(varbinds, fn
                {oid, _type, _value} -> {oid, :integer, "wrong_type"}
                {oid, _value} -> {oid, "wrong_type"}
              end)
          end

        %{
          type: :get_response,
          request_id: Map.get(pdu, :request_id, 0),
          error_status: 0,
          error_index: 0,
          varbinds: variable_bindings
        }

      :truncated ->
        # Create truncated response
        %{
          type: :get_response,
          request_id: Map.get(pdu, :request_id, 0),
          error_status: 0,
          error_index: 0,
          varbinds: []
        }

      _ ->
        # Default malformed response
        %{
          type: :get_response,
          request_id: Map.get(pdu, :request_id, 0),
          # genErr
          error_status: 5,
          error_index: 1,
          varbinds: []
        }
    end
  end
end
