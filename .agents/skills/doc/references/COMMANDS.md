# Commands

Run these from the repository root before calling a change done: the host tests, the example
builds, the format check and the lint.

## Host tests

```bash
ARDUINOJSON_SRC=<ArduinoJson>/src tests/unit/run.sh
```

The script stops when `ARDUINOJSON_SRC` is unset. Point it at a clone of bblanchon/ArduinoJson at
`v7.4.3`, the tag CI uses. A checkout of an xewe project that ran setup has one in
`build/libraries/ArduinoJson/src`. A green run prints `100 tests, 0 failed checks` for `c++17`,
`125 tests, 0 failed checks` for `gnu++2b`, and ends with `== all unit checks passed`. Both passes
build with `-fno-exceptions`.

## Example builds

The examples compile for esp32c3, esp32c6 and esp32s3, as CI's `examples` job does. With plain
arduino-cli:

```bash
arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc --library . examples/01_Hello
```

`doc/TESTS.md` has the full FQBN and the loop over every example.

## Format and lint

- `xewe --project . format --check` runs clang-format with the tools' style and ruff on the
  Python. CI blocks on it. The style aligns nothing, so a deleted line never forces a realign.
- `arduino-lint --compliance strict --library-manager update .` must pass. Run it from a clone
  whose folder name is a valid library name. In a working copy named `xewe-os-core` only LS003
  (the folder name) may fail.
- `xewe brand-lint .` fails on misspellings of the brand. The tools' `brandlint.py` holds the
  pattern.

## Test hooks build

`XEWE_TESTING` compiles in the `$test` group (`src/XeWeCore/Testing/`) that the board files
`test_hooks_*` drive. Build it in one of three ways:

- `xewe build --chip s3 --define XEWE_TESTING=1`, then `xewe flash --no-build`.
- `XEWE_HWTEST_DEFINES=XEWE_TESTING=1` for the pytest run.
- arduino-cli with `--build-property compiler.cpp.extra_flags=-DXEWE_TESTING=1`.

Board tests themselves are in `TESTS.md`.
