#!/usr/bin/env elixir

# Example: Using Full MIB Compilation for DOCSIS Cable Modem Management
#
# This example demonstrates how to compile and use specialized MIBs. The
# built-in tables cover the common IETF MIBs and the core of DOCS-IF-MIB; for
# the rest of DOCSIS and for vendor MIBs you compile the MIB files. When run
# from a checkout it compiles DOCS-IF-MIB from the test fixtures.
#
# Run from a checkout:   mix run examples/docsis_mib_example.exs
# Standalone:            elixir examples/docsis_mib_example.exs

unless Code.ensure_loaded?(SnmpKit), do: Mix.install([{:snmpkit, "~> 2.0"}])

defmodule DocsisExample do
  @moduledoc """
  Example of compiling and using DOCSIS MIBs for cable modem management.

  DOCSIS (Data Over Cable Service Interface Specification) defines MIBs for
  managing cable modems, cable modem termination systems (CMTS), and related
  infrastructure.
  """

  def run_example do
    IO.puts("=== DOCSIS MIB Compilation Example ===")
    IO.puts("")

    # Step 1: Show current stub capabilities
    show_stub_limitations()

    # Step 2: Demonstrate MIB compilation workflow
    demonstrate_mib_compilation()

    # Step 3: Show how compiled MIBs integrate with stubs
    show_integration()

    # Step 4: Practical DOCSIS queries
    docsis_practical_examples()
  end

  defp show_stub_limitations do
    IO.puts("1. Built-in MIB Coverage:")
    IO.puts("")

    # What resolves without loading anything
    names = [
      {"system", "MIB-II system group"},
      {"ifTable", "MIB-II interfaces"},
      {"ifXTable", "IF-MIB extended interfaces"},
      {"ip", "IP statistics"},
      {"docsIfCmStatusValue", "DOCS-IF-MIB cable modem status"},
      {"docsIfDownChannelFrequency", "DOCS-IF-MIB downstream channel"},
      {"docsDevSwCurrentVers", "DOCS-CABLE-DEVICE-MIB software version"},
      {"docsIf3CmStatusValue", "DOCS-IF3-MIB (DOCSIS 3.0)"}
    ]

    for {name, description} <- names do
      case SnmpKit.MIB.resolve(name) do
        {:ok, oid} ->
          IO.puts("  #{String.pad_trailing(name, 28)} built in   #{Enum.join(oid, ".")}  (#{description})")

        {:error, :not_found} ->
          IO.puts("  #{String.pad_trailing(name, 28)} not built in  (#{description}; compile the MIB)")
      end
    end

    IO.puts("")
    IO.puts("Anything not built in resolves after its MIB is compiled and loaded.")
    IO.puts("")
  end

  defp demonstrate_mib_compilation do
    IO.puts("2. MIB Compilation Workflow:")
    IO.puts("")

    IO.puts("Step-by-step process for adding DOCSIS MIB support:")
    IO.puts("")

    workflow_steps = [
      "Download DOCSIS MIB files from CableLabs or the vendor",
      "Place MIB files in a mibs/ directory",
      "Compile them with SnmpKit.MIB.compile/2 (or compile_dir/2)",
      "Register the result with SnmpKit.MIB.load/1",
      "Use symbolic names in SNMP operations"
    ]

    workflow_steps
    |> Enum.with_index(1)
    |> Enum.each(fn {step, idx} ->
      IO.puts("  #{idx}. #{step}")
    end)

    IO.puts("")
    show_code_examples()
    compile_fixture_mib()
  end

  defp show_code_examples do
    IO.puts("Code Examples:")
    IO.puts("")

    IO.puts("# Compile a single DOCSIS MIB file; the result is a map with :symbols and :warnings")
    IO.puts(~S|{:ok, compiled} = SnmpKit.MIB.compile("mibs/DOCS-IF-MIB.mib")|)
    IO.puts("")

    IO.puts("# Compile all MIBs in a directory")
    IO.puts(~S|{:ok, compiled_list} = SnmpKit.MIB.compile_dir("mibs/docsis/")|)
    IO.puts("")

    IO.puts("# Register a compiled MIB (or a .bin written by SnmpKit.MIB.Compiler.write_compiled/2)")
    IO.puts(~S|:ok = SnmpKit.MIB.load(compiled)|)
    IO.puts("")

    IO.puts("# Compile and register in one step")
    IO.puts(~S|:ok = SnmpKit.MIB.load_and_integrate_mib("mibs/DOCS-IF-MIB.mib")|)
    IO.puts("")
  end

  # From a checkout the DOCSIS MIBs are in the test fixtures; compile one for real.
  @fixture "test/fixtures/mibs/docsis/DOCS-IF-MIB"

  defp compile_fixture_mib do
    if File.exists?(@fixture) do
      IO.puts("Compiling #{@fixture}:")

      case SnmpKit.MIB.compile(@fixture) do
        {:ok, compiled} ->
          IO.puts("  #{map_size(compiled.symbols)} symbols, #{length(compiled.warnings)} warnings")
          :ok = SnmpKit.MIB.load(compiled)
          {:ok, oid} = SnmpKit.MIB.resolve("docsIfCmStatusTxPower")
          IO.puts("  docsIfCmStatusTxPower -> #{Enum.join(oid, ".")} (after loading)")

        {:error, reason} ->
          IO.puts("  compile failed: #{inspect(reason)}")
      end

      IO.puts("")
    end
  end

  defp show_integration do
    IO.puts("3. Integration with the Built-in Tables:")
    IO.puts("")

    IO.puts("Compiled MIBs and the built-in tables share one registry:")
    IO.puts("")

    integration_points = [
      "Built-in tables cover the common IETF MIBs (system, interfaces, ip, ...)",
      "Compiled MIBs add specialized objects (DOCSIS, vendor-specific, ...)",
      "resolve/1, reverse_lookup/1 and :formatted values use both",
      "Built-in and compiled names can be mixed in the same operation"
    ]

    integration_points
    |> Enum.with_index(1)
    |> Enum.each(fn {point, _idx} ->
      IO.puts("  • #{point}")
    end)

    IO.puts("")
    show_mixed_usage()
  end

  defp show_mixed_usage do
    IO.puts("Mixed Usage Example:")
    IO.puts("")

    IO.puts("# One GET PDU mixing built-in and compiled names")
    IO.puts(~S|{:ok, varbinds} = SnmpKit.SNMP.get("192.168.1.100", [|)
    IO.puts(~S|  "sysDescr.0",                 # built in|)
    IO.puts(~S|  "sysUpTime.0",                # built in|)
    IO.puts(~S|  "docsIfCmStatusTxPower.2",    # compiled DOCS-IF-MIB|)
    IO.puts(~S|  "docsDevSwCurrentVers.0"      # compiled DOCS-CABLE-DEVICE-MIB|)
    IO.puts(~S|])|)
    IO.puts("")

    IO.puts("# Bulk walk with compiled MIB names")
    IO.puts(~S|{:ok, rows} = SnmpKit.SNMP.bulk_walk_pretty("192.168.1.100", "docsIfCmtsCmStatusTable")|)
    IO.puts("")
  end

  defp docsis_practical_examples do
    IO.puts("4. Practical DOCSIS Use Cases:")
    IO.puts("")

    docsis_use_cases = [
      {
        "Cable Modem Status Monitoring",
        [
          "docsIfCmStatusValue - CM operational status",
          "docsIfCmStatusResets - Number of CM resets",
          "docsIfCmStatusLostSyncs - Lost sync events",
          "docsIfCmStatusInvalidMaps - Invalid MAP messages"
        ]
      },
      {
        "Signal Quality Monitoring",
        [
          "docsIfSigQSignalNoise - Signal-to-noise ratio",
          "docsIfSigQMicroreflections - Microreflection levels",
          "docsIfDownChannelPower - Downstream power levels",
          "docsIfUpChannelTxTimingOffset - Timing offset"
        ]
      },
      {
        "Configuration Management",
        [
          "docsDevNmAccessIp - Network management access IPs",
          "docsDevNmAccessIpMask - Access IP masks",
          "docsDevNmAccessControl - Access control settings",
          "docsDevNmAccessInterfaces - Management interfaces"
        ]
      },
      {
        "Performance Monitoring",
        [
          "docsIfCmtsUpChnlCtrTotalMslots - Total mini-slots",
          "docsIfCmtsUpChnlCtrUcastGrantedMslots - Unicast granted slots",
          "docsIfCmtsUpChnlCtrTotalCntnMslots - Contention mini-slots",
          "docsIfCmtsUpChnlCtrUsedCntnMslots - Used contention slots"
        ]
      }
    ]

    for {category, objects} <- docsis_use_cases do
      IO.puts("#{category}:")
      for object <- objects do
        IO.puts("  • #{object}")
      end
      IO.puts("")
    end
  end

  def demonstrate_file_structure do
    IO.puts("=== Recommended Directory Structure ===")
    IO.puts("")

    structure = """
    project/
    ├── mibs/
    │   ├── docsis/
    │   │   ├── DOCS-IF-MIB.mib
    │   │   ├── DOCS-CABLE-DEVICE-MIB.mib
    │   │   ├── DOCS-BPI-MIB.mib
    │   │   └── DOCS-QOS-MIB.mib
    │   ├── cisco/
    │   │   ├── CISCO-CABLE-MODEM-MIB.mib
    │   │   └── CISCO-DOCS-EXT-MIB.mib
    │   └── compiled/
    │       ├── DOCS-IF-MIB.bin
    │       ├── DOCS-CABLE-DEVICE-MIB.bin
    │       └── ...
    ├── lib/
    └── ...
    """

    IO.puts(structure)
  end

  def show_compilation_script do
    IO.puts("=== Bulk Compilation Script ===")
    IO.puts("")

    script = """
    # compile_all_mibs.exs
    defmodule MibCompiler do
      def compile_all do
        # Compile DOCSIS MIBs
        {:ok, docsis} = SnmpKit.MIB.compile_dir("mibs/docsis/")
        IO.puts("Compiled #\{length(docsis)} DOCSIS MIBs")

        # Compile vendor-specific MIBs
        {:ok, cisco} = SnmpKit.MIB.compile_dir("mibs/cisco/")
        IO.puts("Compiled #\{length(cisco)} Cisco MIBs")

        # Register them; load/1 also accepts a .bin written by write_compiled/2
        for compiled <- docsis ++ cisco do
          :ok = SnmpKit.MIB.load(compiled)
          IO.puts("Loaded #\{compiled.name}")
        end
      end
    end

    MibCompiler.compile_all()
    """

    IO.puts(script)
  end

  def test_mib_system do
    IO.puts("=== Testing MIB Resolution System ===")
    IO.puts("")

    test_objects = [
      "sysDescr",
      "ifName",
      "docsIfCmStatusValue",
      "docsIfCmStatusTxPower",
      "1.3.6.1.2.1.1.1"
    ]

    IO.puts("Resolution with the built-in tables only (nothing loaded):")

    for object <- test_objects do
      case SnmpKit.MIB.resolve(object) do
        {:ok, oid} ->
          IO.puts("  #{String.pad_trailing(object, 25)} -> #{Enum.join(oid, ".")}")

        {:error, reason} ->
          IO.puts("  #{String.pad_trailing(object, 25)} -> #{inspect(reason)} (compile its MIB)")
      end
    end
  end
end

# Usage examples
case System.argv() do
  [] ->
    DocsisExample.run_example()
  ["--structure"] ->
    DocsisExample.demonstrate_file_structure()
  ["--script"] ->
    DocsisExample.show_compilation_script()
  ["--test"] ->
    DocsisExample.test_mib_system()
  _ ->
    IO.puts("Usage:")
    IO.puts("  mix run examples/docsis_mib_example.exs                # Full example")
    IO.puts("  mix run examples/docsis_mib_example.exs --structure    # Show directory structure")
    IO.puts("  mix run examples/docsis_mib_example.exs --script       # Show compilation script")
    IO.puts("  mix run examples/docsis_mib_example.exs --test         # Test MIB resolution")
end
