# AGENTS.md - Critical Rules for AI Agents Working on snmpkit Project

## ABSOLUTE TESTING RULES - NO EXCEPTIONS
- Do not use IO.puts or IO.inspect for output in code or tests. Use Logger.xxx for all logging so output can be controlled and reduced easily.
- If you temporarily add logging in tests, remove it once the test is passing.

## 🚨 ABSOLUTE DIRECTORY RULES - NO EXCEPTIONS

### ✅ CURRENT WORKING DIRECTORY
- ALWAYS STAY IN: `/Users/mcotner/Documents/elixir/snmpkit`
- NEVER LEAVE THIS DIRECTORY - All work must be done here
- NEVER use `cd` commands to change to parent directories or other projects unless the user explicitly asks
- NEVER work in any other Elixir project directories

### 🛑 FORBIDDEN ACTIONS
- DO NOT CHANGE DIRECTORIES without explicit user permission
- DO NOT ASSUME WHAT NEEDS TO BE FIXED - ask first
- DO NOT WORK ON MULTIPLE PROJECTS simultaneously
- NEVER USE `--max-failures` with `mix test` - it provides incomplete information about actual test status
- DO NOT RUN `mix test --max-failures` and then claim only that number are failing

## 📋 PROJECT CONTEXT

### What is snmpkit?
- snmpkit is an Elixir SNMP toolkit/library. As of 1.0, most SNMP operations return enriched maps including keys like `:name`, `:oid`, `:type`, `:value`, and optionally `:formatted`.
- Global defaults typically enable `include_names: true` and `include_formatted: true`. Tests and docs should reflect these defaults unless explicitly testing alternative configurations.

### Work Scope
- ONLY modify files in this project (`/Users/mcotner/Documents/elixir/snmpkit`).
- Prefer working on test files under `./test/` to validate and adapt behavior.
- Modify library code under `./lib/` only when necessary to fix failing tests or to implement clearly defined tasks and only after confirming with the user.
- NEVER modify other projects or any parent directories.

## 🔍 MANDATORY ROOT CAUSE ANALYSIS

### Before ANY changes:
1. Identify the exact error - read full error messages
2. Analyze WHY the test is failing - understand the root cause
3. Determine if the issue is in snmpkit code, configuration, or test expectations (e.g., enriched map vs legacy return types)
4. Ask user for permission before making any impactful code modifications
5. Verify the fix addresses root cause, not just symptoms

### Root Cause Categories to Check:
- Test configuration issues (env vars, mix env, network expectations)
- API or behavior changes (e.g., enriched outputs replacing tuples/values)
- Test isolation problems (ports, UDP sockets not closed, lingering processes)
- Dependency issues
- Configuration mismatches (global include_names/include_formatted defaults)

## 📁 WORKING DIRECTORY STRUCTURE

```
/Users/mcotner/Documents/elixir/snmpkit/       ← WORK HERE ONLY
├── lib/                                       ← Library code
├── test/                                      ← Tests
├── docs/                                      ← Documentation
├── examples/                                  ← Example scripts
├── mix.exs                                    ← Dependencies & project setup
└── AGENTS.md                                  ← This file
```

### FORBIDDEN DIRECTORIES:
```
/Users/mcotner/Documents/elixir/ddumb/         ← Not this project
/Users/mcotner/Documents/elixir/ddnet/         ← Different project
/Users/mcotner/Documents/elixir/* (others)     ← Other projects - not relevant
```

## 🧪 TESTING PROTOCOL

### Test Command Rules:
- ALWAYS use `mix test` without limiting flags
- NEVER use `--max-failures`
- ALWAYS run full test suite to get accurate count of all failures
- NEVER report partial failure counts as if they represent total failures
- ALWAYS wait for complete test run before analyzing results

### SNMP-specific Testing Notes:
- Some tests may intentionally use invalid hosts or simulate timeouts. Network failures in such cases are expected and should not be “fixed” unless the test intention says otherwise.
- When asserting on SNMP results, prefer enriched map assertions: `%{oid: oid, type: type, value: value, formatted: formatted}` as applicable.
- Keep tests deterministic: avoid dependence on real external network conditions unless explicitly intended.

## ⚠️ ERROR HANDLING PROTOCOL

### When encountering test failures:
1. READ the full error message - don't assume
2. Identify if failure is due to enriched output vs legacy expectations
3. Verify configuration defaults (include_names/include_formatted) match test assumptions
4. Ask user before making ANY code changes beyond test adjustments

### Common Issues:
- Pattern matches expecting tuples or raw values instead of enriched maps
- Helpers/utilities not updated to handle enriched map structure
- Formatting differences when using `get_pretty` or formatted values

## 🎯 SUCCESS CRITERIA

### What constitutes successful work:
- Tests pass in snmpkit project
- Documentation/examples are consistent with current API behavior
- Root cause identified and documented
- Changes are minimal and targeted
- User approves all significant code modifications

### What constitutes failure:
- Working in the wrong directory
- Making assumptions and broad changes without analysis
- Introducing regressions or altering documented behavior without approval

## 📞 COMMUNICATION PROTOCOL

### Always ask before:
- Making ANY non-trivial code changes
- Modifying configuration files
- Adding or removing dependencies
- Changing repository structure

### Always report:
- Current working directory when starting work
- Root cause analysis before proposing fixes
- Exact changes planned before implementation
- Test results after any changes

## 🚨 EMERGENCY STOP CONDITIONS

Immediately stop and ask if:
- You realize you're in the wrong directory
- You're about to make changes with unclear impact
- You don't understand the root cause yet
- Tests are failing for unknown reasons

## 📚 REFERENCE DOCUMENTATION

- Erlang/OTP SNMP application docs
- HexDocs for this project (snmpkit) and dependencies
- Elixir Logger documentation (use Logger.xxx rather than IO.puts/IO.inspect)

---

REMEMBER: Work only in `/Users/mcotner/Documents/elixir/snmpkit`. Follow the enriched-output conventions and testing rules above.
