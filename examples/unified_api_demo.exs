#!/usr/bin/env elixir

# Unified SnmpKit API Demo
#
# Shows the context modules (SnmpKit.SNMP, SnmpKit.MIB, SnmpKit.Sim) and the
# SnmpKit shortcuts against a simulated device. Self-contained.
#
# Run from a checkout:   mix run examples/unified_api_demo.exs
# Standalone:            elixir examples/unified_api_demo.exs

unless Code.ensure_loaded?(SnmpKit), do: Mix.install([{:snmpkit, "~> 2.0"}])

defmodule UnifiedAPIDemo do
  @moduledoc """
  Demonstrates the SnmpKit API:
  - SNMP operations through SnmpKit.SNMP
  - MIB operations through SnmpKit.MIB
  - Simulation through SnmpKit.Sim
  - Shortcuts on SnmpKit
  """

  @port 30162

  def run do
    IO.puts """

    SnmpKit Unified API Demo
    ========================
    """

    target = demo_simulation()
    demo_mib_operations()
    demo_snmp_operations(target)
    demo_shortcuts(target)
    demo_api_organization()
  end

  defp demo_simulation do
    IO.puts """

    Simulation (SnmpKit.Sim)
    ========================
    """

    # A bundled walk file (:router, :cable_modem or :switch) becomes a device
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    {:ok, _device} = SnmpKit.Sim.start_device(profile, port: @port)
    target = "127.0.0.1:#{@port}"
    IO.puts "  Simulated router started on #{target}"
    target
  end

  defp demo_mib_operations do
    IO.puts """

    MIB Operations (SnmpKit.MIB)
    ============================
    """

    IO.puts "  Resolving names to OIDs:"

    for name <- ["sysDescr.0", "sysUpTime.0", "ifDescr.1", "system", "interfaces"] do
      case SnmpKit.MIB.resolve(name) do
        {:ok, oid} -> IO.puts "    #{name} -> #{Enum.join(oid, ".")}"
        {:error, reason} -> IO.puts "    #{name} -> #{inspect(reason)}"
      end
    end

    IO.puts "\n  Reverse lookup:"

    case SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0]) do
      {:ok, name} -> IO.puts "    1.3.6.1.2.1.1.1.0 -> #{name}"
      {:error, reason} -> IO.puts "    reverse lookup failed: #{inspect(reason)}"
    end
  end

  defp demo_snmp_operations(target) do
    IO.puts """

    SNMP Operations (SnmpKit.SNMP)
    ==============================
    """

    # Every operation returns enriched varbind maps
    IO.puts "  GET:"

    case SnmpKit.SNMP.get(target, "sysDescr.0") do
      {:ok, %{name: name, type: type, value: value}} ->
        IO.puts "    #{name} (#{type}) = #{inspect(value)}"

      {:error, reason} ->
        IO.puts "    error: #{inspect(reason)}"
    end

    IO.puts "\n  WALK:"

    case SnmpKit.SNMP.walk(target, "system") do
      {:ok, results} -> IO.puts "    #{length(results)} objects in the system group"
      {:error, reason} -> IO.puts "    error: #{inspect(reason)}"
    end

    IO.puts "\n  Pretty output (same map, read :formatted):"

    case SnmpKit.SNMP.get_pretty(target, "sysUpTime.0") do
      {:ok, %{formatted: formatted}} -> IO.puts "    sysUpTime.0 = #{formatted}"
      {:error, reason} -> IO.puts "    error: #{inspect(reason)}"
    end

    IO.puts "\n  Table as rows (get_table):"

    case SnmpKit.SNMP.get_table(target, "ifTable", named: true) do
      {:ok, rows} ->
        for {index, row} <- Enum.sort(rows) do
          IO.puts "    #{index}: #{row["ifDescr"]} (#{row["ifOperStatus"]})"
        end

      {:error, reason} ->
        IO.puts "    error: #{inspect(reason)}"
    end

    IO.puts "\n  Multi-target (results in request order):"

    for {:ok, [%{name: name, formatted: formatted}]} <-
          SnmpKit.SNMP.get_multi([{target, "sysName.0"}, {target, "sysLocation.0"}]) do
      IO.puts "    #{name} = #{formatted}"
    end
  end

  defp demo_shortcuts(target) do
    IO.puts """

    Shortcuts (SnmpKit)
    ===================

    The most common calls are also on the SnmpKit module and return the
    same shapes:
    """

    {:ok, oid} = SnmpKit.resolve("ifInOctets.1")
    IO.puts "    SnmpKit.resolve(\"ifInOctets.1\") -> #{Enum.join(oid, ".")}"

    {:ok, %{formatted: name}} = SnmpKit.get(target, "sysName.0")
    IO.puts "    SnmpKit.get(target, \"sysName.0\") -> #{name}"

    {:ok, rows} = SnmpKit.walk(target, "interfaces")
    IO.puts "    SnmpKit.walk(target, \"interfaces\") -> #{length(rows)} objects"
  end

  defp demo_api_organization do
    IO.puts """

    API Organization
    ================

    SnmpKit.SNMP   get, get_next, set, walks, bulk, tables, streams, async,
                   multi-target, pretty output, send_trap/send_inform
    SnmpKit.MIB    name/OID resolution, tree navigation, compile and load MIBs
    SnmpKit.Sim    simulated devices and populations, record a real device
    SnmpKit.Agent  serve your own data over SNMP
    SnmpKit.Trap   receive traps and informs
    SnmpKit        shortcuts: get, walk, set, get_bulk, get_multi, resolve, ...

    Examples:

      {:ok, %{value: value}} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")
      {:ok, table} = SnmpKit.SNMP.get_table("192.168.1.1", "ifTable")
      results = SnmpKit.SNMP.walk_multi([{"host1", "system"}, {"host2", "interfaces"}])

      {:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
      {:ok, compiled} = SnmpKit.MIB.compile("MY-MIB.mib")
      :ok = SnmpKit.MIB.load(compiled)

      {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, "device.walk"})
      {:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)

      {:ok, %{value: value}} = SnmpKit.get("192.168.1.1", "sysDescr.0")
    """
  end
end

UnifiedAPIDemo.run()
