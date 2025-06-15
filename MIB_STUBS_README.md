# MIB Stubs for SNMP Operations

This document describes the MIB stub functionality that allows you to use common MIB group names and object names without needing to load full MIB files.

## Overview

The SNMP library includes a built-in registry of common MIB objects and groups that can be referenced by name instead of numeric OIDs. This makes SNMP operations much more user-friendly while still being lightweight.

## Available MIB Group Stubs

### Standard MIB-II Groups

| Group Name | OID | Description |
|------------|-----|-------------|
| `system` | 1.3.6.1.2.1.1 | System description, uptime, contact, etc. |
| `interfaces` | 1.3.6.1.2.1.2 | Standard interface table (same as 'if') |
| `if` | 1.3.6.1.2.1.2 | Standard interface table (MIB-II) |
| `ifX` | 1.3.6.1.2.1.31 | Extended interface table (high-capacity counters) |
| `ip` | 1.3.6.1.2.1.4 | IP layer statistics |
| `icmp` | 1.3.6.1.2.1.5 | ICMP statistics |
| `tcp` | 1.3.6.1.2.1.6 | TCP connection statistics |
| `udp` | 1.3.6.1.2.1.7 | UDP statistics |
| `snmp` | 1.3.6.1.2.1.11 | SNMP agent statistics |

### Root Groups

| Group Name | OID | Description |
|------------|-----|-------------|
| `mib-2` | 1.3.6.1.2.1 | Entire MIB-II tree |
| `mgmt` | 1.3.6.1.2 | Management tree |
| `internet` | 1.3.6.1 | Internet root |
| `enterprises` | 1.3.6.1.4.1 | Enterprise-specific MIBs |

### Enterprise MIBs

| Vendor | Group Name | OID | Description |
|--------|------------|-----|-------------|
| Cisco | `cisco` | 1.3.6.1.4.1.9 | Cisco enterprise MIB |
| HP | `hp` | 1.3.6.1.4.1.11 | HP enterprise MIB |
| 3Com | `3com` | 1.3.6.1.4.1.43 | 3Com enterprise MIB |
| Sun | `sun` | 1.3.6.1.4.1.42 | Sun Microsystems MIB |
| DEC | `dec` | 1.3.6.1.4.1.36 | Digital Equipment Corporation MIB |
| IBM | `ibm` | 1.3.6.1.4.1.2 | IBM enterprise MIB |
| Microsoft | `microsoft` | 1.3.6.1.4.1.311 | Microsoft enterprise MIB |
| NetApp | `netapp` | 1.3.6.1.4.1.789 | NetApp enterprise MIB |
| Juniper | `juniper` | 1.3.6.1.4.1.2636 | Juniper Networks MIB |
| Fortinet | `fortinet` | 1.3.6.1.4.1.12356 | Fortinet enterprise MIB |
| Palo Alto | `paloalto` | 1.3.6.1.4.1.25461 | Palo Alto Networks MIB |
| MikroTik | `mikrotik` | 1.3.6.1.4.1.14988 | MikroTik enterprise MIB |

## Individual Object Names

### System Group Objects

| Object Name | OID | Description |
|-------------|-----|-------------|
| `sysDescr` | 1.3.6.1.2.1.1.1 | System description |
| `sysObjectID` | 1.3.6.1.2.1.1.2 | System object identifier |
| `sysUpTime` | 1.3.6.1.2.1.1.3 | System uptime |
| `sysContact` | 1.3.6.1.2.1.1.4 | System contact |
| `sysName` | 1.3.6.1.2.1.1.5 | System name |
| `sysLocation` | 1.3.6.1.2.1.1.6 | System location |
| `sysServices` | 1.3.6.1.2.1.1.7 | System services |

### Interface Table Objects (Standard)

| Object Name | OID | Description |
|-------------|-----|-------------|
| `ifNumber` | 1.3.6.1.2.1.2.1 | Number of interfaces |
| `ifTable` | 1.3.6.1.2.1.2.2 | Interface table |
| `ifEntry` | 1.3.6.1.2.1.2.2.1 | Interface entry |
| `ifIndex` | 1.3.6.1.2.1.2.2.1.1 | Interface index |
| `ifDescr` | 1.3.6.1.2.1.2.2.1.2 | Interface description |
| `ifType` | 1.3.6.1.2.1.2.2.1.3 | Interface type |
| `ifMtu` | 1.3.6.1.2.1.2.2.1.4 | Interface MTU |
| `ifSpeed` | 1.3.6.1.2.1.2.2.1.5 | Interface speed |
| `ifPhysAddress` | 1.3.6.1.2.1.2.2.1.6 | Interface physical address |
| `ifAdminStatus` | 1.3.6.1.2.1.2.2.1.7 | Interface admin status |
| `ifOperStatus` | 1.3.6.1.2.1.2.2.1.8 | Interface operational status |
| `ifInOctets` | 1.3.6.1.2.1.2.2.1.10 | Input octets |
| `ifOutOctets` | 1.3.6.1.2.1.2.2.1.16 | Output octets |

