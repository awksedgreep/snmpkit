#!/usr/bin/env elixir

# Multi Return Format Demo
#
# This example demonstrates the new return_format options available in
# SnmpKit.SnmpMgr.Multi functions, showing how to get better host-to-result
# association for multi-target SNMP operations.

Mix.install([{:snmpkit, path: "."}])

defmodule MultiReturnFormatDemo do
  @moduledoc """
  Demonstrates the three different return formats available for multi-target SNMP operations:
  - :list (default) - Simple list of results in same order as input
  - :with_targets - List of {target, oid, result} tuples
  - :map - Map with {target, oid} keys and result values
  """

  def run do
    IO.puts """

    🚀 SnmpKit Multi Return Format Demo
    ===================================

    This demo shows the new return_format option that helps users associate
    SNMP results with their corresponding hosts and OIDs.
    """

    demo_get_multi()
    demo_bulk_multi()
    demo_practical_usage()
  end

  defp demo_get_multi do
    IO.puts """

    📡 GET Multi Operations
    =======================
    """

    # Sample requests - using invalid hosts to ensure consistent results
    requests = [
      {"device1.example.com", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
      {"device2.example.com", "1.3.6.1.2.1.1.3.0", [timeout: 100]},
      {"device3.example.com", "1.3.6.1.2.1.1.5.0", [timeout: 100]}
    ]

    IO.puts "Sample requests:"
    Enum.each(requests, fn {host, oid, _opts} ->
      IO.puts "  • #{host} → #{oid}"
    end)

    # Demonstrate default list format
    IO.puts "\n1. Default :list format:"
    list_results = SnmpKit.SnmpMgr.get_multi(requests)
    IO.puts "   Results: #{inspect(list_results, limit: 1)}"
    IO.puts "   ❌ Problem: Hard to know which result belongs to which host!"

    # Demonstrate with_targets format
    IO.puts "\n2. :with_targets format:"
    with_targets_results = SnmpKit.SnmpMgr.get_multi(requests, return_format: :with_targets)
    IO.puts "   Results:"
    Enum.each(with_targets_results, fn {host, oid, result} ->
      status = case result do
        {:ok, _} -> "✅ Success"
        {:error, _} -> "❌ Error"
      end
      IO.puts "     #{host} (#{oid}) → #{status}"
    end)

    # Demonstrate map format
    IO.puts "\n3. :map format:"
    map_results = SnmpKit.SnmpMgr.get_multi(requests, return_format: :map)
    IO.puts "   Results:"
    Enum.each(map_results, fn {{host, oid}, result} ->
      status = case result do
        {:ok, _} -> "✅ Success"
        {:error, _} -> "❌ Error"
      end
      IO.puts "     #{host} (#{oid}) → #{status}"
    end)
    IO.puts "   ✅ Easy lookup: map_results[{\"device1.example.com\", \"1.3.6.1.2.1.1.1.0\"}]"
  end

  defp demo_bulk_multi do
    IO.puts """

    📊 BULK Multi Operations
    ========================
    """

    requests = [
      {"switch1.example.com", "1.3.6.1.2.1.2.2", [timeout: 100]},
      {"switch2.example.com", "1.3.6.1.2.1.2.2", [timeout: 100]}
    ]

    IO.puts "Sample bulk requests:"
    Enum.each(requests, fn {host, oid, _opts} ->
      IO.puts "  • #{host} → #{oid} (ifTable)"
    end)

    # Show map format for bulk operations
    IO.puts "\nUsing :map format for easy result processing:"
    map_results = SnmpKit.SnmpMgr.get_bulk_multi(requests, return_format: :map, max_repetitions: 5)

    Enum.each(map_results, fn {{host, oid}, result} ->
      case result do
        {:ok, data} when is_list(data) ->
          IO.puts "  ✅ #{host}: Retrieved #{length(data)} interface entries"
        {:error, reason} ->
          IO.puts "  ❌ #{host}: Failed (#{inspect(reason)})"
      end
    end)
  end

  defp demo_practical_usage do
    IO.puts """

    🛠️  Practical Usage Patterns
    ============================
    """

    requests = [
      {"router1.example.com", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
      {"router2.example.com", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
      {"router3.example.com", "1.3.6.1.2.1.1.1.0", [timeout: 100]}
    ]

    IO.puts "1. Processing results with error handling:"

    # Using with_targets format for easy processing
    results = SnmpKit.SnmpMgr.get_multi(requests, return_format: :with_targets)

    {successful, failed} =
      results
      |> Enum.split_with(fn {_host, _oid, result} -> match?({:ok, _}, result) end)

    IO.puts "   ✅ Successful queries: #{length(successful)}"
    IO.puts "   ❌ Failed queries: #{length(failed)}"

    if length(failed) > 0 do
      IO.puts "\n   Failed devices:"
      Enum.each(failed, fn {host, _oid, {:error, reason}} ->
        IO.puts "     • #{host}: #{inspect(reason)}"
      end)
    end

    IO.puts "\n2. Using map format for selective processing:"

    # Using map format for easy lookup
    map_results = SnmpKit.SnmpMgr.get_multi(requests, return_format: :map)

    # Check specific device
    key = {"router1.example.com", "1.3.6.1.2.1.1.1.0"}
    case Map.get(map_results, key) do
      {:ok, description} ->
        IO.puts "   Router1 description: #{description}"
      {:error, reason} ->
        IO.puts "   Router1 unavailable: #{inspect(reason)}"
      nil ->
        IO.puts "   Router1 not found in results"
    end

    IO.puts "\n3. Converting between formats (if needed):"

    # Convert list to map manually (though return_format: :map is easier)
    list_results = SnmpKit.SnmpMgr.get_multi(requests)
    manual_map =
      requests
      |> Enum.zip(list_results)
      |> Enum.map(fn {{host, oid, _opts}, result} -> {{host, oid}, result} end)
      |> Enum.into(%{})

    IO.puts "   Manual conversion successful: #{map_size(manual_map)} entries"
    IO.puts "   (But using return_format: :map is much cleaner!)"

    IO.puts """

    💡 Recommendations:
    ===================

    • Use :list (default) when you process results in the same order as requests
    • Use :with_targets when you need to iterate through host/result pairs
    • Use :map when you need to look up results by specific host/OID combinations
    • All formats maintain the same ordering and contain the same data
    • Choose the format that makes your code most readable and maintainable
    """
  end
end

# Run the demo
MultiReturnFormatDemo.run()
