defmodule SnmpKit.Telemetry do
  @moduledoc """
  `:telemetry` events emitted by SnmpKit.

  Attach with `:telemetry.attach/4` or `:telemetry.attach_many/4`, or point
  `Telemetry.Metrics` / `TelemetryMetricsPrometheus` at the event names below.
  Durations are in native time units; convert with
  `System.convert_time_unit(duration, :native, :millisecond)`.

  ## Spans

  Spans emit `:start`, `:stop` and `:exception` events with the standard
  `:telemetry.span/3` measurements (`system_time` on start, `duration` on
  stop and exception).

  | Event prefix | Emitted around | Metadata |
  |--------------|----------------|----------|
  | `[:snmpkit, :request, _]` | one single-target PDU exchange (`get`, `get_next`, `set`, `get_bulk`), retries included | `operation`, `target`, `oid`, `version`; on stop `result` (`:ok`/`:error`) and `reason` |
  | `[:snmpkit, :walk, _]` | a whole single-target walk (`walk`, `walk_table`, `bulk_walk`, `adaptive_walk`) | `operation`, `target`, `root_oid`; on stop `result`, `reason`, `count` (varbinds) |
  | `[:snmpkit, :multi, _]` | a multi-target call (`get_multi`, `get_bulk_multi`, `walk_multi`, `walk_table_multi`, `execute_mixed`) | `operation`, `request_count`; on stop `ok_count`, `error_count` |

  ## Events

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:snmpkit, :engine, :timeout]` | `%{count: 1}` | `request_id`, `target` |
  | `[:snmpkit, :trap, :received]` | `%{count: 1}` | `kind`, `version`, `trap_oid`, `trap_name`, `community`, `source` |
  | `[:snmpkit, :trap, :rejected]` | `%{count: 1}` | `reason` (`:community`, `:decode_error`, `:unsupported`), `source` |
  | `[:snmpkit, :sim, :request]` | `%{duration: native}` | `device_id`, `port`, `pdu_type`, `result` (`:ok`/`:error_injected`) |

  ## Example

      :telemetry.attach("log-slow-snmp", [:snmpkit, :request, :stop], fn _event, %{duration: d}, meta, _ ->
        ms = System.convert_time_unit(d, :native, :millisecond)
        if ms > 500, do: Logger.warning("slow SNMP \#{meta.operation} to \#{meta.target}: \#{ms} ms")
      end, nil)
  """

  @doc """
  Runs `fun` inside a `[:snmpkit, name, _]` span. The stop metadata gets
  `result`/`reason` derived from the return value, plus anything `extra.(value)`
  returns.
  """
  @spec span(atom(), map(), (-> term()), (term() -> map())) :: term()
  def span(name, metadata, fun, extra \\ fn _ -> %{} end) do
    :telemetry.span([:snmpkit, name], metadata, fn ->
      value = fun.()
      {value, metadata |> Map.merge(result_metadata(value)) |> Map.merge(extra.(value))}
    end)
  end

  @doc "Emits `[:snmpkit | event]` with the given measurements and metadata."
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements, metadata) when is_list(event) do
    :telemetry.execute([:snmpkit | event], measurements, metadata)
  end

  defp result_metadata({:ok, _}), do: %{result: :ok}
  defp result_metadata(:ok), do: %{result: :ok}
  defp result_metadata({:error, reason}), do: %{result: :error, reason: reason}
  defp result_metadata(_), do: %{result: :ok}
end
