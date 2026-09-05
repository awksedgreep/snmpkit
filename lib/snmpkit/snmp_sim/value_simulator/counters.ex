defmodule SnmpKit.SnmpSim.ValueSimulator.Counters do
  @moduledoc """
  Counter32/Counter64 wrap arithmetic (exact modulo 2^32 / 2^64), wrap prediction, device-specific wrap behaviour and discontinuity handling.
  """

  def apply_counter_wrapping(value, type) do
    case String.downcase(type) do
      "counter32" ->
        handle_counter32_wrapping(value)

      "counter64" ->
        handle_counter64_wrapping(value)

      _ ->
        value
    end
  end

  defp handle_counter32_wrapping(value) do
    # 32-bit counter: 0 to 4,294,967,295 (2^32 - 1)
    max_value = 4_294_967_296

    cond do
      value < 0 ->
        # Handle negative values (shouldn't happen but be defensive)
        0

      value >= max_value ->
        # Counter32 wraps modulo 2^32 exactly (RFC 2578 7.1.6); no jitter
        rem(value, max_value)

      true ->
        value
    end
  end

  defp handle_counter64_wrapping(value) do
    # 64-bit counter: 0 to 18,446,744,073,709,551,615 (2^64 - 1)
    max_value = 18_446_744_073_709_551_616

    cond do
      value < 0 ->
        0

      value >= max_value ->
        # Counter64 wraps modulo 2^64 exactly (RFC 2578 7.1.10); no jitter
        rem(value, max_value)

      true ->
        value
    end
  end

  @doc """
  Check if a counter value is approaching its maximum and likely to wrap soon.
  Used to predict and prepare for counter wrap events.
  """
  def counter_approaching_wrap?(value, type, threshold_percent \\ 0.95) do
    max_value =
      case String.downcase(type) do
        "counter32" -> 4_294_967_296
        "counter64" -> 18_446_744_073_709_551_616
        _ -> nil
      end

    if max_value do
      value / max_value >= threshold_percent
    else
      false
    end
  end

  @doc """
  Calculate the time until counter wrap based on current increment rate.
  Returns estimated seconds until wrap occurs.
  """
  def time_until_counter_wrap(current_value, increment_rate, type) do
    max_value =
      case String.downcase(type) do
        "counter32" -> 4_294_967_296
        "counter64" -> 18_446_744_073_709_551_616
        _ -> :infinity
      end

    if increment_rate > 0 do
      remaining_value = max_value - current_value
      trunc(remaining_value / increment_rate)
    else
      :infinity
    end
  end

  @doc """
  Simulate realistic counter wrap behavior with device-specific patterns.
  Different device types may handle wrap differently.
  """
  def apply_device_specific_counter_behavior(value, type, device_type, config \\ %{}) do
    wrapped_value = apply_counter_wrapping(value, type)

    # Apply device-specific behavior after wrapping
    case device_type do
      :cable_modem ->
        # Cable modems may have slight delays after wrap
        apply_cable_modem_wrap_behavior(wrapped_value, type, config)

      :cmts ->
        # CMTS devices handle high-rate counters with better precision
        apply_cmts_wrap_behavior(wrapped_value, type, config)

      :switch ->
        # Network switches may have buffering effects
        apply_switch_wrap_behavior(wrapped_value, type, config)

      :router ->
        # Routers may reset related counters on wrap
        apply_router_wrap_behavior(wrapped_value, type, config)

      _ ->
        wrapped_value
    end
  end

  # Counters are defined to wrap exactly; adding "post-wrap jitter" would make
  # a Counter32/Counter64 step backwards, which no compliant manager expects.
  # The :post_wrap_jitter option is accepted for compatibility and ignored.
  defp apply_cable_modem_wrap_behavior(value, _type, _config), do: value

  defp apply_cmts_wrap_behavior(value, _type, config) do
    # CMTS devices typically handle wrapping more precisely
    # May sync counter wraps across interfaces
    if Map.get(config, :synchronized_wrap, false) do
      # Round to nearest synchronization boundary
      sync_boundary = Map.get(config, :sync_boundary, 1000)
      rounded_value = div(value, sync_boundary) * sync_boundary
      rounded_value
    else
      value
    end
  end

  defp apply_switch_wrap_behavior(value, type, config) do
    # Switches may buffer counter updates, causing delayed wrap appearance
    # 2% delay
    buffer_delay = Map.get(config, :buffer_delay_percent, 0.02)

    if :rand.uniform() < buffer_delay do
      # Simulate buffered counter that hasn't updated yet
      # Return a value slightly before wrap
      case type do
        "counter32" -> max(0, 4_294_967_295 - trunc(:rand.uniform() * 1000))
        "counter64" -> max(0, 18_446_744_073_709_551_615 - trunc(:rand.uniform() * 1000))
        _ -> value
      end
    else
      value
    end
  end

  defp apply_router_wrap_behavior(value, _type, config) do
    # Routers may reset related counters when primary counters wrap
    reset_related = Map.get(config, :reset_related_counters, false)

    # Just wrapped (small value)
    if reset_related and value < 1000 do
      # Simulate related counter resets by adding some randomness
      reset_jitter = trunc(:rand.uniform() * 100)
      value + reset_jitter
    else
      value
    end
  end

  @doc """
  Generate counter discontinuity events that occur during counter wraps.
  Some devices increment discontinuity counters when main counters wrap.
  """
  def handle_counter_discontinuity(old_value, new_value, discontinuity_counter) do
    # Detect if a wrap occurred (new value much smaller than old value)
    # If new value is 1M+ less than old, likely wrapped
    wrap_threshold = 1_000_000

    if old_value - new_value > wrap_threshold do
      # Counter wrapped, increment discontinuity counter
      discontinuity_counter + 1
    else
      discontinuity_counter
    end
  end
end
