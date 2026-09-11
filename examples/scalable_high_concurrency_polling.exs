#!/usr/bin/env elixir

# Scalable High Concurrency SNMP Polling Example
#
# Polls a population of simulated cable modems through the shared-socket
# engine behind SnmpKit's multi-target calls. Self-contained: the modems are
# started by the script (100 devices on ports 30000-30099).
#
# What the engine does:
# - one UDP socket with a large receive buffer, shared by every request
# - request ids from an ETS counter, responses correlated back to callers
# - no process per request; max_concurrent bounds the requests in flight
#
# Run from a checkout:   mix run examples/scalable_high_concurrency_polling.exs
# Standalone:            elixir examples/scalable_high_concurrency_polling.exs

unless Code.ensure_loaded?(SnmpKit), do: Mix.install([{:snmpkit, "~> 2.0"}])

require Logger

defmodule ScalablePollingExample do
  @moduledoc """
  Polls a simulated cable modem population with `SnmpKit.SnmpMgr.Multi`.
  """

  @device_count 100
  @port_range 30_000..30_099

  def run() do
    IO.puts("=== Scalable High Concurrency SNMP Polling Example ===\n")

    # The request-id generator and the engine start on demand with the first
    # multi-target call; ensure_started/0 only makes that explicit here.
    :ok = SnmpKit.SnmpMgr.ensure_started()
    IO.puts("Engine started (shared UDP socket + response correlator)")

    targets = start_cable_modems()

    IO.puts("Started #{length(targets)} simulated cable modems")
    IO.puts("Sample targets:")

    targets
    |> Enum.take(3)
    |> Enum.each(fn {ip, oid} -> IO.puts("  #{ip} -> #{oid}") end)

    run_basic_polling(targets)
    run_performance_benchmark(targets)
    run_return_format_examples(targets)
    run_monitoring_example(targets)

    IO.puts("\n=== Example Complete ===")
  end

  defp start_cable_modems() do
    walk = SnmpKit.SnmpSim.ProfileLoader.bundled_walk(:cable_modem)

    {:ok, devices} =
      SnmpKit.Sim.start_device_population(
        [{:cable_modem, {:walk_file, walk}, count: @device_count}],
        port_range: @port_range
      )

    for %{target: target} <- devices, do: {target, "sysDescr.0"}
  end

  defp run_basic_polling(targets) do
    IO.puts("\n=== Example 1: Basic High Concurrency Polling ===")
    IO.puts("Polling #{length(targets)} cable modems...")

    {duration, results} =
      :timer.tc(
        fn ->
          SnmpKit.SnmpMgr.Multi.get_multi(targets,
            max_concurrent: 50,
            timeout: 3_000,
            return_format: :list
          )
        end,
        :millisecond
      )

    success_count = Enum.count(results, &match?({:ok, [%{value: _} | _]}, &1))

    IO.puts("Results:")
    IO.puts("  Duration: #{duration}ms")
    IO.puts("  Success: #{success_count}/#{length(results)}")
    IO.puts("  Throughput: #{throughput(length(results), duration)} requests/sec")
  end

  defp run_performance_benchmark(targets) do
    IO.puts("\n=== Example 2: Concurrency Levels ===")

    for concurrency <- [10, 25, 50, 100] do
      {duration, results} =
        :timer.tc(
          fn -> SnmpKit.SnmpMgr.Multi.get_multi(targets, max_concurrent: concurrency, timeout: 2_000) end,
          :millisecond
        )

      IO.puts(
        "  max_concurrent: #{concurrency}  duration: #{duration}ms  " <>
          "throughput: #{throughput(length(results), duration)} req/sec"
      )
    end
  end

  defp run_return_format_examples(targets) do
    IO.puts("\n=== Example 3: Return Formats ===")
    small_targets = Enum.take(targets, 10)

    IO.puts("  1. :list (default) - results in request order:")
    list_results = SnmpKit.SnmpMgr.Multi.get_multi(small_targets, max_concurrent: 10)
    IO.puts("     #{inspect(Enum.at(list_results, 0), printable_limit: 40)}")

    IO.puts("  2. :with_targets - {target, oid, result}:")

    target_results =
      SnmpKit.SnmpMgr.Multi.get_multi(small_targets, max_concurrent: 10, return_format: :with_targets)

    IO.puts("     #{inspect(Enum.at(target_results, 0), printable_limit: 40)}")

    IO.puts("  3. :map - %{{target, oid} => result}:")
    map_results = SnmpKit.SnmpMgr.Multi.get_multi(small_targets, max_concurrent: 10, return_format: :map)
    {sample_key, sample_value} = Enum.at(map_results, 0)
    IO.puts("     #{inspect(sample_key)} => #{inspect(sample_value, printable_limit: 40)}")
  end

  defp run_monitoring_example(targets) do
    IO.puts("\n=== Example 4: Errors and Engine Stats ===")

    # Mix in targets that will not answer
    dead = for port <- 1..5, do: {"127.0.0.1:#{port}", "sysDescr.0"}
    mixed = targets ++ dead

    results = SnmpKit.SnmpMgr.Multi.get_multi(mixed, max_concurrent: 30, timeout: 500, retries: 0)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    IO.puts("  Results: #{success_count} success, #{length(results) - success_count} errors")

    error_types =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, reason} -> reason end)
      |> Enum.frequencies()

    for {error, count} <- error_types, do: IO.puts("    #{inspect(error)}: #{count}")

    stats = SnmpKit.SnmpMgr.Engine.get_buffer_stats()
    IO.puts("  Engine socket buffer: #{div(stats.buffer_size, 1024 * 1024)}MB")
    IO.puts("  Receive queue: #{stats.recv_queue_length} bytes")
  end

  defp throughput(_count, 0), do: "n/a"
  defp throughput(count, duration_ms), do: Float.round(count / (duration_ms / 1000), 2)
