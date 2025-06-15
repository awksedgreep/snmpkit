#!/usr/bin/env elixir

# Example: Using Full MIB Compilation for DOCSIS Cable Modem Management
#
# This example demonstrates how to compile and use specialized MIBs like DOCSIS
# that are not included in the built-in stubs. The MIB stub system handles
# common MIB-II objects, but for specialized protocols like DOCSIS, you'll
# want to compile the actual MIB files.

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
    IO.puts("1. Built-in MIB Stubs Coverage:")
    IO.puts("")

    # Show what's available in stubs
    stub_groups = [
      {"system", "Basic system info - ✓ Available"},
      {"if", "Standard interfaces - ✓ Available"},
      {"ifX", "Extended interfaces - ✓ Available"},
      {"ip", "IP statistics - ✓ Available"},
      {"docsis", "DOCSIS cable modem - ✗ Not available"},
      {"cableDataPrivateMib", "Cable data MIB - ✗ Not available"},
      {"docsIf", "DOCSIS interface - ✗ Not available"}
    ]

    for {name, status} <- stub_groups do
      case SnmpKit.SnmpMgr.MIB.resolve(name) do
        {:ok, oid} ->
          IO.puts("  #{String.pad_trailing(name, 20)} → #{inspect(oid)} #{status}")
        {:error, :not_found} ->
          IO.puts("  #{String.pad_trailing(name, 20)} → Not found - #{status}")
      end
    end

    IO.puts("")
    IO.puts("For specialized protocols like DOCSIS, you need to compile the MIB files.")
    IO.puts("")
  end

  defp demonstrate_mib_compilation do
    IO.puts("2. MIB Compilation Workflow:")
    IO.puts("")

    IO.puts("Step-by-step process for adding DOCSIS MIB support:")
    IO.puts("")

    workflow_steps = [
      "Download DOCSIS MIB files from CableLabs or vendor",
      "Place MIB files in a mibs/ directory",
      "Compile MIBs using SnmpKit.SnmpMgr.MIB.compile/2",
      "Load compiled MIBs using SnmpKit.SnmpMgr.MIB.load/1",
      "Use symbolic names in SNMP operations"
    ]

    workflow_steps
    |> Enum.with_index(1)
    |> Enum.each(fn {step, idx} ->
      IO.puts("  #{idx}. #{step}")
    end)

    IO.puts("")
    show_code_examples()
  end

  defp show_code_examples do
    IO.puts("Code Examples:")
    IO.puts("")

    IO.puts("# Compile a single DOCSIS MIB file")
    IO.puts(~S|{:ok, compiled_path} = SnmpKit.SnmpMgr.MIB.compile("mibs/DOCS-IF-MIB.mib")|)
    IO.puts("")

    IO.puts("# Compile all MIBs in a directory")
    IO.puts(~S|{:ok, results} = SnmpKit.SnmpMgr.MIB.compile_dir("mibs/docsis/")|)
    IO.puts("")

    IO.puts("# Load compiled MIB")
    IO.puts(~S|{:ok, mib_data} = SnmpKit.SnmpMgr.MIB.load("DOCS-IF-MIB.bin")|)
    IO.puts("")

    IO.puts("# Parse and integrate MIB (combines compilation + loading)")
    IO.puts(~S|{:ok, _} = SnmpKit.SnmpMgr.MIB.load_and_integrate_mib("mibs/DOCS-IF-MIB.mib")|)
    IO.puts("")
  end

  defp show_integration do
    IO.puts("3. Integration with Built-in Stubs:")
    IO.puts("")

    IO.puts("The MIB compilation system works alongside the built-in stubs:")
    IO.puts("")

    integration_points = [
      "Built-in stubs handle common MIB-II objects (system, if, ip, etc.)",
      "Compiled MIBs add specialized objects (DOCSIS, vendor-specific, etc.)",
      "Resolution tries compiled MIBs first, then falls back to stubs",
      "Both systems use the same API - completely transparent to users",
      "Can mix stub names and compiled names in the same operation"
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

    IO.puts("# Query combining stubs and compiled MIBs")
    IO.puts(~S|{:ok, results} = SnmpKit.SnmpLib.Manager.get_multi("192.168.1.100", [|)
    IO.puts(~S|  "sysDescr.0",           # Built-in stub|)
    IO.puts(~S|  "sysUpTime.0",          # Built-in stub|)
    IO.puts(~S|  "docsIfCmCpeCmdIpAddress.0",  # Compiled DOCSIS MIB|)
    IO.puts(~S|  "docsIfCmStatusValue.0"       # Compiled DOCSIS MIB|)
    IO.puts(~S|])|)
    IO.puts("")

    IO.puts("# Bulk walk with compiled MIB names")
    IO.puts(~S|{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "docsIfCmtsTable")|)
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
        {:ok, docsis_results} = SnmpKit.SnmpMgr.MIB.compile_dir("mibs/docsis/")
        IO.puts("Compiled #\{length(docsis_results)} DOCSIS MIBs")

        # Compile vendor-specific MIBs
        {:ok, cisco_results} = SnmpKit.SnmpMgr.MIB.compile_dir("mibs/cisco/")
        IO.puts("Compiled #\{length(cisco_results)} Cisco MIBs")

        # Load all compiled MIBs
        compiled_files = Path.wildcard("mibs/compiled/*.bin")
        for file <- compiled_files do
          {:ok, _} = SnmpKit.SnmpMgr.MIB.load(file)
          IO.puts("Loaded #\{Path.basename(file)}")
        end

        IO.puts("All MIBs compiled and loaded successfully!")
      end
    end

    MibCompiler.compile_all()
    """

    IO.puts(script)
  end

  def test_mib_system do
    IO.puts("=== Testing MIB Resolution System ===")
    IO.puts("")

    # Test resolution priority
    test_objects = [
      "sysDescr",           # Should resolve via stub
      "ifName",             # Should resolve via stub
      "docsIfCmStatusValue", # Would resolve via compiled MIB (if loaded)
      "1.3.6.1.2.1.1.1"    # Numeric OID (always works, but tested as string)
    ]

    IO.puts("Resolution test (stubs only - DOCSIS MIBs not loaded):")
    for object <- test_objects do
      case SnmpKit.SnmpMgr.MIB.resolve(object) do
        {:ok, oid} ->
          IO.puts("  ✓ #{String.pad_trailing(object, 25)} → #{inspect(oid)}")
        {:error, :not_found} ->
          if String.starts_with?(object, "1.") do
            IO.puts("  ✓ #{String.pad_trailing(object, 25)} → Numeric OID (passthrough)")
          else
            IO.puts("  ✗ #{String.pad_trailing(object, 25)} → Not found (would need compiled MIB)")
          end
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
