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

# Multiple resolutions
names = ["sysDescr.0", "sysUpTime.0", "sysName.0"]
{:ok, oids} = SnmpKit.MIB.resolve_many(names)

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

# Multiple reverse lookups
oids = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]
{:ok, names} = SnmpKit.MIB.reverse_lookup_many(oids)

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

# Check what MIBs are loaded
{:ok, loaded_mibs} = SnmpKit.MIB.list_loaded()
IO.inspect(loaded_mibs)

# Reload standard MIBs if needed
{:ok, _} = SnmpKit.MIB.reload_standard()
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

{:ok, compiled_mibs} = SnmpKit.MIB.compile_many(mib_files)
{:ok, _} = SnmpKit.MIB.load_many(compiled_mibs)
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
# Load specific standard MIBs
standard_mibs = [
  "BRIDGE-MIB",
  "ENTITY-MIB", 
  "DISMAN-EVENT-MIB",
  "NOTIFICATION-LOG-MIB"
]

for mib <- standard_mibs do
  case SnmpKit.MIB.load_standard(mib) do
    {:ok, _} -> IO.puts("Loaded #{mib}")
    {:error, reason} -> IO.puts("Failed to load #{mib}: #{reason}")
  end
end
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

# Load Cisco MIBs in dependency order
{:ok, _} = SnmpKit.MIB.compile_and_load_many(cisco_mibs)

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

{:ok, _} = SnmpKit.MIB.compile_and_load_many(docsis_mibs)

# DOCSIS-specific operations
{:ok, status} = SnmpKit.SNMP.get("10.1.1.100", "docsIfCmStatusValue.1")
{:ok, signal} = SnmpKit.SNMP.get("10.1.1.100", "docsIfSigQSignalNoise.1")
```

### Creating Custom MIB Definitions

```elixir
# Define custom objects programmatically
custom_objects = [
  %{
    name: "myCustomObject",
    oid: [1, 3, 6, 1, 4, 1, 12345, 1, 1, 1],
    syntax: :integer,
    access: :read_only,
    description: "My custom SNMP object"
  }
]

{:ok, _} = SnmpKit.MIB.define_objects(custom_objects)

# Now the custom object can be resolved
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

# Get siblings
{:ok, siblings} = SnmpKit.MIB.siblings([1, 3, 6, 1, 2, 1, 1, 1, 0])

# Walk the tree from a starting point
{:ok, tree} = SnmpKit.MIB.walk_tree([1, 3, 6, 1, 2, 1, 1])
```

### Querying Object Information

```elixir
# Get detailed object information
{:ok, info} = SnmpKit.MIB.object_info("sysDescr.0")
# Returns: %{name: "sysDescr", oid: [...], syntax: :octet_string, ...}

# Check if an OID exists
true = SnmpKit.MIB.exists?("sysDescr.0")
false = SnmpKit.MIB.exists?("nonExistentObject.0")

# Get object syntax information
{:ok, syntax} = SnmpKit.MIB.get_syntax("sysDescr.0")
# Returns: :octet_string

# Get access level
{:ok, access} = SnmpKit.MIB.get_access("sysDescr.0") 
# Returns: :read_only
```

## Advanced Features

### MIB Validation

```elixir
# Validate MIB files before compilation
case SnmpKit.MIB.validate("MY-MIB.mib") do
  {:ok, _} -> IO.puts("MIB is valid")
  {:error, {:validation_failed, errors}} ->
    IO.puts("MIB validation failed:")
    for error <- errors, do: IO.puts("  #{error}")
end

# Validate loaded MIB consistency
{:ok, report} = SnmpKit.MIB.validate_loaded()
if report.inconsistencies != [] do
  IO.puts "Found inconsistencies:"
  for issue <- report.inconsistencies, do: IO.puts("  #{issue}")
end
```

### MIB Caching and Performance

```elixir
# Enable aggressive caching for better performance
SnmpKit.MIB.configure_cache(
  size: 10_000,
  ttl: :infinity,
  strategy: :lru
)

# Preload commonly used OIDs
common_oids = [
  "sysDescr.0", "sysUpTime.0", "sysName.0",
  "ifInOctets", "ifOutOctets", "ifOperStatus"
]

{:ok, _} = SnmpKit.MIB.preload(common_oids)

# Get cache statistics
{:ok, stats} = SnmpKit.MIB.cache_stats()
IO.inspect(stats)
```

### Bulk OID Operations

```elixir
# Resolve many OIDs efficiently
oids_to_resolve = [
  "sysDescr.0", "sysUpTime.0", "sysName.0",
  "ifInOctets.1", "ifOutOctets.1", "ifOperStatus.1"
]

{:ok, resolved} = SnmpKit.MIB.resolve_many(oids_to_resolve)

# Reverse lookup many OIDs
numeric_oids = [
  [1, 3, 6, 1, 2, 1, 1, 1, 0],
  [1, 3, 6, 1, 2, 1, 1, 3, 0],
  [1, 3, 6, 1, 2, 1, 1, 5, 0]
]

{:ok, names} = SnmpKit.MIB.reverse_lookup_many(numeric_oids)
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
  {:error, :not_found} ->
    # Try partial matches
    case SnmpKit.MIB.search("unknownOid") do
      {:ok, matches} ->
        IO.puts("Did you mean one of these?")
        for match <- matches, do: IO.puts("  #{match}")
      {:error, :no_matches} ->
        IO.puts("No similar OIDs found")
    end
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
2. **Use preloading** - Preload commonly used OIDs for better performance  
3. **Cache aggressively** - Enable caching for production deployments
4. **Validate before loading** - Always validate MIBs before compilation
5. **Handle errors gracefully** - Always pattern match on MIB operation results
6. **Use bulk operations** - Resolve multiple OIDs at once when possible

### Getting Help

```elixir
# Get help on available MIB functions
h SnmpKit.MIB

# List all loaded MIBs
{:ok, mibs} = SnmpKit.MIB.list_loaded()
IO.inspect(mibs)

# Get detailed system information
{:ok, info} = SnmpKit.MIB.system_info()
IO.inspect(info)
```

For more examples and advanced usage, see the [API documentation](https://hexdocs.pm/snmpkit/SnmpKit.MIB.html).