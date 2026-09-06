# MIB Guide

SnmpKit ships its own MIB toolchain: a tokenizer and yecc grammar ported from
OTP's `snmpc`, an Elixir parser and compiler, and a registry that maps names
to OIDs. This guide covers resolving names, compiling and loading MIBs, and
what to expect from vendor files.

## Built-in objects

The registry starts with the common IETF MIBs already loaded, so these work
without compiling anything:

| Group | OID | Contents |
|-------|-----|----------|
| system | 1.3.6.1.2.1.1 | sysDescr ... sysServices |
| interfaces | 1.3.6.1.2.1.2 | ifTable and ifXTable columns |
| ip | 1.3.6.1.2.1.4 | ip statistics, ipAddrTable, ipRouteTable, ipNetToMediaTable |
| tcp, udp | 1.3.6.1.2.1.6 / .7 | statistics and connection tables |
| snmp | 1.3.6.1.2.1.11 | SNMP statistics |
| host | 1.3.6.1.2.1.25 | host resources: storage, device, processor, software tables |
| docsis | 1.3.6.1.2.1.10.127 | DOCSIS IF-MIB: channels, signal quality, CM status |

## Resolving names

```elixir
{:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = SnmpKit.MIB.resolve("sysDescr.0")
{:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = SnmpKit.MIB.resolve("sysDescr")
{:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 3]} = SnmpKit.MIB.resolve("ifInOctets.3")
{:ok, [1, 3, 6, 1, 2, 1]} = SnmpKit.MIB.resolve("mib-2")
```

Accepted input is an object name with an optional instance suffix. Dotted
module paths (`iso.org.dod...`) and OID lists are not accepted; SNMP calls
take numeric OID strings and lists directly, so there is no need to resolve
them.

| Error | Meaning |
|-------|---------|
| `{:error, :not_found}` | no object by that name in the registry |
| `{:error, :invalid_instance}` | the part after the first dot is not numeric |
| `{:error, :invalid_name}` | the argument is not a string |

### Reverse lookup

```elixir
{:ok, "sysDescr.0"} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
{:ok, "sysDescr.0"} = SnmpKit.MIB.reverse_lookup("1.3.6.1.2.1.1.1.0")
{:ok, "sysDescr.999"} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 999])
```

The longest known prefix is named and the remaining sub-identifiers are
appended as the instance.

### Tree navigation and metadata

```elixir
{:ok, names} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])      # ["sysContact", "sysDescr", ...]
{:ok, parent} = SnmpKit.MIB.parent([1, 3, 6, 1, 2, 1, 1, 1, 0])  # [1, 3, 6, 1, 2, 1, 1, 1]
{:ok, entries} = SnmpKit.MIB.walk_tree([1, 3, 6, 1, 2, 1, 1])    # [{"system", [...]}, {"sysDescr", [...]}, ...]

{:ok, %{name: "sysDescr", module: "SNMPv2-MIB", oid: [1, 3, 6, 1, 2, 1, 1, 1],
        syntax: %{base: :octet_string, textual_convention: "DisplayString", display_hint: "255a"}}} =
  SnmpKit.MIB.resolve_enhanced("sysDescr")
```

## Compiling and loading MIBs

```elixir
{:ok, compiled} = SnmpKit.MIB.compile("priv/mibs/MY-ENTERPRISE-MIB.mib")
:ok = SnmpKit.MIB.load(compiled)
{:ok, oid} = SnmpKit.MIB.resolve("myEnterpriseObject.0")
```

`compile/2` returns a compiled MIB map:

| Key | Contents |
|-----|----------|
| `name`, `version` | module name, `:v1_mib` or `:v2_mib` |
| `symbols` | `%{"objectName" => definition}` for every definition |
| `dependencies` | modules named in `IMPORTS` |
| `warnings` | `[{line, message}]`, see below |

`load/1` also accepts the path of a MIB written with `:format :binary`
(`SnmpKit.MIB.Compiler.compile/2` with `output_dir:`).

Batches:

```elixir
{:ok, compiled_list} = SnmpKit.MIB.compile_all(["A-MIB.mib", "B-MIB.mib"])
{:ok, compiled_list} = SnmpKit.MIB.compile_dir("priv/mibs")
Enum.each(compiled_list, &SnmpKit.MIB.load/1)

# compile, parse and register in one step
:ok = SnmpKit.MIB.load_and_integrate_mib("priv/mibs/MY-ENTERPRISE-MIB.mib")
```

Load base modules before the modules that import from them, the same order
`smilint` or `snmptranslate` would need.

### Compiler options

`SnmpKit.MIB.Compiler.compile/2` (also reachable as
`SnmpKit.MIB.compile_raw/2`) accepts:

| Option | Default | Effect |
|--------|---------|--------|
| `output_dir:` | `"./priv/mibs"` | where `:binary` output is written |
| `format:` | `:binary` | output format |
| `validate:` | `true` | run post-compile validation |
| `include_paths:` | `[]` | directories searched for imported modules |
| `warnings_as_errors:` | `false` | turn parser warnings into compilation errors |

