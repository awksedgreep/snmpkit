# MIB Integration Guide: Stubs + Compilation

This guide explains how SnmpKit's MIB stub system integrates with full MIB compilation to provide comprehensive SNMP management capabilities.

## Overview

SnmpKit provides two complementary MIB systems:

1. **Built-in MIB Stubs** - Immediate access to common MIB-II objects
2. **Full MIB Compilation** - Complete support for specialized and vendor-specific MIBs

These systems work together seamlessly, providing the convenience of stubs for common operations while enabling full MIB compilation for specialized protocols like DOCSIS, vendor-specific MIBs, or custom applications.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SNMP Operations                          │
│  (get, get_multi, bulk_walk_pretty, etc.)                  │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│                 MIB Resolution Engine                       │
│                                                             │
│  1. Try compiled MIBs first (dynamic, loaded at runtime)   │
│  2. Fall back to built-in stubs (static, always available) │
│  3. Pass through numeric OIDs (always supported)           │
└─────────────────┬───────────────────────────────────────────┘
                  │
         ┌────────┴────────┐
         │                 │
┌────────▼─────────┐ ┌─────▼──────────┐
│  Compiled MIBs   │ │  Built-in      │
│                  │ │  Stubs         │
│ • DOCSIS MIBs    │ │                │
│ • Vendor MIBs    │ │ • system       │
│ • Custom MIBs    │ │ • if/ifX       │
│ • Enterprise     │ │ • ip/tcp/udp   │
│   Extensions     │ │ • snmp         │
│                  │ │ • Enterprise   │
│ (Loaded from     │ │   roots        │
│  .mib files)     │ │                │
└──────────────────┘ │ (Always        │
                     │  available)    │
                     └────────────────┘
```

## Resolution Priority

When you use a symbolic name in an SNMP operation, the resolution follows this priority:

1. **Compiled MIBs** - Check dynamically loaded MIB objects first
2. **Built-in Stubs** - Fall back to predefined common objects
3. **Numeric OIDs** - Pass through numeric strings directly
4. **Error** - Return `:not_found` if none of the above match

## Built-in Stub Coverage

### Standard MIB-II Groups (Always Available)
- `system` - System information (sysDescr, sysUpTime, etc.)
- `if` - Standard interface table (ifDescr, ifOperStatus, etc.)
- `ifX` - Extended interface table (ifName, ifHCInOctets, etc.)
- `ip`, `icmp`, `tcp`, `udp` - Protocol statistics
- `snmp` - SNMP agent statistics

### Enterprise Root OIDs (Always Available)
- `enterprises` - Root of enterprise tree (1.3.6.1.4.1)
- `cisco`, `hp`, `ibm`, `microsoft` - Major vendors
- `cablelabs`, `docsis`, `arris`, `motorola` - Cable/DOCSIS industry
- `mikrotik`, `juniper`, `fortinet` - Network equipment vendors

### Individual Objects (60+ objects available)
- All system group objects (`sysDescr`, `sysUpTime`, etc.)
- All standard interface objects (`ifDescr`, `ifOperStatus`, etc.)
- All extended interface objects (`ifName`, `ifAlias`, etc.)

## When to Use Each System

### Use Built-in Stubs For:
- **Standard network monitoring** - Interface statistics, system info
- **Common SNMP operations** - Basic device discovery and monitoring
- **Quick prototyping** - No setup required, works immediately
- **Cross-platform compatibility** - Same code works everywhere

### Use Full MIB Compilation For:
- **Specialized protocols** - DOCSIS, Frame Relay, ATM, etc.
- **Vendor-specific features** - Cisco VLAN management, HP server monitoring
- **Custom applications** - Your own MIB definitions
- **Complete object coverage** - Access to all objects in a MIB

## Integration Examples

### Example 1: Mixed Queries
```elixir
# Query combining stubs and compiled MIBs
{:ok, results} = SnmpKit.SnmpLib.Manager.get_multi("192.168.1.100", [
  "sysDescr.0",                    # Built-in stub
  "sysUpTime.0",                   # Built-in stub
  "ifName.1",                      # Built-in stub
  "docsIfCmStatusValue.0",         # Compiled DOCSIS MIB
  "ciscoVlanPortVlan.1.5",         # Compiled Cisco MIB
  "1.3.6.1.4.1.9.2.1.1.0"        # Numeric OID (always works)
])
```

### Example 2: Bulk Walking with Automatic Resolution
```elixir
# Standard interface data (uses stubs)
{:ok, if_results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "if")

# Extended interface data (uses stubs)
{:ok, ifx_results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "ifX")

