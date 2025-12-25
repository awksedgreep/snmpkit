# MIB Guide - SnmpKit

This guide covers working with Management Information Bases (MIBs) in SnmpKit, including OID resolution, MIB compilation, and custom MIB integration.

## Table of Contents

- [Overview](#overview)
- [Basic MIB Operations](#basic-mib-operations)
- [OID Resolution](#oid-resolution)
- [MIB Compilation](#mib-compilation)
- [Standard MIBs](#standard-mibs)
- [Custom MIBs](#custom-mibs)
- [Tree Navigation](#tree-navigation)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)

## Overview

Management Information Bases (MIBs) define the structure of manageable objects in SNMP. SnmpKit provides comprehensive MIB support through the `SnmpKit.MIB` module, allowing you to:

- Resolve OID names to numeric identifiers
- Perform reverse lookups from OIDs to names
- Compile and load custom MIBs
- Navigate the MIB tree structure
- Query object definitions and metadata

## Basic MIB Operations

### OID Name Resolution

Convert human-readable names to numeric OIDs:

```elixir
# Simple name resolution
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
# Returns: [1, 3, 6, 1, 2, 1, 1, 1, 0]

# Multiple resolutions (resolve each individually)
names = ["sysDescr.0", "sysUpTime.0", "sysName.0"]
oids = Enum.map(names, &SnmpKit.MIB.resolve/1)

# Partial name resolution
{:ok, oid} = SnmpKit.MIB.resolve("system.sysDescr.0")
{:ok, oid} = SnmpKit.MIB.resolve("1.3.6.1.2.1.1.1.0")
```

### Reverse OID Lookup

Convert numeric OIDs back to readable names:

```elixir
# Basic reverse lookup
{:ok, name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
# Returns: "sysDescr.0"

# Multiple reverse lookups (lookup each individually)
oids = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]
names = Enum.map(oids, &SnmpKit.MIB.reverse_lookup/1)

# Get the longest matching name
{:ok, partial_name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 5])
# Returns closest match even if exact OID doesn't exist
```

## OID Resolution

### Working with Different OID Formats

SnmpKit supports multiple OID input formats:

```elixir
# String format
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")

# Dotted decimal string
{:ok, oid} = SnmpKit.MIB.resolve("1.3.6.1.2.1.1.1.0")

# Mixed format
{:ok, oid} = SnmpKit.MIB.resolve("iso.org.dod.internet.mgmt.mib-2.system.sysDescr.0")

# List format (already resolved)
{:ok, oid} = SnmpKit.MIB.resolve([1, 3, 6, 1, 2, 1, 1, 1, 0])
```

### Common System OIDs

```elixir
# System group OIDs
system_oids = %{
  "sysDescr.0" => [1, 3, 6, 1, 2, 1, 1, 1, 0],
  "sysObjectID.0" => [1, 3, 6, 1, 2, 1, 1, 2, 0],
  "sysUpTime.0" => [1, 3, 6, 1, 2, 1, 1, 3, 0],
  "sysContact.0" => [1, 3, 6, 1, 2, 1, 1, 4, 0],
  "sysName.0" => [1, 3, 6, 1, 2, 1, 1, 5, 0],
  "sysLocation.0" => [1, 3, 6, 1, 2, 1, 1, 6, 0],
  "sysServices.0" => [1, 3, 6, 1, 2, 1, 1, 7, 0]
}

# Verify all resolve correctly
for {name, expected_oid} <- system_oids do
  {:ok, ^expected_oid} = SnmpKit.MIB.resolve(name)
end
```

## MIB Compilation

### Loading Standard MIBs

SnmpKit comes with standard MIBs pre-compiled:

```elixir
# Standard MIBs are loaded automatically
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")  # Works immediately

# Load standard MIBs explicitly if needed
:ok = SnmpKit.MIB.load_standard_mibs()
```

### Compiling Custom MIBs

#### High-Level Compilation

For most use cases, use the high-level compilation API:

```elixir
# Compile a single MIB file
{:ok, compiled} = SnmpKit.MIB.compile("path/to/MY-CUSTOM-MIB.mib")
{:ok, _} = SnmpKit.MIB.load(compiled)

# Compile multiple MIBs with dependencies
mib_files = [
  "CISCO-SMI.mib",
  "CISCO-TC.mib",
  "CISCO-CABLE-MODEM-MIB.mib"
]

# Use compile_all for batch compilation
{:ok, compiled_mibs} = SnmpKit.MIB.compile_all(mib_files)
# Load each compiled MIB
Enum.each(compiled_mibs, fn {_file, {:ok, path}} -> SnmpKit.MIB.load(path) end)
```

#### Low-Level Compilation

For advanced control over the compilation process:

```elixir
# Use the low-level compiler directly
alias SnmpKit.MibCompiler

# Configure compilation options
options = [
  output_dir: "priv/compiled_mibs",
  include_dirs: ["priv/mibs", "/usr/share/snmp/mibs"],
  warnings_as_errors: false,
  verbose: true
]

# Compile with options
{:ok, result} = MibCompiler.compile_file("MY-MIB.mib", options)

# Handle compilation errors
case MibCompiler.compile_file("BROKEN-MIB.mib", options) do
  {:ok, result} -> 
    IO.puts("Compilation successful")
  {:error, {:compilation_failed, errors}} ->
    IO.puts("Compilation failed:")
    for error <- errors, do: IO.puts("  #{error}")
end
```

## Standard MIBs

### Commonly Used Standard MIBs

```elixir
# RFC1213-MIB (MIB-II) - Basic system information
{:ok, _} = SnmpKit.MIB.resolve("sysDescr.0")
{:ok, _} = SnmpKit.MIB.resolve("ifTable")
{:ok, _} = SnmpKit.MIB.resolve("ipAddrTable")

# IF-MIB - Interface information  
{:ok, _} = SnmpKit.MIB.resolve("ifXTable")
{:ok, _} = SnmpKit.MIB.resolve("ifHCInOctets.1")

# HOST-RESOURCES-MIB - System resources
{:ok, _} = SnmpKit.MIB.resolve("hrSystemUptime.0")
{:ok, _} = SnmpKit.MIB.resolve("hrMemorySize.0")

# SNMPv2-MIB - SNMP statistics
{:ok, _} = SnmpKit.MIB.resolve("snmpInPkts.0")
{:ok, _} = SnmpKit.MIB.resolve("snmpOutPkts.0")
```

### Loading Additional Standard MIBs

```elixir
# Load standard MIBs that are built into the library
:ok = SnmpKit.MIB.load_standard_mibs()

# For additional MIBs, compile and load them individually
{:ok, compiled} = SnmpKit.MIB.compile("path/to/BRIDGE-MIB.mib")
{:ok, _} = SnmpKit.MIB.load(compiled)
```

## Custom MIBs

### Enterprise MIBs

Many vendors provide their own MIBs for device-specific objects:

```elixir
# Cisco MIBs
cisco_mibs = [
  "CISCO-SMI.mib",
  "CISCO-TC.mib",
  "CISCO-CABLE-MODEM-MIB.mib",
  "CISCO-DOCS-EXT-MIB.mib"
]

# Compile and load Cisco MIBs in dependency order
for mib <- cisco_mibs do
  {:ok, compiled} = SnmpKit.MIB.compile(mib)
  {:ok, _} = SnmpKit.MIB.load(compiled)
end

# Now Cisco-specific OIDs work
{:ok, oid} = SnmpKit.MIB.resolve("cdxCmtsCmStatusValue")
```

### DOCSIS MIBs

For cable modem and CMTS management:

```elixir
# DOCSIS MIBs
docsis_mibs = [
  "DOCS-CABLE-DEVICE-MIB.mib",
  "DOCS-IF-MIB.mib", 
  "DOCS-QOS-MIB.mib",
  "DOCS-SUBMGT-MIB.mib"
]

# Compile and load each MIB in order
for mib <- docsis_mibs do
  {:ok, compiled} = SnmpKit.MIB.compile(mib)
  {:ok, _} = SnmpKit.MIB.load(compiled)
end

# DOCSIS-specific operations
{:ok, status} = SnmpKit.SNMP.get("10.1.1.100", "docsIfCmStatusValue.1")
{:ok, signal} = SnmpKit.SNMP.get("10.1.1.100", "docsIfSigQSignalNoise.1")
```

### Loading Custom MIB Data

Custom MIB definitions can be loaded by compiling and integrating MIB files:

```elixir
# Compile and integrate a custom MIB file
{:ok, _} = SnmpKit.MIB.load_and_integrate_mib("path/to/MY-CUSTOM-MIB.mib")

# Now the custom objects can be resolved
{:ok, oid} = SnmpKit.MIB.resolve("myCustomObject.0")
```

## Tree Navigation

### Exploring the MIB Tree

```elixir
# Get children of a node
{:ok, children} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])
# Returns list of child OIDs under system group

# Get parent of a node
{:ok, parent} = SnmpKit.MIB.parent([1, 3, 6, 1, 2, 1, 1, 1, 0])
# Returns: [1, 3, 6, 1, 2, 1, 1, 1]

# Walk the tree from a starting point
{:ok, tree} = SnmpKit.MIB.walk_tree([1, 3, 6, 1, 2, 1, 1])
```

### Querying Object Information

```elixir
# Get detailed object information using object_info
# Available via SnmpKit.SnmpMgr.MIB.object_info/1
{:ok, info} = SnmpKit.SnmpMgr.MIB.object_info("sysDescr.0")
# Returns: %{name: "sysDescr", oid: [...], syntax: %{base: :octet_string, ...}, ...}

# Check if an OID can be resolved
case SnmpKit.MIB.resolve("sysDescr.0") do
  {:ok, _oid} -> IO.puts("OID exists")
  {:error, :not_found} -> IO.puts("OID not found")
end
```

## Advanced Features

### MIB Parsing and Analysis

```elixir
# Parse a MIB file to extract object definitions
{:ok, parsed} = SnmpKit.MIB.parse_mib_file("MY-MIB.mib")
IO.inspect(parsed.parsed_objects)

# Parse MIB content from a string
{:ok, parsed} = SnmpKit.MIB.parse_mib_content(mib_content_string)
```

### Enhanced Resolution

```elixir
# Use enhanced resolution that includes loaded MIB data
{:ok, oid} = SnmpKit.MIB.resolve_enhanced("customObject.0")
```

### Bulk OID Operations

```elixir
# Resolve many OIDs using Enum.map
oids_to_resolve = [
  "sysDescr.0", "sysUpTime.0", "sysName.0",
  "ifInOctets.1", "ifOutOctets.1", "ifOperStatus.1"
]

resolved = Enum.map(oids_to_resolve, &SnmpKit.MIB.resolve/1)

# Reverse lookup many OIDs
numeric_oids = [
  [1, 3, 6, 1, 2, 1, 1, 1, 0],
  [1, 3, 6, 1, 2, 1, 1, 3, 0],
  [1, 3, 6, 1, 2, 1, 1, 5, 0]
]

names = Enum.map(numeric_oids, &SnmpKit.MIB.reverse_lookup/1)
```

## Troubleshooting

### Common Issues

#### MIB Compilation Failures

```elixir
# Debug compilation issues
case SnmpKit.MIB.compile("problematic.mib", debug: true) do
  {:error, {:compilation_failed, errors}} ->
    IO.puts("Compilation errors:")
    for {line, message} <- errors do
      IO.puts("Line #{line}: #{message}")
    end
  {:error, {:missing_dependencies, deps}} ->
    IO.puts("Missing dependencies: #{Enum.join(deps, ", ")}")
    IO.puts("Load these MIBs first")
end
```

#### OID Resolution Problems

```elixir
# Debug OID resolution
case SnmpKit.MIB.resolve("unknownOid.0") do
  {:ok, oid} ->
    IO.puts("Resolved to: #{inspect(oid)}")
  {:error, :not_found} ->
    IO.puts("OID not found - check MIB is loaded")
  {:error, :invalid_name} ->
    IO.puts("Invalid OID name format")
end
```

#### Performance Issues

```elixir
# Profile MIB operations
{time, {:ok, result}} = :timer.tc(fn ->
  SnmpKit.MIB.resolve("complexOid.withManyParts.0")
end)

IO.puts("Resolution took #{time}μs")

# Enable verbose logging for debugging
Logger.configure(level: :debug)
SnmpKit.MIB.resolve("sysDescr.0")  # Will show detailed logs
```

### Best Practices

1. **Load MIBs in dependency order** - Load base MIBs before dependent ones
2. **Handle errors gracefully** - Always pattern match on MIB operation results
3. **Use bulk operations** - Resolve multiple OIDs at once using Enum.map when possible
4. **Integrate MIBs properly** - Use load_and_integrate_mib for full MIB support

### Getting Help

```elixir
# Get help on available MIB functions
h SnmpKit.MIB

# Load standard MIBs
:ok = SnmpKit.MIB.load_standard_mibs()

# Test resolution
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
IO.inspect(oid)
```

For more examples and advanced usage, see the [API documentation](https://hexdocs.pm/snmpkit/SnmpKit.MIB.html).