### Interface Extensions (ifX) Objects

| Object Name | OID | Description |
|-------------|-----|-------------|
| `ifXTable` | 1.3.6.1.2.1.31.1 | Extended interface table |
| `ifName` | 1.3.6.1.2.1.31.1.1.1 | Interface name |
| `ifHCInOctets` | 1.3.6.1.2.1.31.1.1.6 | High-capacity input octets |
| `ifHCOutOctets` | 1.3.6.1.2.1.31.1.1.10 | High-capacity output octets |
| `ifHighSpeed` | 1.3.6.1.2.1.31.1.1.15 | High-speed interface speed |
| `ifAlias` | 1.3.6.1.2.1.31.1.1.18 | Interface alias |

## Usage Examples

### Bulk Walking with Group Names

```elixir
# Get all system information
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "system")

# Get interface table data
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "if")

# Get extended interface data (high-capacity counters)
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "ifX")

# Get just interface names
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "ifName")

# Get SNMP agent statistics
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "snmp")

# Get vendor-specific data (MikroTik example)
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "mikrotik")
```

### Individual Object Queries

```elixir
# Get system description
{:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "sysDescr.0")

# Get system uptime
{:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "sysUpTime.0")

# Get system name
{:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "sysName.0")

# Get interface description for interface 1
{:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "ifDescr.1")

# Get interface name for interface 2 (from ifX table)
{:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "ifName.2")
```

### Multi-Object Queries

```elixir
# Get multiple system objects at once
{:ok, results} = SnmpKit.SnmpLib.Manager.get_multi("192.168.1.1", [
  "sysDescr.0",
  "sysUpTime.0", 
  "sysName.0",
  "sysLocation.0"
])
```

### Using Numeric OIDs (Still Supported)

```elixir
# You can still use numeric OIDs directly
{:ok, results} = SnmpKit.SnmpMgr.bulk_walk_pretty("192.168.1.1", "1.3.6.1.2.1.1")
{:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "1.3.6.1.2.1.1.1.0")
```

## MIB Name Resolution

You can test MIB name resolution directly:

```elixir
# Start IEx with the project
iex -S mix

# Resolve a group name to its OID
iex> SnmpKit.SnmpMgr.MIB.resolve("system")
{:ok, [1, 3, 6, 1, 2, 1, 1]}

# Resolve an object name to its OID
iex> SnmpKit.SnmpMgr.MIB.resolve("sysDescr")
{:ok, [1, 3, 6, 1, 2, 1, 1, 1]}

# Resolve with instance (automatically handled)
iex> SnmpKit.SnmpMgr.MIB.resolve("sysDescr.0")
{:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}
```

## Demo Script

Run the included demo script to see all available stubs:

```bash
# Show all available groups and test them
mix run demo_mib_groups.exs

# Test group name resolution
mix run demo_mib_groups.exs --resolve-test

# Show interface details
mix run demo_mib_groups.exs --interface-details

# Test with a specific host
mix run demo_mib_groups.exs 192.168.1.100
```

## Benefits

1. **User-Friendly**: Use meaningful names instead of numeric OIDs
2. **Lightweight**: No need to load large MIB files for common operations  
3. **Fast**: Built-in mappings are instantly available
4. **Compatible**: Still supports numeric OIDs when needed
5. **Extensible**: Easy to add more mappings as needed

## Implementation Notes

- MIB stubs are defined in `lib/snmpkit/snmp_mgr/mib.ex`
- The `@standard_mibs` module attribute contains all mappings
- Group names automatically resolve to their base OIDs for bulk operations
- Object names can include instance identifiers (e.g., "sysDescr.0")
- The MIB registry is started automatically when needed
- All existing numeric OID functionality remains unchanged

This stub system provides the convenience of symbolic names for common SNMP operations without the complexity and overhead of full MIB parsing and loading.