# DOCSIS cable modem data (uses compiled MIB if loaded)
{:ok, docsis_results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "docsIfCmTable")

# Cisco VLAN data (uses compiled MIB if loaded)
{:ok, vlan_results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "ciscoVlanTable")
```

### Example 3: Progressive Enhancement
```elixir
# Start with basic monitoring using stubs
defmodule BasicMonitoring do
  def get_device_info(host) do
    {:ok, results} = SnmpKit.SnmpLib.Manager.get_multi(host, [
      "sysDescr.0",
      "sysUpTime.0",
      "sysName.0"
    ])
    results
  end
  
  def get_interface_stats(host) do
    {:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "if")
    results
  end
end

# Enhance with specialized monitoring after loading MIBs
defmodule EnhancedMonitoring do
  def setup do
    # Load specialized MIBs
    {:ok, _} = SnmpKit.SnmpMgr.MIB.load_and_integrate_mib("mibs/CISCO-VLAN-MIB.mib")
    {:ok, _} = SnmpKit.SnmpMgr.MIB.load_and_integrate_mib("mibs/DOCS-IF-MIB.mib")
  end
  
  def get_cisco_vlans(host) do
    # This now works because we loaded the Cisco VLAN MIB
    {:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "ciscoVlanTable")
    results
  end
  
  def get_docsis_status(host) do
    # This now works because we loaded the DOCSIS MIB
    {:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "docsIfCmTable")
    results
  end
end
```

## DOCSIS Example Workflow

### Step 1: Basic Device Discovery (Stubs Only)
```elixir
# Works immediately, no MIB compilation needed
{:ok, system_info} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "system")
{:ok, interfaces} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "if")

# Can access DOCSIS enterprise root (stub available)
{:ok, cablelabs_oid} = SnmpKit.SnmpMgr.MIB.resolve("cablelabs")  # [1,3,6,1,4,1,4491]
```

### Step 2: Compile DOCSIS MIBs
```elixir
# Download DOCSIS MIB files from CableLabs
# Place in mibs/docsis/ directory

# Compile all DOCSIS MIBs
{:ok, results} = SnmpKit.SnmpMgr.MIB.compile_dir("mibs/docsis/")

# Load compiled MIBs
for result <- results do
  {:ok, _} = SnmpKit.SnmpMgr.MIB.load(result.compiled_path)
end
```

### Step 3: Enhanced DOCSIS Monitoring
```elixir
# Now DOCSIS-specific objects are available
{:ok, cm_status} = SnmpKit.SnmpLib.Manager.get("192.168.1.100", "docsIfCmStatusValue.0")
{:ok, signal_quality} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "docsIfSigQTable")
{:ok, channel_info} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.100", "docsIfDownChannelTable")

# Mix DOCSIS objects with standard objects
{:ok, full_status} = SnmpKit.SnmpLib.Manager.get_multi("192.168.1.100", [
  "sysDescr.0",              # Stub
  "sysUpTime.0",             # Stub
  "ifOperStatus.2",          # Stub
  "docsIfCmStatusValue.0",   # Compiled MIB
  "docsIfCmStatusResets.0"   # Compiled MIB
])
```

## MIB Compilation API Reference

### Compiling MIBs
```elixir
# Compile a single MIB file
{:ok, compiled_path} = SnmpKit.SnmpMgr.MIB.compile("path/to/DOCS-IF-MIB.mib")

# Compile all MIBs in a directory
{:ok, results} = SnmpKit.SnmpMgr.MIB.compile_dir("mibs/docsis/")

# Compile with options
{:ok, compiled_path} = SnmpKit.SnmpMgr.MIB.compile("CUSTOM-MIB.mib", [
  output_dir: "compiled_mibs/",
  include_dirs: ["mibs/deps/"]
])
```

### Loading MIBs
```elixir
# Load a compiled MIB
{:ok, mib_data} = SnmpKit.SnmpMgr.MIB.load("compiled_mibs/DOCS-IF-MIB.bin")

# Parse and integrate in one step
{:ok, _} = SnmpKit.SnmpMgr.MIB.load_and_integrate_mib("mibs/DOCS-IF-MIB.mib")

# Load standard MIBs (built into library)
{:ok, _} = SnmpKit.SnmpMgr.MIB.load_standard_mibs()
```

### Parsing MIBs
```elixir
# Parse MIB file content
{:ok, parsed_data} = SnmpKit.SnmpMgr.MIB.parse_mib_file("CUSTOM-MIB.mib")