end

# Helpers of the kind a production poller would keep
defmodule CableModemPolling do
  @moduledoc """
  Functions for cable modem fleets.
  """

  @doc """
  Polls cable modems for basic health information.

      cable_modems = [{"10.50.1.1", "sysDescr.0"}, {"10.50.1.2", "sysDescr.0"}]
      CableModemPolling.health_check(cable_modems, max_concurrent: 100)
  """
  def health_check(cable_modems, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 50)
    timeout = Keyword.get(opts, :timeout, 5_000)

    start_time = System.monotonic_time(:millisecond)

    results =
      SnmpKit.SnmpMgr.Multi.get_multi(cable_modems,
        max_concurrent: max_concurrent,
        timeout: timeout,
        return_format: :with_targets
      )

    duration = System.monotonic_time(:millisecond) - start_time

    {online, offline} =
      Enum.split_with(results, fn {_ip, _oid, result} -> match?({:ok, _}, result) end)

    Logger.info("Health check: #{length(online)} online, #{length(offline)} offline in #{duration}ms")

    %{online: online, offline: offline, duration_ms: duration, total_count: length(cable_modems)}
  end

  @doc """
  Polls several interface counters per modem in one call.
  """
  def interface_statistics(cable_modem_ips, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 50)
    timeout = Keyword.get(opts, :timeout, 5_000)

    interface_oids = ["ifInOctets.2", "ifOutOctets.2", "ifInErrors.2", "ifOutErrors.2"]
    targets = for ip <- cable_modem_ips, oid <- interface_oids, do: {ip, oid}

    results =
      SnmpKit.SnmpMgr.Multi.get_multi(targets,
        max_concurrent: max_concurrent,
        timeout: timeout,
        return_format: :with_targets
      )

    results
    |> Enum.group_by(fn {ip, _oid, _result} -> ip end)
    |> Map.new(fn {ip, ip_results} ->
      {ip, Map.new(ip_results, fn {_ip, oid, result} -> {oid, result} end)}
    end)
  end
end

ScalablePollingExample.run()
