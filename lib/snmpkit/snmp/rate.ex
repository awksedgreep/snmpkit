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

  `sysUpTime` is itself a 32-bit TimeTicks value and wraps after about 497
  days. A wrap looks exactly like a restart, so `rates/3` reports
  `{:error, :device_restarted}` for it too. When a poll may span that
  boundary pass `interval_ms:` from your own clock; it always takes priority
  over the uptime varbinds.

  ## Multiple wraps

  A counter that wrapped more than once between two samples cannot be told
  from one that wrapped once, so its delta is under-reported. Poll fast
  enough that no counter can wrap twice (a 32-bit octet counter wraps in
  under 35 seconds at 1 Gbps), or give `max_rate:`, the highest per-second
  rate the object can plausibly show, and a rate that only a multiple wrap
  explains becomes `{:error, :implausible_rate}`.

  ## Options

    * `:type` - the SNMP type of bare numeric samples.
    * `:max_rate` - per-second bound; a rate whose magnitude exceeds it is
      reported as `:implausible_rate`.
    * `:interval_ms` (`rates/3`) - elapsed time between the two samples,
      takes priority over `sysUpTime.0`.
    * `:unrateable` (`rates/3`) - `:skip` (default) leaves out entries that
      could not be rated; `:error` returns `{:error, {:unrateable, oid, reason}}`
      for the first one.

  ## Sample values

  Integer values are what the decoder produces. Hand-built samples may
  carry floats for `:gauge32`, `:integer` and `:unsigned32`; a counter is an
  integer by definition, so a float counter is `{:error, {:not_a_sample, _}}`.
  """

  @counter32_max 4_294_967_295
  @counter64_max 18_446_744_073_709_551_615
  @sys_uptime_oid "1.3.6.1.2.1.1.3.0"
  @rateable_types [:counter32, :counter64, :gauge32, :integer, :unsigned32]
  @float_types [:gauge32, :integer, :unsigned32]

  @type sample :: map() | {atom(), number()} | number()

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
  @spec delta(sample(), sample(), keyword()) :: {:ok, number()} | {:error, term()}
  def delta(previous, current, opts \\ []) do
    with {:ok, {type, prev}} <- normalize(previous, opts),
         {:ok, {type2, curr}} <- normalize(current, opts),
         :ok <- same_type(type, type2) do
      {:ok, do_delta(type, prev, curr)}
    end
  end

  @doc """
  Per-second rate between two samples taken `interval_ms` apart. With
  `max_rate:` a rate whose magnitude exceeds the bound is
  `{:error, :implausible_rate}`.

      iex> SnmpKit.SNMP.Rate.rate({:counter32, 100}, {:counter32, 1_100}, 10_000)
      {:ok, 100.0}

      iex> SnmpKit.SNMP.Rate.rate({:counter32, 100}, {:counter32, 50}, 1_000, max_rate: 1.0e9)
      {:error, :implausible_rate}
  """
  @spec rate(sample(), sample(), pos_integer(), keyword()) :: {:ok, float()} | {:error, term()}
  def rate(previous, current, interval_ms, opts \\ [])

  def rate(_previous, _current, interval_ms, _opts)
      when not is_integer(interval_ms) or interval_ms <= 0,
      do: {:error, :invalid_interval}

  def rate(previous, current, interval_ms, opts) do
    with {:ok, d} <- delta(previous, current, opts) do
      bounded_rate(d * 1000 / interval_ms, opts)
    end
  end

  @doc """
  Pairs two lists of enriched varbinds (walk or get results) by OID and
  returns a delta and rate for every counter or gauge present in both.

  The interval comes from `interval_ms:` or, failing that, from the
  `sysUpTime.0` varbinds in both samples. Each result is

      %{oid: "1.3.6.1.2.1.2.2.1.10.1", name: "ifInOctets.1", type: :counter32,
        previous: 100, current: 1100, delta: 1000, rate: 100.0}

  Returns `{:error, :device_restarted}` when `sysUpTime.0` went backwards
  (or wrapped, see the module docs), `{:error, :no_interval}` when no
  interval can be determined.

  Only values whose type can carry a rate are candidates: strings, OIDs,
  addresses and TimeTicks are always left out. A candidate that could not be
  rated (no previous sample, a type that changed between samples, a
  non-numeric value, or a rate above `max_rate:`) is left out by default and
  reported as `{:error, {:unrateable, oid, reason}}` with `unrateable: :error`.
  """
  @spec rates([map()], [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def rates(previous, current, opts \\ []) when is_list(previous) and is_list(current) do
    prev_by_oid = Map.new(previous, &{oid_key(&1), &1})
    curr_by_oid = Map.new(current, &{oid_key(&1), &1})
    on_unrateable = Keyword.get(opts, :unrateable, :skip)

    with {:ok, interval_ms} <- interval(prev_by_oid, curr_by_oid, opts) do
      current
      |> Enum.filter(&rate_candidate?/1)
      |> Enum.reduce_while({:ok, []}, fn curr, {:ok, acc} ->
        oid = oid_key(curr)

        case rate_entry(Map.get(prev_by_oid, oid), curr, interval_ms, opts) do
          {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
          {:error, _reason} when on_unrateable == :skip -> {:cont, {:ok, acc}}
          {:error, reason} -> {:halt, {:error, {:unrateable, oid, reason}}}
        end
      end)
      |> case do
        {:ok, entries} -> {:ok, Enum.reverse(entries)}
        error -> error
      end
    end
  end

  @doc """
  Milliseconds elapsed between two `sysUpTime` readings (TimeTicks, i.e.
  centiseconds), or `{:error, :device_restarted}` when the second is lower.

  TimeTicks wrap after 2^32 centiseconds (about 497 days). A wrap is
  indistinguishable from a restart here and is reported the same way;
  callers whose polls may span that boundary should pass `interval_ms:` to
  `rates/3` instead.

      iex> SnmpKit.SNMP.Rate.interval_from_uptime(1_000, 2_500)
      {:ok, 15_000}

      iex> SnmpKit.SNMP.Rate.interval_from_uptime(4_294_967_195, 5)
      {:error, :device_restarted}
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

  defp rate_entry(nil, _curr, _interval_ms, _opts), do: {:error, :no_previous_sample}

  defp rate_entry(prev, curr, interval_ms, opts) do
    with {:ok, d} <- delta(prev, curr, opts),
         {:ok, rate} <- bounded_rate(d * 1000 / interval_ms, opts) do
      {:ok,
       %{
         oid: oid_key(curr),
         name: Map.get(curr, :name),
         type: curr.type,
         previous: prev.value,
         current: curr.value,
         delta: d,
         rate: rate
       }}
    end
  end

  defp bounded_rate(rate, opts) do
    case Keyword.get(opts, :max_rate) do
      max when is_number(max) and abs(rate) > max -> {:error, :implausible_rate}
      _ -> {:ok, rate}
    end
  end

  # Only counters and gauges can carry a rate; strings, OIDs, addresses and
  # TimeTicks are never candidates, whatever `:unrateable` says.
  defp rate_candidate?(%{type: type}), do: type in @rateable_types
  defp rate_candidate?(_), do: false

  defp oid_key(%{oid: oid}) when is_binary(oid), do: oid
  defp oid_key(%{oid_list: list}) when is_list(list), do: Enum.join(list, ".")
  defp oid_key(%{oid: list}) when is_list(list), do: Enum.join(list, ".")
  defp oid_key(_), do: nil

  defp normalize(%{type: type, value: value}, _opts) when is_number(value),
    do: typed(type, value)

  defp normalize({type, value}, _opts) when is_atom(type) and is_number(value),
    do: typed(type, value)

  defp normalize(value, opts) when is_number(value) do
    case Keyword.get(opts, :type) do
      nil -> {:error, :type_required}
      type -> typed(type, value)
    end
  end

  defp normalize(other, _opts), do: {:error, {:not_a_sample, other}}

  defp typed(type, value) when is_integer(value), do: {:ok, {type, value}}
  defp typed(type, value) when type in @float_types, do: {:ok, {type, value}}
  defp typed(type, value), do: {:error, {:not_a_sample, {type, value}}}

  defp same_type(type, type), do: :ok
  defp same_type(_, _), do: {:error, :type_mismatch}

  defp do_delta(:counter32, prev, curr) when curr < prev, do: @counter32_max - prev + curr + 1
  defp do_delta(:counter64, prev, curr) when curr < prev, do: @counter64_max - prev + curr + 1
  defp do_delta(_type, prev, curr), do: curr - prev
end
