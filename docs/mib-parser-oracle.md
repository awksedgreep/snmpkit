# Checking the MIB parser against libsmi and net-snmp

`SnmpKit.MIB.Parser` is a port of OTP's `snmpc` tokenizer and grammar. To keep
it honest against reference implementations, `test/mib/smilint_oracle_test.exs`
runs libsmi's `smilint` and net-snmp's `snmptranslate` over every fixture MIB
and asserts that SnmpKit never rejects a file either tool parses. We may be
more lenient than a reference, never stricter.

libsmi is the strict reference (a bison grammar with a catalogue of numbered
errors); net-snmp is the permissive one that real deployments rely on. Only
their syntax-level findings count: import resolution and semantic checks
(missing modules, range limits, SMI version consistency) are ignored because
the parser does no semantic validation.

## Running it

The tests are tagged `:mib_oracle` and excluded by default. Each looks for its
tool on `PATH` or in an environment variable (`SMILINT`, `SNMPTRANSLATE`) and
passes with a notice when the tool is absent.

```sh
SMILINT=/path/to/libsmi/bin/smilint \
SNMPTRANSLATE=/path/to/net-snmp/bin/snmptranslate \
  mix test --include mib_oracle test/mib/smilint_oracle_test.exs
```

Status at the time of writing: all 185 fixture MIBs parse natively. About a
dozen carry warnings for constructs net-snmp tolerates and libsmi rejects; see
"Constructs accepted with a warning" below.

## Building libsmi

libsmi 0.5.0 is not packaged for every distribution. It builds from source in
a minute, but its 2014 code uses empty prototypes that GCC 15's C23 default
rejects, so pin the C standard:

```sh
curl -sSLO https://www.ibr.cs.tu-bs.de/projects/libsmi/download/libsmi-0.5.0.tar.gz
tar xzf libsmi-0.5.0.tar.gz && cd libsmi-0.5.0
./configure --prefix="$HOME/.local/libsmi" --disable-shared
make CFLAGS="-std=gnu11 -O2 -Wno-implicit-function-declaration -Wno-incompatible-pointer-types"
make install
```

The install also ships the IETF, IANA and IRTF MIB trees under
`share/mibs`; the test adds them to smilint's search path so `IMPORTS`
resolve and only real syntax problems are reported.

## Building net-snmp

Only the applications are needed (`snmptranslate` loads a MIB given as a path
with `-m`):

```sh
curl -sSLO https://github.com/net-snmp/net-snmp/archive/refs/tags/v5.9.4.tar.gz
tar xzf v5.9.4.tar.gz && cd net-snmp-5.9.4
./configure --prefix="$HOME/.local/net-snmp" --with-defaults --disable-agent \
  --disable-manuals --disable-scripts --without-perl-modules \
  --disable-embedded-perl --disable-shared --with-mib-modules="" --with-transports=UDP
make && make install
```

Parse errors surface as `<message>: At line N in <file>`; the test treats
only those as rejections, not the `Undefined identifier` / `Unlinked OID`
linkage messages.

## Constructs accepted with a warning

These are invalid SMIv2 but appear in shipped vendor MIBs and are loaded by
net-snmp, so the grammar accepts them and the parser records a warning:

| Construct | Treated as |
|-----------|-----------|
| `SYNTAX Integer32 { a(1) }` / `Unsigned32 { ... }` | `INTEGER` enumeration |
| enumeration label starting with an uppercase letter | kept as written |
| `MAX-ACCESS write-only` | `write-only` |
| `UNITS` on an SMIv1 (`ACCESS`/`mandatory`) OBJECT-TYPE | kept as written |
| `LAST-UPDATED` / `REVISION` stamp with an impossible date | kept as written |

net-snmp rejects identifiers containing underscores outright; SnmpKit accepts
them with a warning, as it always has.

## Lexer checks adopted from libsmi

The tokenizer (`SnmpKit.MIB.SnmpTokenizer.scan/1`) returns `{line, message}`
warnings, exposed as `warnings` on the parsed MIB map and turned into errors by
`SnmpKit.MIB.Compiler` when `warnings_as_errors: true`:

| Check | libsmi error |
|-------|--------------|
| identifier contains an underscore | `ERR_UNDERSCORE_IN_IDENTIFIER` |
| identifier ends in a hyphen | `ERR_ID_ENDS_IN_HYPHEN` |
| hex string with an odd number of digits | `ERR_HEX_STRING_MUL2` |
| binary string not a multiple of 8 bits | `ERR_BIN_STRING_MUL8` |
| non-radix character in a hex/binary string | lexer rejects the token |
| input is not valid UTF-8 (decoded as Latin-1) | `ERR_ILLEGAL_CHAR_IN_STRING` |

Two libsmi behaviours were adopted outright: a `--` inside an identifier starts
a comment rather than being swallowed into the name, and backslashes in quoted
strings are literal characters (SMI has no escape sequences).

## Deliberately different from libsmi

- Comments run to end of line. libsmi and ASN.1 also end a comment at the next
  `--` on the same line; net-snmp and OTP use end of line, which is what
  vendor MIBs in the wild assume.
- No semantic checks (base types, ranges, MODULE-IDENTITY presence, SMI
  version consistency). Those belong to a validator, not the parser.
