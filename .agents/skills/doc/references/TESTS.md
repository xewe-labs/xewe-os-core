# Tests

## Where each test goes

- Host tests are `tests/unit/test/test_*.cpp`. Those that need ArduinoJson go in
  `tests/unit/test/json/`.
- Compile probes are `tests/unit/probe/*.probe.cpp`, and the Arduino, FreeRTOS, NVS and ESP log
  stand-ins are in `tests/unit/shim/`. `tests/unit/run.sh` drives all of them.
- Board tests are `tests/board/test_*.py` and run only through the `xewe-os-tools` pytest plugin.

A parser, tokenizer or FlexData case lives in both tables, in these pairs:

| Host | Board |
|---|---|
| `test_parsers.cpp` | `test_hooks_utils.py` |
| `test_tokenizer.cpp` | `test_hooks_cli_tokenizer.py` |
| `json/test_flexdata.cpp` | `test_hooks_flexdata.py` |

## Board tests

They run from an xewe project with a board attached, never on their own. `doc/TESTS.md` has the
command. Take the board lock with `flock <project>/.board.lock` first, and never flash a board
unless the human asked.

Tests never clean up with `erase_all()`, `disable()` or `System::reset()`. Board-test namespaces
start with `xt`. `test_recovery_nvs_wipe.py` needs `XEWE_HWTEST_DESTRUCTIVE=1` and runs only on
request.

## Test hooks

Everything hook-related, including the call site in `XeWeOs.cpp`, stays inside
`#ifdef XEWE_TESTING`. A build without the define has an empty `Testing.cpp.o` and no `$test`
string. There are no crash, abort or watchdog hooks.

## Credentials

Never open, print or copy a dotenv or key file. The tools read them.
