#!/usr/bin/env elixir

# SnmpKit Getting Started Example
# ==============================
#
# Creates a simulated SNMP device and runs the core operations against it:
# GET, WALK, bulk walk, MIB resolution and error handling. Self-contained,
# no hardware needed.
#
# Run from a checkout:   mix run examples/getting_started.exs
# Standalone:            elixir examples/getting_started.exs  (fetches snmpkit from Hex)

unless Code.ensure_loaded?(SnmpKit), do: Mix.install([{:snmpkit, "~> 2.0"}])

defmodule GettingStartedExample do
  @moduledoc """
  A getting started example for SnmpKit: device simulation, basic SNMP
  operations, MIB operations and error handling.
  """

  alias SnmpKit.{SNMP, MIB, Sim}

  @port 30161

  def run do
    IO.puts("""

    SnmpKit Getting Started Example
    ===============================

    1. Create a simulated SNMP device
    2. Perform basic SNMP operations
    3. Explore MIB functionality
    4. Bulk, async and error handling
    """)

    with {:ok, device_info} <- setup_simulated_device(),
         :ok <- demonstrate_basic_operations(device_info),
         :ok <- demonstrate_mib_operations(),
         :ok <- demonstrate_advanced_features(device_info),
         :ok <- cleanup(device_info) do
      IO.puts("""

      Example completed.

      Next steps:
      - API documentation: https://hexdocs.pm/snmpkit
      - Quickstart Livebook: livebooks/01_quickstart.livemd
      - Guides: docs/unified-api-guide.md, docs/mib-guide.md, docs/testing-guide.md
      """)
    else
      {:error, reason} ->
        IO.puts("Example failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp setup_simulated_device do
    IO.puts("Setting up simulated SNMP device...")

    # A plain %{objects: %{oid => value}} map is enough for a device. Values
    # are typed from their Elixir type (string -> OCTET STRING, integer ->
    # INTEGER); pass %{type: "Counter32", value: n} for anything else.
    device_profile = %{objects: create_device_objects()}

    case Sim.start_device(device_profile, port: @port) do
      {:ok, device} ->
        target = "127.0.0.1:#{@port}"
        IO.puts("Simulated device started on #{target}")
        {:ok, %{device: device, target: target}}

      {:error, reason} ->
        IO.puts("Failed to start device: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_device_objects do
    %{
      # System group (sysUpTime.0 is computed by the device)
      [1, 3, 6, 1, 2, 1, 1, 1, 0] => "SnmpKit Example Router v1.0 - Getting Started Demo",
      [1, 3, 6, 1, 2, 1, 1, 2, 0] => %{type: "OBJECT IDENTIFIER", value: "1.3.6.1.4.1.99999.1.1"},
      [1, 3, 6, 1, 2, 1, 1, 4, 0] => "Example Admin <admin@example.com>",
      [1, 3, 6, 1, 2, 1, 1, 5, 0] => "getting-started-router",
      [1, 3, 6, 1, 2, 1, 1, 6, 0] => "SnmpKit Demo Lab",
      [1, 3, 6, 1, 2, 1, 1, 7, 0] => 72,

      # Interface table - 4 interfaces
      [1, 3, 6, 1, 2, 1, 2, 1, 0] => 4,

      # Interface 1 - Loopback
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1] => 1,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1] => "lo0",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 1] => 24,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 1] => %{type: "Gauge32", value: 10_000_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 1] => 1,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1] => %{type: "Counter32", value: 1_000_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 1] => %{type: "Counter32", value: 500_000},

      # Interface 2 - Ethernet
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 2] => 2,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 2] => "eth0",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 2] => 6,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 2] => %{type: "Gauge32", value: 1_000_000_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 2] => 1,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 2] => %{type: "Counter32", value: 50_000_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 2] => %{type: "Counter32", value: 25_000_000},

      # Interface 3 - Ethernet, down
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 3] => 3,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 3] => "eth1",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 3] => 6,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 3] => %{type: "Gauge32", value: 1_000_000_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 3] => 2,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 3] => %{type: "Counter32", value: 0},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 3] => %{type: "Counter32", value: 0},

      # Interface 4 - Serial
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 4] => 4,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 4] => "serial0",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 4] => 22,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 4] => %{type: "Gauge32", value: 1_544_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 4] => 1,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 4] => %{type: "Counter32", value: 10_000_000},
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 4] => %{type: "Counter32", value: 8_000_000}
    }
  end

  defp demonstrate_basic_operations(%{target: target}) do
    IO.puts("""

    Basic SNMP Operations
    =====================
    """)

    # GET returns one enriched varbind map
    IO.puts("GET:")

    with {:ok, %{formatted: description}} <- SNMP.get(target, "sysDescr.0") do
      IO.puts("   sysDescr.0: #{description}")
    end

    # Several objects in one PDU
    IO.puts("\nGET with several OIDs in one PDU:")

    with {:ok, varbinds} <-
           SNMP.get(target, ["sysDescr.0", "sysUpTime.0", "sysName.0", "sysLocation.0"]) do
      for %{name: name, formatted: formatted} <- varbinds do
        IO.puts("   #{name}: #{formatted}")
      end
    end

    # WALK returns a list of enriched maps in OID order
    IO.puts("\nWALK of the system group:")

    case SNMP.walk(target, "system") do
      {:ok, results} ->
        IO.puts("   #{length(results)} objects:")

        for %{name: name, formatted: formatted} <- Enum.take(results, 5) do
          IO.puts("     #{name} = #{formatted}")
        end

        if length(results) > 5, do: IO.puts("     ... and #{length(results) - 5} more")

      {:error, reason} ->
        IO.puts("   WALK failed: #{inspect(reason)}")
    end

    # get_table groups a table walk into %{index => %{column => value}};
    # named: true uses the MIB's column names
    IO.puts("\nInterface table (get_table with named: true):")

    case SNMP.get_table(target, "ifTable", named: true) do
      {:ok, rows} ->
        for {index, row} <- Enum.sort(rows) do
          status = if row["ifOperStatus"] == 1, do: "up", else: "down"
          IO.puts("     #{index}: #{row["ifDescr"]} - #{status}")
        end

      {:error, reason} ->
        IO.puts("   get_table failed: #{inspect(reason)}")
    end

    :ok
  end

  defp demonstrate_mib_operations do
    IO.puts("""

    MIB Operations
    ==============
    """)

    IO.puts("Name -> OID:")

    for name <- ["sysDescr.0", "sysUpTime.0", "ifTable", "ifInOctets.1"] do
      case MIB.resolve(name) do
        {:ok, oid} -> IO.puts("   #{name} -> #{Enum.join(oid, ".")}")
        {:error, reason} -> IO.puts("   #{name} -> #{inspect(reason)}")
      end
    end

    IO.puts("\nOID -> name:")

    for oid <- [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0], [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1]] do
      case MIB.reverse_lookup(oid) do
        {:ok, name} -> IO.puts("   #{Enum.join(oid, ".")} -> #{name}")
        {:error, reason} -> IO.puts("   #{Enum.join(oid, ".")} -> #{inspect(reason)}")
      end
    end

    IO.puts("\nTree navigation:")

    with {:ok, system_oid} <- MIB.resolve("system"),
         {:ok, children} <- MIB.children(system_oid) do
      IO.puts("   system (#{Enum.join(system_oid, ".")}) has #{length(children)} children:")
      IO.puts("   #{Enum.join(children, ", ")}")
    end

    :ok
  end

  defp demonstrate_advanced_features(%{target: target}) do
    IO.puts("""

    Bulk, Async and Errors
    ======================
    """)

    IO.puts("Bulk walk (GETBULK):")

    case SNMP.bulk_walk(target, "interfaces") do
      {:ok, results} -> IO.puts("   #{length(results)} objects")
      {:error, reason} -> IO.puts("   bulk walk failed: #{inspect(reason)}")
    end

    IO.puts("\nAsync (get_async returns a Task):")

    tasks = for oid <- ["sysDescr.0", "sysUpTime.0", "sysName.0"], do: SNMP.get_async(target, oid)

    for {:ok, %{name: name, formatted: formatted}} <- Task.await_many(tasks, 5_000) do
      IO.puts("   #{name}: #{formatted}")
    end

    IO.puts("\nMulti-target (one result per request, in request order):")

    results = SNMP.get_multi([{target, "sysName.0"}, {target, "sysLocation.0"}])

    for {:ok, [%{name: name, formatted: formatted}]} <- results do
      IO.puts("   #{name}: #{formatted}")
    end

    IO.puts("\nError handling:")

    error_cases = [
      {"Unreachable host", "192.0.2.1", "sysDescr.0", timeout: 300, retries: 0},
      {"Unknown name", target, "nonExistent.0", []},
      {"Nothing listening", "127.0.0.1:1", "sysDescr.0", timeout: 300, retries: 0}
    ]

    for {label, error_target, oid, opts} <- error_cases do
      case SNMP.get(error_target, oid, opts) do
        {:ok, _} -> IO.puts("   #{label}: unexpected success")
        {:error, reason} -> IO.puts("   #{label}: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp cleanup(%{device: device}) do
    if Process.alive?(device), do: GenServer.stop(device)
    IO.puts("\nSimulated device stopped")
    :ok
  end
end

GettingStartedExample.run()
