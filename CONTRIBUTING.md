# Contributing to SnmpKit

Thanks for helping. Bug reports, vendor MIBs that fail to parse, walk files
from unusual devices, and documentation fixes are as welcome as code.

## Development setup

Requirements: Elixir 1.18 or newer on OTP 28 (CI runs 1.18.4 and 1.20.0).

```sh
git clone https://github.com/awksedgreep/snmpkit.git
cd snmpkit
mix deps.get
mix test                 # the whole suite runs against simulated devices, no hardware needed
mix lint                 # mix format --check-formatted, credo --strict, dialyzer
mix docs                 # ExDoc into doc/
```

The first `mix dialyzer` builds a PLT, which takes a few minutes; the
`.dialyzer_ignore.exs` baseline lists pre-existing warnings that are being
burned down.

## Repository layout

```
lib/
  snmpkit.ex               SnmpKit, SnmpKit.SNMP, SnmpKit.MIB, SnmpKit.Sim (public entry points)
  snmp_mgr.ex              SnmpKit.SnmpMgr: manager operations
  snmpkit/
    snmp_lib/              PDUs, ASN.1, OIDs, transport, SNMPv3 security
    snmp_mgr/              core requests, walks, bulk, streams, tables, engine, multi
    mib/                   tokenizer, parser, compiler, registry, builtin tables
    snmp_sim/              simulated devices, profiles, populations, error injection
src/
  mib_grammar_elixir.yrl   yecc grammar for MIB files
priv/walks/                bundled device walks used by the simulator
test/
  fixtures/mibs/           ~200 real-world MIBs used by the parser tests
  support/                 test helpers
docs/, livebooks/, examples/
```

## Tests

- Prefer testing through a simulated device (`SnmpKit.Sim.start_device/2`)
  over mocks; it exercises real PDUs and real v1/v2c semantics.
- Pick a free port per test so `async: true` is safe.
- Encoding and decoding changes should extend the StreamData properties in
  `test/snmp_lib/property_test.exs`; a round-trip property catches more than
  hand-picked vectors.
- Tag slow or environment-dependent tests: `:performance`, `:snmpv3`,
  `:mib_oracle`, `:manual`, `:real_device`. They are excluded by default and
  run with `mix test --include <tag>`.
- `mix test <directory>` runs only some of the files in it; use globs or the
  full suite when checking your change.
- When touching the MIB parser, run the oracle test with libsmi and net-snmp
  available (see `docs/mib-parser-oracle.md`); every fixture must still parse.

## Code style

- `mix format` before committing; CI checks formatting and compiles with
  `--warnings-as-errors` on every supported Elixir.
- Public functions have `@doc` and `@spec`; modules have `@moduledoc`.
- Return tagged tuples; raise only in `!` variants.
- Never create atoms from network or file input (`String.to_atom/1` on
  device or MIB data is a bug; the credo config flags it).
- No caps on protocol parameters such as `max_repetitions`; operators tune
  those to their networks.

## Pull requests

1. Open an issue first for anything larger than a bug fix, so the design can
   be discussed before the work.
2. Branch from `main` (or from `2.x` while that branch is open), keep commits
   focused, and use conventional prefixes: `feat:`, `fix:`, `docs:`, `test:`,
   `refactor:`.
3. Add or update tests and documentation with the change; a behaviour change
   needs a CHANGELOG entry and, if it is breaking, a line in the migration
   guide.
4. Make sure `mix test` and `mix lint` pass locally; CI runs both on every
   push.

## Reporting parser problems

If a MIB fails to compile, attach the file (or a minimal cut-down of it) and
the output of `smilint -s -l 2 FILE` if you have libsmi. The parser aims to
accept everything net-snmp loads, so a file that `snmptranslate` accepts and
SnmpKit rejects is a bug.

## Releases

Maintainers: bump the version in `mix.exs`, finalise the CHANGELOG section,
tag `vX.Y.Z`, push, and publish with `mix hex.publish`.
