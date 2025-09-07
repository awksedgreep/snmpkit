# Enriched Output Migration Guide (1.0+)

This guide helps you migrate from legacy return formats to the new enriched varbind maps introduced in 1.0.

Enriched varbind shape per item:

%{
  name: "sysUpTime.0",        # optional (nil if no reverse lookup)
  oid: "1.3.6.1.2.1.1.3.0",   # numeric OID as string
  type: :timeticks,           # Elixir atom describing type
  value: 12345678,            # raw value
  formatted: "1 day, 10 hours, 17 minutes, 36 seconds"  # optional
}

Defaults
- include_names: true
- include_formatted: true

Override per-call
- Pass include_names: false and/or include_formatted: false to any SNMP API call.

Set defaults globally
- SnmpKit.SnmpMgr.Config.set_default_include_names(false)
- SnmpKit.SnmpMgr.Config.set_default_include_formatted(false)

Common migrations

1) get/3
Before:
{:ok, value} = SnmpKit.get(target, oid)
After:
{:ok, %{value: value}} = SnmpKit.get(target, oid)

2) get_next/3
Before:
{:ok, {next_oid, value}} = SnmpKit.get_next(target, oid)
After:
{:ok, %{oid: next_oid, value: value}} = SnmpKit.get_next(target, oid)

3) walk/3 and get_bulk/3
Before:
{:ok, [{oid, type, value}]} = SnmpKit.walk(target, root)
After:
{:ok, [%{oid: oid, type: type, value: value}]} = SnmpKit.walk(target, root)

4) Pretty functions
Before:
{:ok, formatted} = SnmpKit.get_pretty(target, oid)
After:
{:ok, %{formatted: formatted, type: type, value: value}} = SnmpKit.get_pretty(target, oid)

Performance tips
- Turn off name resolution and formatting in hot paths:
{:ok, rows} = SnmpKit.walk(target, root, include_names: false, include_formatted: false)

Notes
- Multi-target APIs preserve their outer structure; the inner items are enriched maps.
- type is always present; formatted is present when include_formatted is true.

