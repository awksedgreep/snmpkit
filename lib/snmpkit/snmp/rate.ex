defmodule SnmpKit.SNMP.Rate do
  @moduledoc """
  Deltas and per-second rates from successive SNMP samples, with Counter32
  and Counter64 wraparound handled.

  Works on the enriched varbind maps every `SnmpKit.SNMP` call returns, on
  `{type, value}` tuples, or on bare integers with an explicit type.

      # two polls of the same object
      {:ok, %{value: 4_294_967_000, type: :counter32} = t0} = SnmpKit.SNMP.get(host, "ifInOctets.1")
      # ... 10 seconds later, the counter wrapped ...
      {:ok, %{value: 1_000} = t1} = SnmpKit.SNMP.get(host, "ifInOctets.1")

      SnmpKit.SNMP.Rate.delta(t0, t1)          #=> {:ok, 1296}
      SnmpKit.SNMP.Rate.rate(t0, t1, 10_000)   #=> {:ok, 129.6}  (per second)

  Whole walks are paired by OID with `rates/3`, which reads the interval
  from the `sysUpTime.0` varbinds when both samples carry them and reports a
  device restart instead of inventing rates from reset counters.

  ## Restarts versus wraps

  A Counter32 that wrapped and a counter that reset on reboot look the same
  from one object alone. `delta/2` assumes a wrap, which is right for a
  busy 32-bit counter. `rates/3` compares `sysUpTime.0` when present and
  returns `{:error, :device_restarted}` if it went backwards; pass
  `sysUpTime.0` along with the objects you poll to get that protection.
  """

  @counter32_max 4_294_967_295
  @counter64_max 18_446_744_073_709_551_615
  @sys_uptime_oid "1.3.6.1.2.1.1.3.0"

  @type sample :: map() | {atom(), integer()} | integer()

  @doc """
  The increase from `previous` to `current`, wrap-corrected for
  `:counter32` and `:counter64`. Other numeric types return the plain
  difference (gauges can go down).

      iex> SnmpKit.SNMP.Rate.delta({:counter32, 4_294_967_000}, {:counter32, 1_000})
      {:ok, 1296}

      iex> SnmpKit.SNMP.Rate.delta(%{type: :gauge32, value: 50}, %{type: :gauge32, value: 20})
      {:ok, -30}

      iex> SnmpKit.SNMP.Rate.delta({:counter32, 1}, {:counter64, 2})
      {:error, :type_mismatch}
  """
  @spec delta(sample(), sample(), keyword()) :: {:ok, integer()} | {:error, term()}
  def delta(previous, current, opts \\ []) do
    with {:ok, {type, prev}} <- normalize(previous, opts),
         {:ok, {type2, curr}} <- normalize(current, opts),
         :ok <- same_type(type, type2) do
      {:ok, do_delta(type, prev, curr)}
    end
  end

  @doc """
  Per-second rate between two samples taken `interval_ms` apart.

      iex> SnmpKit.SNMP.Rate.rate({:counter32, 100}, {:counter32, 1_100}, 10_000)
      {:ok, 100.0}
  """
  @spec rate(sample(), sample(), pos_integer(), keyword()) :: {:ok, float()} | {:error, term()}
  def rate(previous, current, interval_ms, opts \\ [])

  def rate(_previous, _current, interval_ms, _opts)
      when not is_integer(interval_ms) or interval_ms <= 0,
      do: {:error, :invalid_interval}

  def rate(previous, current, interval_ms, opts) do
    with {:ok, d} <- delta(previous, current, opts) do
      {:ok, d * 1000 / interval_ms}
    end
  end

  @doc """
  Pairs two lists of enriched varbinds (walk or get results) by OID and
  returns a delta and rate for every counter or gauge present in both.

  The interval comes from `interval_ms:` or, failing that, from the
  `sysUpTime.0` varbinds in both samples. Each result is

      %{oid: "1.3.6.1.2.1.2.2.1.10.1", name: "ifInOctets.1", type: :counter32,
        previous: 100, current: 1100, delta: 1000, rate: 100.0}

  Returns `{:error, :device_restarted}` when `sysUpTime.0` went backwards,
  `{:error, :no_interval}` when no interval can be determined.
  """
  @spec rates([map()], [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def rates(previous, current, opts \\ []) when is_list(previous) and is_list(current) do
    prev_by_oid = Map.new(previous, &{oid_key(&1), &1})
    curr_by_oid = Map.new(current, &{oid_key(&1), &1})

    with {:ok, interval_ms} <- interval(prev_by_oid, curr_by_oid, opts) do
      results =
        current
        |> Enum.filter(&rateable?/1)
        |> Enum.flat_map(fn curr ->
          case Map.get(prev_by_oid, oid_key(curr)) do
            nil ->
              []

            prev ->
              case delta(prev, curr) do
                {:ok, d} ->
                  [
                    %{
                      oid: oid_key(curr),
                      name: Map.get(curr, :name),
                      type: curr.type,
                      previous: prev.value,
                      current: curr.value,
                      delta: d,
                      rate: d * 1000 / interval_ms
                    }
                  ]

                {:error, _} ->
                  []
              end
          end
        end)

      {:ok, results}
    end
  end

  @doc """
  Milliseconds elapsed between two `sysUpTime` readings (TimeTicks, i.e.
  centiseconds), or `{:error, :device_restarted}` when the second is lower.

      iex> SnmpKit.SNMP.Rate.interval_from_uptime(1_000, 2_500)
      {:ok, 15_000}
  """
  @spec interval_from_uptime(non_neg_integer(), non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, :device_restarted | :no_interval}
  def interval_from_uptime(previous_ticks, current_ticks)
      when is_integer(previous_ticks) and is_integer(current_ticks) do
    cond do
      current_ticks < previous_ticks -> {:error, :device_restarted}
      current_ticks == previous_ticks -> {:error, :no_interval}
      true -> {:ok, (current_ticks - previous_ticks) * 10}
    end
  end

  def interval_from_uptime(_, _), do: {:error, :no_interval}

  ## helpers

  defp interval(prev_by_oid, curr_by_oid, opts) do
    case Keyword.get(opts, :interval_ms) do
      ms when is_integer(ms) and ms > 0 ->
        {:ok, ms}

      _ ->
        with %{value: prev} <- Map.get(prev_by_oid, @sys_uptime_oid, :none),
             %{value: curr} <- Map.get(curr_by_oid, @sys_uptime_oid, :none) do
          interval_from_uptime(prev, curr)
        else
          _ -> {:error, :no_interval}
        end
    end
  end

  defp rateable?(%{type: type, value: value}) when is_integer(value),
    do: type in [:counter32, :counter64, :gauge32, :integer, :unsigned32]

  defp rateable?(_), do: false

  defp oid_key(%{oid: oid}) when is_binary(oid), do: oid
  defp oid_key(%{oid_list: list}) when is_list(list), do: Enum.join(list, ".")
  defp oid_key(%{oid: list}) when is_list(list), do: Enum.join(list, ".")
  defp oid_key(_), do: nil

  defp normalize(%{type: type, value: value}, _opts) when is_integer(value),
    do: {:ok, {type, value}}

  defp normalize({type, value}, _opts) when is_atom(type) and is_integer(value),
    do: {:ok, {type, value}}

  defp normalize(value, opts) when is_integer(value) do
    case Keyword.get(opts, :type) do
      nil -> {:error, :type_required}
      type -> {:ok, {type, value}}
    end
  end

  defp normalize(other, _opts), do: {:error, {:not_a_sample, other}}

  defp same_type(type, type), do: :ok
  defp same_type(_, _), do: {:error, :type_mismatch}

  defp do_delta(:counter32, prev, curr) when curr < prev, do: @counter32_max - prev + curr + 1
  defp do_delta(:counter64, prev, curr) when curr < prev, do: @counter64_max - prev + curr + 1
  defp do_delta(_type, prev, curr), do: curr - prev
end
