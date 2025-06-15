#!/usr/bin/env elixir

# Quick Cable Modem Simulation Example
# This shows the simplest way to create a cable modem simulation without walk files

Mix.install([
  {:snmpkit, "~> 0.3.1"}
])

# Create essential cable modem OIDs
cable_modem_oids = %{
  # System information
  "1.3.6.1.2.1.1.1.0" => "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem",
  "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 0},
  "1.3.6.1.2.1.1.5.0" => "cable-modem-001",

  # Interface count and descriptions
  "1.3.6.1.2.1.2.1.0" => 2,
  "1.3.6.1.2.1.2.2.1.2.1" => "cable-downstream0/0/0",
  "1.3.6.1.2.1.2.2.1.2.2" => "cable-upstream0/0/0",

  # Interface types (127 = docsCableMaclayer)
  "1.3.6.1.2.1.2.2.1.3.1" => 127,
  "1.3.6.1.2.1.2.2.1.3.2" => 127,

  # Interface status (1 = up)
  "1.3.6.1.2.1.2.2.1.8.1" => 1,
  "1.3.6.1.2.1.2.2.1.8.2" => 1,

  # Traffic counters (will increment automatically)
  "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 0},  # ifInOctets downstream
  "1.3.6.1.2.1.2.2.1.16.1" => %{type: "Counter32", value: 0},  # ifOutOctets downstream
  "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 0},  # ifInOctets upstream
  "1.3.6.1.2.1.2.2.1.16.2" => %{type: "Counter32", value: 0},  # ifOutOctets upstream

  # DOCSIS status
  "1.3.6.1.2.1.10.127.1.2.2.1.1.2" => 12,  # docsIfCmStatusValue (operational)
  "1.3.6.1.2.1.10.127.1.2.2.1.15.2" => 35,  # Signal/Noise ratio (35 dB)
}

# Create the profile with realistic behaviors
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
  :cable_modem,
  {:manual, cable_modem_oids},
  behaviors: [:counter_increment]
)

# Start the simulated cable modem
{:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)

IO.puts("✅ Cable modem simulation started on port 1161")

# Test the simulation
target = "127.0.0.1:1161"

# Query some basic information
{:ok, description} = SnmpKit.SNMP.get(target, "1.3.6.1.2.1.1.1.0")
{:ok, name} = SnmpKit.SNMP.get(target, "1.3.6.1.2.1.1.5.0")
{:ok, status} = SnmpKit.SNMP.get(target, "1.3.6.1.2.1.10.127.1.2.2.1.1.2")

IO.puts("\n📊 Cable Modem Information:")
IO.puts("  Description: #{description}")
IO.puts("  Name: #{name}")
IO.puts("  DOCSIS Status: #{status} (12 = operational)")

# Walk the system group
{:ok, system_info} = SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1")
IO.puts("\n🚶 System group contains #{length(system_info)} OIDs")

# Walk interfaces
{:ok, interfaces} = SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.2")
IO.puts("🔌 Interface group contains #{length(interfaces)} OIDs")

IO.puts("\n🎉 Cable modem is ready for SNMP queries!")
IO.puts("\nTry these commands:")
IO.puts("  SnmpKit.SNMP.get(\"#{target}\", \"sysDescr.0\")")
IO.puts("  SnmpKit.SNMP.walk(\"#{target}\", \"system\")")
IO.puts("  SnmpKit.SNMP.get(\"#{target}\", \"ifNumber.0\")")

# Keep running
IO.puts("\nPress Ctrl+C to stop...")
Process.sleep(:infinity)
