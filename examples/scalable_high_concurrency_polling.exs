#!/usr/bin/env elixir

# Scalable High Concurrency SNMP Polling Example
# 
# This demonstrates the new MultiV2 architecture for polling thousands of devices
# efficiently without GenServer bottlenecks. Perfect for cable modem management.
#
# Key Features:
# - Direct UDP sending (no GenServer serialization)
# - Shared socket with large buffer (4MB)
# - Atomic request ID generation via ETS
# - Configurable concurrency limits
# - Comprehensive result tracking

require Logger

defmodule ScalablePollingExample do
  @moduledoc """
  Demonstrates scalable SNMP polling for thousands of cable modems.
  
  This example shows how to efficiently poll 5,000+ cable modems using
  the new MultiV2 architecture that eliminates GenServer bottlenecks.
  """

  def run() do
    IO.puts("=== Scalable High Concurrency SNMP Polling Example ===\n")
    
    # Start the new architecture components
    start_snmp_architecture()
    
    # Generate cable modem target list
    cable_modems = generate_cable_modem_targets()
    
    IO.puts("Generated #{length(cable_modems)} cable modem targets")
    IO.puts("IP range: 10.50.1.0/24 - 10.50.250.0/24")
    IO.puts("Sample targets:")
    Enum.take(cable_modems, 3)
    |> Enum.each(fn {ip, oid} -> IO.puts("  #{ip} -> #{oid}") end)
    
    # Demonstrate different polling strategies
    run_polling_examples(cable_modems)
    
    IO.puts("\n=== Example Complete ===")
  end
  
  defp start_snmp_architecture() do
    IO.puts("Starting SNMP architecture components...")
    
    # Start required components for new architecture
    {:ok, _} = SnmpKit.SnmpMgr.RequestIdGenerator.start_link()
    {:ok, _} = SnmpKit.SnmpMgr.SocketManager.start_link()
    {:ok, _} = SnmpKit.SnmpMgr.EngineV2.start_link()
    
    IO.puts("✓ RequestIdGenerator started (ETS atomic counter)")
    IO.puts("✓ SocketManager started (shared 4MB UDP socket)")
    IO.puts("✓ EngineV2 started (pure response correlator)")
    IO.puts("")
  end
  
  defp generate_cable_modem_targets() do
    IO.puts("Generating cable modem target list...")
    
    # Generate IP addresses for cable modems
    # 10.50.1.0/24 - 10.50.250.0/24 (about 5,000 devices)
    for subnet <- 1..250 do
      for host <- 1..20 do  # 20 devices per subnet = 5,000 total
        ip = "10.50.#{subnet}.#{host}"
        oid = "1.3.6.1.2.1.1.1.0"  # sysDescr - basic device info
        {ip, oid}
      end
    end
    |> List.flatten()
  end
  
  defp run_polling_examples(cable_modems) do
    # Take smaller subset for demo (adjust for your needs)
    demo_targets = Enum.take(cable_modems, 100)
    
    IO.puts("\n=== Example 1: Basic High Concurrency Polling ===")
    run_basic_polling(demo_targets)
    
    IO.puts("\n=== Example 2: Performance Benchmarking ===")
    run_performance_benchmark(demo_targets)
    
    IO.puts("\n=== Example 3: Different Return Formats ===")
    run_return_format_examples(demo_targets)
    
    IO.puts("\n=== Example 4: Error Handling & Monitoring ===")
    run_monitoring_example(demo_targets)
  end
  
  defp run_basic_polling(targets) do
    IO.puts("Polling #{length(targets)} cable modems with high concurrency...")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Use MultiV2 for high concurrency without GenServer bottleneck
    results = SnmpKit.SnmpMgr.MultiV2.get_multi(targets,
      max_concurrent: 50,    # High concurrency
      timeout: 3000,         # 3 second timeout
      return_format: :list   # Simple list format
    )
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Analyze results
success_count = Enum.count(results, fn 
      {:ok, %{oid: _, type: _, value: _}} -> true
      _ -> false
    end)
    
    IO.puts("Results:")
    IO.puts("  Duration: #{duration}ms")
    IO.puts("  Success: #{success_count}/#{length(results)}")
    IO.puts("  Throughput: #{Float.round(length(results) / (duration / 1000), 2)} requests/sec")
    IO.puts("  Success rate: #{Float.round(success_count / length(results) * 100, 1)}%")
  end
  
  defp run_performance_benchmark(targets) do
    IO.puts("Running performance benchmark...")
    
    # Test different concurrency levels
    concurrency_levels = [10, 25, 50, 100]
    
    for concurrency <- concurrency_levels do
      IO.puts("  Testing concurrency: #{concurrency}")
      
      start_time = System.monotonic_time(:millisecond)
      
      results = SnmpKit.SnmpMgr.MultiV2.get_multi(targets,
        max_concurrent: concurrency,
        timeout: 2000
      )
      
      duration = System.monotonic_time(:millisecond) - start_time
      throughput = length(results) / (duration / 1000)
      
      IO.puts("    Duration: #{duration}ms, Throughput: #{Float.round(throughput, 2)} req/sec")
    end
  end
  
  defp run_return_format_examples(targets) do
    small_targets = Enum.take(targets, 10)
    
    IO.puts("Demonstrating different return formats...")
    
    # Format 1: Simple list (default)
    IO.puts("  1. List format (default):")
    list_results = SnmpKit.SnmpMgr.MultiV2.get_multi(small_targets, 
      max_concurrent: 10,
      timeout: 1000
    )
    IO.puts("    Length: #{length(list_results)}")
    IO.puts("    Sample: #{inspect(Enum.at(list_results, 0))}")
    
    # Format 2: With targets (includes device info)
    IO.puts("  2. With targets format:")
    target_results = SnmpKit.SnmpMgr.MultiV2.get_multi(small_targets,
      max_concurrent: 10,
      timeout: 1000,
      return_format: :with_targets
    )
    IO.puts("    Length: #{length(target_results)}")
    IO.puts("    Sample: #{inspect(Enum.at(target_results, 0))}")
    
    # Format 3: Map format (device -> result)
    IO.puts("  3. Map format:")
    map_results = SnmpKit.SnmpMgr.MultiV2.get_multi(small_targets,
      max_concurrent: 10,
      timeout: 1000,
      return_format: :map
    )
    IO.puts("    Keys: #{map_size(map_results)}")
    {sample_key, sample_value} = Enum.at(map_results, 0)
    IO.puts("    Sample: #{inspect(sample_key)} -> #{inspect(sample_value)}")
  end
  
  defp run_monitoring_example(targets) do
    IO.puts("Monitoring UDP buffer and performance...")
    
    # Get initial buffer stats
    initial_stats = SnmpKit.SnmpMgr.SocketManager.get_buffer_stats()
    IO.puts("  Initial buffer size: #{div(initial_stats.buffer_size, 1024 * 1024)}MB")
    IO.puts("  Initial utilization: #{initial_stats.recv_utilization_percent}%")
    
    # Run polling with monitoring
    start_time = System.monotonic_time(:millisecond)
    
    results = SnmpKit.SnmpMgr.MultiV2.get_multi(targets,
      max_concurrent: 30,
      timeout: 2000
    )
    
    end_time = System.monotonic_time(:millisecond)
    
    # Get final buffer stats
    final_stats = SnmpKit.SnmpMgr.SocketManager.get_buffer_stats()
    
    # Show results
