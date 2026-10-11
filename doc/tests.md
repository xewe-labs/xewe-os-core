# Tests

XeWeCore has three kinds of checks: host unit tests, example builds and board tests. `tests/` is
not compiled by the Arduino builder.

## Host unit tests

`tests/unit/run.sh` needs only a host `g++` and bash.

- It compiles the probes in `tests/unit/probe/` and the tests in `tests/unit/test/` against the
  shims in `tests/unit/shim/` (Arduino, FreeRTOS, ESP log, an in-memory NVS).
- It builds and runs everything twice: at `-std=c++17`, which exercises the `xewe::span` fallback,
  and at `-std=gnu++2b`, which is what the ESP32 core uses. Both use `-fno-exceptions`.
- The FlexData tests need ArduinoJson. Set `ARDUINOJSON_SRC` to its `src/` directory, for example
  after `git clone --depth 1 --branch v7.4.3 https://github.com/bblanchon/ArduinoJson` (the tag CI
  uses). Unset, the script stops with that hint.
- The Nvs and Settings tests need C++20 and ArduinoJson, so they run in the `gnu++2b` pass only.
  That pass runs 121 tests, the `c++17` pass 96.

The last line is `== all unit checks passed`; any failure stops the script with a non-zero exit.

## Example builds

Every `examples/*/*.ino` compiles against this checkout for ESP32-C3, C6 and S3, with the
arduino-cli and esp32 core versions the tools pin (`src/xewe/env/pins.py`) and the tools' FQBNs
(`src/xewe/build/chips.py`), ArduinoJson from the Library Manager:

```sh
FQBN=esp32:esp32:esp32c3:CDCOnBoot=cdc,CPUFreq=160,DebugLevel=none,EraseFlash=all,FlashMode=qio,FlashSize=4M,PartitionScheme=no_ota,UploadSpeed=921600
for ino in examples/*/*.ino; do arduino-cli compile --fqbn "$FQBN" --warnings default --library . "$ino"; done
```

Repeat with `esp32c6` and `esp32s3`. CI does the same, one job per chip.

## CI

`.github/workflows/tests.yml` calls the tools' `xewe-core-tests.yml` on every push and pull request.
Every job blocks: the host unit tests, arduino-lint, the example builds (c3, c6, s3),
`xewe format --check` (clang-format with the tools' style, ruff for the Python) and
`xewe brand-lint`.

## Board tests

The pytest files in `tests/board/` run on a real board through the xewe-os-tools pytest plugin
(fixtures `compiled`, `firmware`, `serial`).

| File | Covers |
|---|---|
| `test_cli_parsing.py` | `Cli::execute`/`tokenize`/`print_help`: help shape, case, errors, quotes, whitespace, 254-char lines, over-long lines dropped whole |
| `test_serial_input.py` | `SerialPort::loop`/`push_line` queue: bursts of 2/4/5/6 lines, overflow notice, CRLF, binary garbage, input during a long reply |
| `test_system.py` | `System::status` table, info/uid/mac, uptime and heap (from `$web_interface status`), `$system restart` |
| `test_prompts.py` | `get_yn`/`get_core` via `$buttons disable`: n, y (+ enable), one typo re-prompts, a second invalid answer cancels, 2 × 15 s timeout cancels, type-ahead discard |
| `test_nvs_persistence.py` | button mapping, schedule and enable flags across `$system restart` |
| `test_soak_short.py` | 200 mixed commands, heap sampled every 20 |
| `test_hooks_*` | `$test` hooks: NVS, FlexData, parsers, prompts, tokenizer, heap; need `XEWE_HWTEST_DEFINES=XEWE_TESTING=1` |
| `test_recovery_*`, `test_soak_mixed.py` | input flood, restart cycles, NVS wipe (destructive, `XEWE_HWTEST_DESTRUCTIVE=1`), mixed soak; see their docstrings |

`conftest.py` adds the `cli` fixture and `csv_writer`. `cli` runs a command and collects the
reply, writes raw bytes, reads heap and uptime, restarts and waits for the boot banner, and clears
the button and schedule tables.

### Run from an xewe project

The board tests drive modules (buttons, scheduler, web interface), so they run from an xewe project
with a board attached. `xewe test` always collects the project's and the modules' `tests/`. Pass
the core's files after `--` and deselect the module tests by node-id prefix (`--ignore` does not
drop explicit roots):

```sh
H=<xewe project with a board attached>
D=<this repository>/tests/board
cd $H
XEWE_HWTEST_LOG_DIR=/path/to/logs \
flock $H/.board.lock build/tools/.venv/bin/python -m xewe test --chip s3 --require-board -- \
  $D/test_cli_parsing.py $D/test_serial_input.py $D/test_system.py \
  $D/test_prompts.py $D/test_nvs_persistence.py $D/test_soak_short.py \
  --deselect=build/modules -v -s --junitxml=/path/to/logs/junit.xml
```

`XEWE_HWTEST_LOG_DIR` is optional. It receives the heap and uptime CSVs (`<HHMM>-heap-*.csv`).

Preconditions:

- The board is provisioned, and Wi-Fi is connected.
- The modules buttons, pins, wifi, time, scheduler and web-interface are enabled. Other modules
  may be present: the status and help tests check order and the required set, not an exact list.
- GPIO `XEWE_TEST_BUTTONS_PIN` (default 14) is free.

The tests restart the board several times (`$system restart`, `$buttons disable`/`enable`) and
remove **all** button mappings and schedules they find. They never run `$system reset` or touch
Wi-Fi settings. A run takes about 4 min 10 s on an ESP32-S3.

### Test hooks

`XEWE_TESTING` compiles in the `$test` command group (`src/XeWeCore/Testing.{h,cpp}`) that the
`test_hooks_*` files drive. Set `XEWE_HWTEST_DEFINES=XEWE_TESTING=1` for the pytest run. Without
the define the hooks add 0 bytes to the firmware.
