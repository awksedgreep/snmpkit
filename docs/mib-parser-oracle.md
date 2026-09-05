# Checking the MIB parser against libsmi

`SnmpKit.MIB.Parser` is a port of OTP's `snmpc` tokenizer and grammar. To keep
it honest against a reference implementation, `test/mib/smilint_oracle_test.exs`
runs libsmi's `smilint` over every fixture MIB and asserts:

1. every file smilint parses without a syntax error also parses natively, and
2. SnmpKit never rejects a file that smilint accepts (we may be more lenient,
   never stricter).

Import-resolution and semantic findings from smilint (missing modules, SMIv1
`ACCESS` in an SMIv2 module, range checks) are deliberately ignored; the
parser does no semantic validation.

## Running it

The test is tagged `:smilint` and excluded by default. It looks for `smilint`
on `PATH` or in the `SMILINT` environment variable and passes with a notice
when neither is set.

```sh
SMILINT=/path/to/libsmi/bin/smilint \
  mix test --include smilint test/mib/smilint_oracle_test.exs
```

Status at the time of writing: 185 fixture MIBs, 180 parse natively, 5 are
rejected by both tools (genuinely broken vendor files).

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