success_count = Enum.count(results, fn {:ok, %{oid: _, type: _, value: _}} -> true; _ -> false end)
    error_count = length(results) - success_count
    
    IO.puts("  Results: #{success_count} success, #{error_count} errors")
    IO.puts("  Duration: #{end_time - start_time}ms")
    IO.puts("  Final buffer utilization: #{final_stats.recv_utilization_percent}%")
    IO.puts("  Responses received: #{final_stats.recv_queue_length}")
    
    # Show error breakdown
    error_types = results
    |> Enum.filter(fn {:error, _} -> true; _ -> false end)
    |> Enum.map(fn {:error, reason} -> reason end)
    |> Enum.frequencies()
    
    if error_types != %{} do
      IO.puts("  Error breakdown:")
      Enum.each(error_types, fn {error, count} ->
        IO.puts("    #{error}: #{count}")
      end)
    end
  end
end

# Production-ready helper functions
defmodule CableModemPolling do
  @moduledoc """
  Production-ready functions for cable modem management.
  """
  
  @doc """
  Polls cable modems for basic health information.
  
  ## Examples
  
      cable_modems = [
        {"10.50.1.1", "1.3.6.1.2.1.1.1.0"},
        {"10.50.1.2", "1.3.6.1.2.1.1.1.0"}
      ]
      
      CableModemPolling.health_check(cable_modems, max_concurrent: 100)
  """
  def health_check(cable_modems, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 50)
    timeout = Keyword.get(opts, :timeout, 5000)
    
    Logger.info("Starting health check for #{length(cable_modems)} cable modems")
    
    start_time = System.monotonic_time(:millisecond)
    
    results = SnmpKit.SnmpMgr.MultiV2.get_multi(cable_modems,
      max_concurrent: max_concurrent,
      timeout: timeout,
      return_format: :with_targets
    )
    
    end_time = System.monotonic_time(:millisecond)
    
    # Analyze results
    {online, offline} = Enum.split_with(results, fn {_ip, _oid, result} ->
      match?({:ok, _}, result)
    end)
    
    Logger.info("Health check complete: #{length(online)} online, #{length(offline)} offline")
    Logger.info("Duration: #{end_time - start_time}ms")
    
    %{
      online: online,
      offline: offline,
      duration_ms: end_time - start_time,
      total_count: length(cable_modems)
    }
  end
  
  @doc """
  Polls cable modems for interface statistics.
  
  Demonstrates polling multiple OIDs per device efficiently.
  """
  def interface_statistics(cable_modem_ips, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 50)
    timeout = Keyword.get(opts, :timeout, 5000)
    
    # Multiple OIDs per device
    interface_oids = [
      "1.3.6.1.2.1.2.2.1.10.2",  # ifInOctets
      "1.3.6.1.2.1.2.2.1.16.2",  # ifOutOctets
      "1.3.6.1.2.1.2.2.1.14.2",  # ifInErrors
      "1.3.6.1.2.1.2.2.1.20.2"   # ifOutErrors
    ]
    
    # Create targets (IP + OID combinations)
    targets = for ip <- cable_modem_ips, oid <- interface_oids, do: {ip, oid}
    
    Logger.info("Polling interface stats for #{length(cable_modem_ips)} modems (#{length(targets)} total requests)")
    
    start_time = System.monotonic_time(:millisecond)
    
    results = SnmpKit.SnmpMgr.MultiV2.get_multi(targets,
      max_concurrent: max_concurrent,
      timeout: timeout,
      return_format: :with_targets
    )
    
    end_time = System.monotonic_time(:millisecond)
    
    # Group results by IP
    grouped_results = results
    |> Enum.group_by(fn {ip, _oid, _result} -> ip end)
    |> Enum.map(fn {ip, ip_results} ->
      stats = ip_results
      |> Enum.map(fn {_ip, oid, result} -> {oid, result} end)
      |> Map.new()
      
      {ip, stats}
    end)
    |> Map.new()
    
    Logger.info("Interface stats complete in #{end_time - start_time}ms")
    
    grouped_results
  end
end

# Run the example
ScalablePollingExample.run()