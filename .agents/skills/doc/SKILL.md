---
name: doc
description: >
  What an agent needs to know about XeWeCore (xewe-os-core) that the code does not show: the
  commands that check a change (host tests with ARDUINOJSON_SRC, example builds, format,
  arduino-lint, brand-lint, the XEWE_TESTING hooks build), the include direction and refused
  patterns (cli(, exceptions, [&] handlers, C++20 library features), SPDX headers and comment
  rules, stored NVS keys and console behaviour that must not change, what a feature change
  carries (code, host test, component README, example), where host and board tests go and how
  board tests run, the two-run release through scripts/release.sh, per-component pitfalls of
  Utils, Serial, Cli, Nvs, FlexData, Os, Module and System, and the decisions log. Use it before
  editing anything under src/, tests/ or examples/, before a build, test, lint or release, and
  when asking why something is the way it is.
---

# doc

This is the index of the project's agent knowledge. Open only the file whose row matches the
task. Each row names one file under `references/`, and every file there has a row.

| File | Read it when |
|---|---|
| `references/COMMANDS.md` | checking a change: host tests, example builds, format, lint, the test hooks build |
| `references/CODE_RULES.md` | adding a header or include, naming a symbol, writing a comment or a file header |
| `references/STABILITY.md` | touching an NVS key, a FlexData struct, a CLI string, a prompt or the serial line handling |
| `references/CHANGES.md` | adding or changing a core feature or an example |
| `references/TESTS.md` | writing a test, or running anything on a board |
| `references/RELEASE.md` | asked about a version bump or a release |
| `references/COMPONENTS.md` | editing Utils, Serial, Cli, Nvs, FlexData, Os, Module, System or Settings |
| `references/DECISIONS.md` | changing anything a past decision covers |