### Errors

```elixir
case SnmpKit.MIB.compile("BROKEN-MIB.mib") do
  {:ok, compiled} ->
    compiled

  {:error, {:snmp_lib_compilation_failed, errors}} ->
    for %SnmpKit.MIB.Error{type: type, message: message, line: line} <- errors do
      IO.puts("#{type} at line #{line}: #{message}")
    end
end
```

A missing file, an unreadable file and a syntax error all arrive in that
shape. Syntax errors carry the line and the token the grammar stopped on.

### Warnings

The parser accepts, with a warning, constructs that appear in shipped vendor
MIBs and that net-snmp loads:

| Warning | What happens |
|---------|--------------|
| identifier contains an underscore or ends in a hyphen | kept |
| hex string with an odd digit count, binary string not a multiple of 8 bits | kept |
| enumeration on `Integer32` / `Unsigned32` | treated as `INTEGER` |
| enumeration label starting with an uppercase letter | kept |
| `MAX-ACCESS write-only` in SMIv2 | kept |
| `UNITS` on an SMIv1 (`ACCESS`) object | kept |
| impossible `LAST-UPDATED` / `REVISION` date | kept |
| file is not valid UTF-8 | decoded as Latin-1 |

`compiled.warnings` lists them as `{line, message}`; pass
`warnings_as_errors: true` to reject such files. The parser is cross-checked
against libsmi and net-snmp over 185 fixture MIBs; see
[mib-parser-oracle.md](mib-parser-oracle.md).

## What loading a MIB changes

Once a MIB is loaded, its object names resolve, `reverse_lookup/1` names
their OIDs, and the formatter uses its metadata: INTEGER enumerations become
labels, textual conventions with a DISPLAY-HINT (`d-1`, `1x:`, DateAndTime)
render accordingly, and `object_info/1` reports the syntax, textual
convention, hint and enumerations. The same tables exist for the built-in
objects (`SnmpKit.MIB.Builtin.enumerations/1`), which is why `ifOperStatus`
formats as `"up"` without loading anything.

## Checking a MIB

`SnmpKit.MIB.Lint` reports what the parser cannot: OIDs whose parent is not
defined, imported or known; duplicate names and OIDs; SYNTAX naming an
undefined type; SMIv1 `ACCESS`/`mandatory` inside an SMIv2 module; rows
without INDEX or AUGMENTS; index strings without a SIZE; SEQUENCE fields that
do not match the columns; notifications and groups listing undefined objects.

```elixir
{:ok, report} = SnmpKit.MIB.Lint.check("priv/mibs/VENDOR-MIB.mib", context: [vendor_smi])
report.errors                       # 0
Enum.map(report.findings, &SnmpKit.MIB.Lint.format/1)
# ["42: warning: [index_without_size] index object `vendorKey' of row `vendorEntry' has no SIZE restriction"]
```

Imports from modules that are not available are warnings, not errors; pass
the compiled modules in `context:` (or `--context PATH` on the command
line) to resolve them. `mix snmpkit.mib.lint PATH... [--strict]` prints the
findings and exits non-zero on errors, or on warnings with `--strict`.

## Parsing without loading

```elixir
{:ok, %{parsed_objects: objects, tokens: tokens}} = SnmpKit.MIB.parse_mib_file("MY-MIB.mib")
{:ok, %{parsed_objects: objects}} = SnmpKit.MIB.parse_mib_content(File.read!("MY-MIB.mib"))

# The raw parser, for tools that want the full definition list
{:ok, %{name: "MY-MIB", definitions: definitions, imports: imports, warnings: warnings}} =
  SnmpKit.MIB.Parser.parse(File.read!("MY-MIB.mib"))
```

## Vendor and DOCSIS MIBs

```elixir
for file <- ["DOCS-CABLE-DEVICE-MIB", "DOCS-IF-MIB", "DOCS-QOS-MIB"] do
  {:ok, compiled} = SnmpKit.MIB.compile("priv/mibs/#{file}.mib")
  :ok = SnmpKit.MIB.load(compiled)
end

{:ok, %{formatted: status}} = SnmpKit.SNMP.get("10.1.1.100", "docsIfCmStatusValue.2")
```

The DOCSIS IF-MIB objects are already built in; compiling the files adds the
rest of the DOCSIS family and any private enterprise module.

## Troubleshooting

- **`{:error, :not_found}` after loading**: check that `load/1` returned
  `:ok` and that the object is defined in that module rather than imported;
  imported definitions come from the module that owns them.
- **Compile fails on a vendor file**: run the same file through `smilint`;
  if libsmi also rejects it at that line, the file is broken rather than the
  parser. The [oracle test](mib-parser-oracle.md) documents the known
  differences.
- **Slow resolution**: names are looked up in ETS; if resolution is slow you
  are probably resolving inside a hot loop; resolve once and pass numeric
  OIDs to the SNMP calls.