# Parse MIB content directly
{:ok, parsed_data} = SnmpKit.SnmpMgr.MIB.parse_mib_content(mib_content_string)
```

## Resolution Testing

You can test which system resolves a name:

```elixir
# Test name resolution
test_names = [
  "sysDescr",              # Should resolve via stub
  "ifName",                # Should resolve via stub  
  "docsIfCmStatusValue",   # Resolves via compiled MIB (if loaded)
  "customObject",          # Resolves via compiled MIB (if loaded)
  "1.3.6.1.2.1.1.1"      # Numeric OID (passthrough)
]

for name <- test_names do
  case SnmpKit.SnmpMgr.MIB.resolve(name) do
    {:ok, oid} ->
      IO.puts("✓ #{name} → #{inspect(oid)}")
    {:error, :not_found} ->
      IO.puts("✗ #{name} → Not found")
  end
end
```

## Best Practices

### Development Workflow
1. **Start with stubs** - Use built-in stubs for initial development
2. **Identify gaps** - Note which specialized objects you need
3. **Compile MIBs** - Add MIB compilation for specialized needs
4. **Test integration** - Verify both systems work together
5. **Deploy incrementally** - Stubs work everywhere, MIBs add features

### Performance Considerations
- **Stubs are faster** - No file I/O, immediate resolution
- **Compiled MIBs have overhead** - Parsing and loading time
- **Cache compiled MIBs** - Load once, use many times
- **Use stubs for common operations** - Reserve compilation for specialized needs

### Deployment Strategy
```elixir
# Production deployment approach
defmodule SNMPManager do
  def start do
    # Built-in stubs are always available
    IO.puts("Basic SNMP capabilities ready")
    
    # Load specialized MIBs if available
    case load_optional_mibs() do
      :ok -> IO.puts("Enhanced SNMP capabilities loaded")
      :error -> IO.puts("Running with basic capabilities only")
    end
  end
  
  defp load_optional_mibs do
    mibs_to_load = [
      "compiled/DOCS-IF-MIB.bin",
      "compiled/CISCO-VLAN-MIB.bin",
      "compiled/CUSTOM-APP-MIB.bin"
    ]
    
    Enum.reduce_while(mibs_to_load, :ok, fn mib, _acc ->
      case SnmpKit.SnmpMgr.MIB.load(mib) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, :error}
      end
    end)
  end
end
```

## Troubleshooting

### Common Issues

**Q: My compiled MIB object isn't resolving**
```elixir
# Check if MIB is loaded
case SnmpKit.SnmpMgr.MIB.resolve("myCustomObject") do
  {:ok, oid} -> IO.puts("Object found: #{inspect(oid)}")
  {:error, :not_found} -> IO.puts("MIB not loaded or object doesn't exist")
end
```

**Q: I want to see what MIBs are loaded**
```elixir
# This functionality would need to be added to the MIB module
# For now, keep track of loaded MIBs in your application
```

**Q: Stub resolution conflicts with compiled MIB**
- Compiled MIBs take priority over stubs
- If you need stub behavior, use numeric OIDs directly

**Q: MIB compilation fails**
- Check MIB file syntax and dependencies
- Ensure required MIB dependencies are available
- Use proper file paths and permissions

## Migration Path

### From Numeric OIDs to Symbolic Names
```elixir
# Before: Using numeric OIDs
{:ok, value} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "1.3.6.1.2.1.1.1.0")

# After: Using stubs (no setup required)
{:ok, value} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "sysDescr.0")

# Advanced: Using compiled MIBs (after loading)
{:ok, value} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "docsIfCmStatusValue.0")
```

### From Basic to Enhanced Monitoring
```elixir
# Phase 1: Basic monitoring with stubs
defmodule Phase1 do
  def monitor_device(host) do
    {:ok, basic_info} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "system")
    {:ok, interfaces} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "if")
    {basic_info, interfaces}
  end
end

# Phase 2: Enhanced monitoring with compiled MIBs
defmodule Phase2 do
  def monitor_device(host) do
    # Basic info (still uses stubs)
    {:ok, basic_info} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "system")
    {:ok, interfaces} = SnmpKit.SnmpMgr.bulk_walk_pretty(host, "ifX")  # Enhanced interface data
    
    # Specialized monitoring (uses compiled MIBs)
    specialized_data = case detect_device_type(basic_info) do
      :docsis_modem -> get_docsis_data(host)
      :cisco_switch -> get_cisco_data(host)
      :generic -> %{}
    end
    
    {basic_info, interfaces, specialized_data}
  end
end
```

This integration provides the best of both worlds: immediate functionality through stubs and unlimited extensibility through MIB compilation.