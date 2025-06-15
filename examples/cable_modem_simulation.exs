#!/usr/bin/env elixir

# Cable Modem Simulation Examples
# Demonstrates how to create realistic DOCSIS cable modem simulations without walk files

Mix.install([
  {:snmpkit, "~> 0.3.1"}
])

alias SnmpKit.{SNMP, Sim}
require Logger

defmodule CableModemSimulation do
  @moduledoc """
  Examples of creating cable modem simulations without walk files.

  This module demonstrates several approaches:
  1. Manual OID definitions with essential cable modem MIBs
  2. JSON profile loading (structured approach)
  3. Programmatic profile generation
  4. Multiple cable modem population simulation
  """

  @doc """
  Method 1: Manual OID definitions
  Creates a basic but functional cable modem with essential DOCSIS OIDs
  """
  def create_basic_cable_modem(port \\ 1161) do
    IO.puts("🔧 Creating basic cable modem simulation...")

    # Essential cable modem OIDs based on DOCSIS standards
    cable_modem_oids = %{
      # System Group (RFC1213-MIB)
      "1.3.6.1.2.1.1.1.0" => "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.4115.1.20.1.1.2.25",
      "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 0},
      "1.3.6.1.2.1.1.4.0" => "Network Administrator <admin@example.com>",
      "1.3.6.1.2.1.1.5.0" => "cable-modem-001",
      "1.3.6.1.2.1.1.6.0" => "Home Network - Living Room",

      # Interface Group (IF-MIB)
      "1.3.6.1.2.1.2.1.0" => 2,  # ifNumber
      "1.3.6.1.2.1.2.2.1.1.1" => 1,  # ifIndex.1
      "1.3.6.1.2.1.2.2.1.1.2" => 2,  # ifIndex.2
      "1.3.6.1.2.1.2.2.1.2.1" => "cable-downstream0/0/0",  # ifDescr.1
      "1.3.6.1.2.1.2.2.1.2.2" => "cable-upstream0/0/0",    # ifDescr.2
      "1.3.6.1.2.1.2.2.1.3.1" => 127,  # ifType.1 (docsCableMaclayer)
      "1.3.6.1.2.1.2.2.1.3.2" => 127,  # ifType.2 (docsCableMaclayer)
      "1.3.6.1.2.1.2.2.1.5.1" => %{type: "Gauge32", value: 1000000000},  # ifSpeed.1 (1Gbps)
      "1.3.6.1.2.1.2.2.1.5.2" => %{type: "Gauge32", value: 100000000},   # ifSpeed.2 (100Mbps)
      "1.3.6.1.2.1.2.2.1.8.1" => 1,  # ifOperStatus.1 (up)
      "1.3.6.1.2.1.2.2.1.8.2" => 1,  # ifOperStatus.2 (up)

      # Interface Counters (with realistic increment rates)
      "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 0},  # ifInOctets.1
      "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 0},  # ifInOctets.2
      "1.3.6.1.2.1.2.2.1.16.1" => %{type: "Counter32", value: 0},  # ifOutOctets.1
      "1.3.6.1.2.1.2.2.1.16.2" => %{type: "Counter32", value: 0},  # ifOutOctets.2
      "1.3.6.1.2.1.2.2.1.11.1" => %{type: "Counter32", value: 0},  # ifInUcastPkts.1
      "1.3.6.1.2.1.2.2.1.11.2" => %{type: "Counter32", value: 0},  # ifInUcastPkts.2
      "1.3.6.1.2.1.2.2.1.17.1" => %{type: "Counter32", value: 0},  # ifOutUcastPkts.1
      "1.3.6.1.2.1.2.2.1.17.2" => %{type: "Counter32", value: 0},  # ifOutUcastPkts.2

      # DOCSIS Specific OIDs (DOCS-IF-MIB)
      "1.3.6.1.2.1.10.127.1.1.1.1.3.2" => 3,          # docsIfCmtsUpChannelId.2
      "1.3.6.1.2.1.10.127.1.1.1.1.6.2" => 36000000,   # docsIfCmtsUpChannelFrequency.2 (36MHz)
      "1.3.6.1.2.1.10.127.1.1.2.1.1.1" => 1,          # docsIfCmtsDownChannelId.1
      "1.3.6.1.2.1.10.127.1.1.2.1.2.1" => 591000000,  # docsIfCmtsDownChannelFrequency.1 (591MHz)
      "1.3.6.1.2.1.10.127.1.2.2.1.1.2" => 12,         # docsIfCmStatusValue.2 (operational)
      "1.3.6.1.2.1.10.127.1.2.2.1.12.2" => %{type: "Counter32", value: 0},  # docsIfCmStatusUnerroreds.2
      "1.3.6.1.2.1.10.127.1.2.2.1.13.2" => %{type: "Counter32", value: 0},  # docsIfCmStatusCorrecteds.2
      "1.3.6.1.2.1.10.127.1.2.2.1.14.2" => %{type: "Counter32", value: 0},  # docsIfCmStatusUncorrectables.2
      "1.3.6.1.2.1.10.127.1.2.2.1.15.2" => 35,        # docsIfCmStatusSignalNoise.2 (35 dB)
      "1.3.6.1.2.1.10.127.1.2.2.1.16.2" => 25,        # docsIfCmStatusMicroreflections.2
    }

    # Create profile with behaviors for realistic simulation
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
      :cable_modem,
      {:manual, cable_modem_oids},
      behaviors: [:counter_increment, :time_based_changes, :signal_fluctuation]
    )

    # Start the simulated device
    {:ok, device} = Sim.start_device(profile, port: port, community: "public")

    IO.puts("✅ Cable modem simulation started on port #{port}")
    {:ok, device, "127.0.0.1:#{port}"}
  end

  @doc """
  Method 2: JSON Profile Loading
  Uses structured JSON configuration for more complex setups
  """
  def create_json_cable_modem(port \\ 1162) do
    IO.puts("📄 Creating cable modem from JSON profile...")

    # Load from JSON profile (assuming the file exists)
    json_path = Path.join([__DIR__, "cable_modem_profile.json"])

    case File.exists?(json_path) do
      true ->
        {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
          :cable_modem,
          {:json_profile, json_path}
        )

        {:ok, device} = Sim.start_device(profile, port: port, community: "public")
        IO.puts("✅ JSON-based cable modem simulation started on port #{port}")
        {:ok, device, "127.0.0.1:#{port}"}

      false ->
        IO.puts("⚠️  JSON profile not found at #{json_path}")
        IO.puts("   Falling back to manual creation...")
        create_basic_cable_modem(port)
    end
  end

  @doc """
  Method 3: Programmatic Profile Generation
  Creates profiles with calculated values and realistic behaviors
  """
  def create_advanced_cable_modem(port \\ 1163, opts \\ []) do
    IO.puts("🚀 Creating advanced cable modem with calculated values...")

    device_id = Keyword.get(opts, :device_id, "cm-#{:rand.uniform(999)}")
    downstream_freq = Keyword.get(opts, :downstream_freq, 591_000_000)
    upstream_freq = Keyword.get(opts, :upstream_freq, 36_000_000)
    signal_noise = Keyword.get(opts, :signal_noise, 35)

    # Generate MAC address
    mac_suffix = :rand.uniform(16777215) |> Integer.to_string(16) |> String.pad_leading(6, "0")
    mac_address = "00:11:22:#{String.slice(mac_suffix, 0, 2)}:#{String.slice(mac_suffix, 2, 2)}:#{String.slice(mac_suffix, 4, 2)}"

    advanced_oids = %{
      # Enhanced System Group
      "1.3.6.1.2.1.1.1.0" => "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem (#{device_id})",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.4115.1.20.1.1.2.25",
      "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 0, behavior: "uptime"},
      "1.3.6.1.2.1.1.4.0" => "ISP Customer Service <support@isp.com>",
      "1.3.6.1.2.1.1.5.0" => device_id,
      "1.3.6.1.2.1.1.6.0" => "Customer Premises - #{device_id}",

      # Interface Configuration
      "1.3.6.1.2.1.2.1.0" => 3,  # More interfaces (management + cable)

      # Downstream Interface (Cable HFC)
      "1.3.6.1.2.1.2.2.1.1.1" => 1,
      "1.3.6.1.2.1.2.2.1.2.1" => "cable-downstream0/0/0 (#{downstream_freq/1000000} MHz)",
      "1.3.6.1.2.1.2.2.1.3.1" => 127,
      "1.3.6.1.2.1.2.2.1.5.1" => %{type: "Gauge32", value: 1_200_000_000},  # 1.2 Gbps
      "1.3.6.1.2.1.2.2.1.8.1" => 1,
      "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 0, behavior: "traffic_counter", rate: 15000},
      "1.3.6.1.2.1.2.2.1.16.1" => %{type: "Counter32", value: 0, behavior: "traffic_counter", rate: 8000},

      # Upstream Interface (Cable HFC)
      "1.3.6.1.2.1.2.2.1.1.2" => 2,
      "1.3.6.1.2.1.2.2.1.2.2" => "cable-upstream0/0/0 (#{upstream_freq/1000000} MHz)",
      "1.3.6.1.2.1.2.2.1.3.2" => 127,
      "1.3.6.1.2.1.2.2.1.5.2" => %{type: "Gauge32", value: 200_000_000},  # 200 Mbps
      "1.3.6.1.2.1.2.2.1.8.2" => 1,
      "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 0, behavior: "traffic_counter", rate: 12000},
      "1.3.6.1.2.1.2.2.1.16.2" => %{type: "Counter32", value: 0, behavior: "traffic_counter", rate: 18000},

      # Management Interface (Ethernet)
      "1.3.6.1.2.1.2.2.1.1.3" => 3,
      "1.3.6.1.2.1.2.2.1.2.3" => "eth0 (Management)",
      "1.3.6.1.2.1.2.2.1.3.3" => 6,  # ethernetCsmacd
      "1.3.6.1.2.1.2.2.1.5.3" => %{type: "Gauge32", value: 1_000_000_000},
      "1.3.6.1.2.1.2.2.1.8.3" => 1,
      "1.3.6.1.2.1.2.2.1.6.3" => mac_address,

      # Advanced DOCSIS Parameters
      "1.3.6.1.2.1.10.127.1.1.1.1.6.2" => upstream_freq,
      "1.3.6.1.2.1.10.127.1.1.2.1.2.1" => downstream_freq,
      "1.3.6.1.2.1.10.127.1.2.2.1.15.2" => %{
        type: "INTEGER",
        value: signal_noise,
        behavior: "fluctuate",
        min: signal_noise - 5,
        max: signal_noise + 5
      },

      # QoS and Service Flow Information
      "1.3.6.1.2.1.10.127.1.3.3.1.2.1" => 1,  # docsIfServiceFlowId
      "1.3.6.1.2.1.10.127.1.3.3.1.3.1" => 1,  # docsIfServiceFlowSid
      "1.3.6.1.2.1.10.127.1.3.3.1.4.1" => 1,  # docsIfServiceFlowDirection (downstream)

      # Cable Modem Status and Diagnostics
      "1.3.6.1.2.1.10.127.1.2.2.1.12.2" => %{type: "Counter32", value: 0, behavior: "error_counter", rate: 1},
      "1.3.6.1.2.1.10.127.1.2.2.1.13.2" => %{type: "Counter32", value: 0, behavior: "error_counter", rate: 0.1},
      "1.3.6.1.2.1.10.127.1.2.2.1.14.2" => %{type: "Counter32", value: 0, behavior: "error_counter", rate: 0.01},

      # Power Levels (dBmV)
      "1.3.6.1.4.1.4115.1.20.1.1.2.25.1.1.2.1" => %{
        type: "INTEGER",
        value: 5,
        behavior: "fluctuate",
        min: 0,
        max: 10,
        description: "Downstream power level (dBmV)"
      },
      "1.3.6.1.4.1.4115.1.20.1.1.2.25.1.2.2.2" => %{
        type: "INTEGER",
        value: 45,
        behavior: "fluctuate",
        min: 40,
        max: 50,
        description: "Upstream power level (dBmV)"
      }
    }

    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
      :cable_modem,
      {:manual, advanced_oids},
      behaviors: [:counter_increment, :time_based_changes, :signal_fluctuation, :realistic_errors]
    )

    {:ok, device} = Sim.start_device(profile, port: port, community: "public")

    IO.puts("✅ Advanced cable modem '#{device_id}' started on port #{port}")
    IO.puts("   📡 Downstream: #{downstream_freq/1000000} MHz")
    IO.puts("   📡 Upstream: #{upstream_freq/1000000} MHz")
    IO.puts("   📊 Signal/Noise: #{signal_noise} dB")
    IO.puts("   🔗 MAC: #{mac_address}")

    {:ok, device, "127.0.0.1:#{port}"}
  end

  @doc """
  Method 4: Cable Modem Population
  Creates multiple cable modems for testing at scale
  """
  def create_cable_modem_population(count \\ 5, start_port \\ 2000) do
    IO.puts("🏭 Creating population of #{count} cable modems...")

    devices =
      Enum.map(1..count, fn i ->
        port = start_port + i - 1
        device_id = "cm-#{String.pad_leading(to_string(i), 3, "0")}"

        # Vary parameters for realistic diversity
        opts = [
          device_id: device_id,
          downstream_freq: 591_000_000 + (:rand.uniform(20) - 10) * 6_000_000,  # ±60MHz
          upstream_freq: 36_000_000 + (:rand.uniform(10) - 5) * 6_000_000,      # ±30MHz
          signal_noise: 30 + :rand.uniform(15)  # 30-45 dB range
        ]

        case create_advanced_cable_modem(port, opts) do
          {:ok, device, target} ->
            %{device: device, target: target, device_id: device_id, port: port}
          {:error, reason} ->
            IO.puts("⚠️  Failed to create #{device_id}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    IO.puts("✅ Successfully created #{length(devices)} cable modems")
    devices
  end

  @doc """
  Test and demonstrate the simulated cable modems
  """
  def test_cable_modem(target) do
    IO.puts("\n🧪 Testing cable modem at #{target}")

    test_cases = [
      {"System Description", "1.3.6.1.2.1.1.1.0"},
      {"System Uptime", "1.3.6.1.2.1.1.3.0"},
      {"System Name", "1.3.6.1.2.1.1.5.0"},
      {"Interface Count", "1.3.6.1.2.1.2.1.0"},
      {"Downstream Interface", "1.3.6.1.2.1.2.2.1.2.1"},
      {"Upstream Interface", "1.3.6.1.2.1.2.2.1.2.2"},
      {"Downstream RX Octets", "1.3.6.1.2.1.2.2.1.10.1"},
      {"Upstream TX Octets", "1.3.6.1.2.1.2.2.1.16.2"},
      {"DOCSIS Status", "1.3.6.1.2.1.10.127.1.2.2.1.1.2"},
      {"Signal/Noise Ratio", "1.3.6.1.2.1.10.127.1.2.2.1.15.2"}
    ]

    Enum.each(test_cases, fn {name, oid} ->
      case SNMP.get(target, oid) do
        {:ok, value} ->
          IO.puts("  ✅ #{name}: #{inspect(value)}")
        {:error, reason} ->
          IO.puts("  ❌ #{name}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Demonstrate SNMP walk on simulated cable modem
  """
  def walk_cable_modem(target, root_oid \\ "1.3.6.1.2.1.1") do
    IO.puts("\n🚶 Walking #{root_oid} on #{target}")

    case SNMP.walk(target, root_oid) do
      {:ok, results} ->
        IO.puts("Found #{length(results)} OIDs:")
        results
        |> Enum.take(10)  # Show first 10
        |> Enum.each(fn {oid, value} ->
          IO.puts("  #{oid} = #{inspect(value)}")
        end)

        if length(results) > 10 do
          IO.puts("  ... and #{length(results) - 10} more")
        end

      {:error, reason} ->
        IO.puts("  ❌ Walk failed: #{inspect(reason)}")
    end
  end
end

# Main execution
IO.puts("🎯 SnmpKit Cable Modem Simulation Examples")
IO.puts("=" |> String.duplicate(50))

# Example 1: Basic Cable Modem
{:ok, _device1, target1} = CableModemSimulation.create_basic_cable_modem(1161)
CableModemSimulation.test_cable_modem(target1)

# Example 2: Advanced Cable Modem
{:ok, _device2, target2} = CableModemSimulation.create_advanced_cable_modem(1162)
CableModemSimulation.test_cable_modem(target2)
CableModemSimulation.walk_cable_modem(target2)

# Example 3: Cable Modem Population
IO.puts("\n" <> ("=" |> String.duplicate(50)))
population = CableModemSimulation.create_cable_modem_population(3, 2000)

# Test a few from the population
population
|> Enum.take(2)
|> Enum.each(fn %{target: target, device_id: device_id} ->
  IO.puts("\n📊 Testing #{device_id} at #{target}")
  CableModemSimulation.test_cable_modem(target)
end)

IO.puts("\n🎉 Cable modem simulations are running!")
IO.puts("You can now query them using standard SNMP tools or SnmpKit API calls.")
IO.puts("\nExample SNMP queries:")
IO.puts("  SnmpKit.SNMP.get(\"#{target1}\", \"sysDescr.0\")")
IO.puts("  SnmpKit.SNMP.walk(\"#{target2}\", \"system\")")

# Keep the script running to maintain the simulations
IO.puts("\nPress Ctrl+C to stop the simulations...")
Process.sleep(:infinity)
