# XeWeCore 3.0.0 test card

What was tested, where, on which commits, and what was not. Host counts are `TEST` cases in
`tests/unit/test/` (gnu++2b pass; the c++17 pass runs the same minus Nvs and Settings). Board counts
are pytest cases in `tests/board/`, all run with `XEWE_TESTING=1`, and are the last result on the
board in the v3 campaign (runs TV3, TV4 and TV5, 2026-10-10).

| Component (src) | Host unit tests | Board tests | Not covered |
|---|---|---|---|
| SerialPort output: print, tables, wrap (`Serial.*`) | 1 golden-output test, pass | none dedicated; every board test reads its output | `message_width` wrapping on the board |
| SerialPort input: 4-line queue, 254-char lines, CRLF, garbage (`Serial.*`) | 10, pass | `test_serial_input.py` 8/8, `test_recovery_flood.py` 5/5 | a UART other than the USB CDC console |
| Prompts: `get_yn`, `get_int`, `get_str`, `get_core`, bounded confirmations (`Serial.*`) | 7 (`test_confirm`), pass | `test_prompts.py` 6/6, `test_hooks_prompts.py` 29/29 | none known |
| Cli: tokenizer, matching, help, errors (`Cli.*`) | 26 (`test_cli`, `test_cli_edges`, `test_tokenizer`), pass | `test_cli_parsing.py` 16/16, `test_hooks_cli_tokenizer.py` 26/26 | none known |
| Nvs: typed values, blobs, namespaces, error reports (`Nvs.*`) | 14 (gnu++2b only, in-memory NVS shim), pass | `test_hooks_nvs.py` 36/36, `test_nvs_persistence.py` 3/3 | partition-full and automatic-erase paths on real flash; the whole-NVS wipe (`test_recovery_nvs_wipe.py` never ran) |
| FlexData / JSON: type-matched assignment, presence, blob format (`FlexData.h`) | 18, pass | `test_hooks_flexdata.py` 22/22 | none known |
| Settings tables: load, `set`/`get`, bounds, SECRET, RESTART (`Settings.*`, `Module.cpp`) | 7 of `test_settings` (gnu++2b only), pass | no core board test | `$<module> set`/`get` on a board from the core suite (module suites used it, see below) |
| Schema: `$<module> schema`, `$system schema` (`Settings.*`, `XeWeOs.cpp`) | 4 of `test_settings`, pass | no test; one capture of `$system schema` (10 modules, `"count":47`, secret masked) | asserted schema output on a board |
| ListenerSet (`Utils/Listeners.h`) | 3, pass | none | on a board |
| Pins registry (`Utils/Pins.h`) | 5, pass | none in core | strapping warnings on a board (the modules' pins tests passed 4/4) |
| Os, Module, System: lifecycle, enable/disable, status, restart, `$system` (`XeWeOs.*`, `Module.*`) | none (not host-built) | `test_system.py` 5/5, `test_hooks_heap.py` 4/4, enable state in `test_nvs_persistence.py` | host tests; build-time device name (`XEWE_DEVICE_NAME`); `$system reset` |
| Utils: str, validator, parsers, span (`Utils/String.h`, `Validator.h`, `Span.h`) | 19 (`test_utils`, `test_parsers`), pass | `test_hooks_utils.py` 78/78 | none known |
| Utils: color, hex colour (`Utils/Color.h`, `String.h`) | 5, pass | none | on a board |
| Utils: AsyncTimer, LockGuard (`Utils/AsyncTimer.h`, `LockGuard.h`) | 1 + 1 (LockGuard against the FreeRTOS shim), pass | none | real FreeRTOS contention |
| Utils: Debug macros (`Utils/Debug.h`) | none | none | not tested |
| Recovery and soak (whole core) | none | `test_recovery_restart.py` 2/2, `test_soak_short.py` 1/1 | `test_soak_mixed.py` and `test_recovery_nvs_wipe.py` never ran |
| Totals | **96 + 121 passed, 0 failed** | **241/241 passed** (14 of 16 files) | |

Host compile probes (`tests/unit/probe/`: Cli, Serial, Utils) and the four host-includable headers
compile at c++17 and gnu++2b.

Examples: every `examples/*/*.ino` (7) compiled for ESP32-C3, C6 and S3, `--warnings default`,
against this checkout: **21/21 pass**, before and after the format commit.

## Environment

- Board: one ESP32-S3 dev board on USB (USB-Serial/JTAG, `/dev/ttyACM0`), passed through into the
  Linux VM. Board runs from an xewe-os project with all modules of the time, through the
  xewe-os-tools pytest plugin; test image 1344696 B (64 %).
- Toolchain: arduino-cli 1.5.1, esp32 core 3.3.12, ArduinoJson 7.4.3.
- Host: GCC 16.1.1 (`g++`), Linux aarch64; `-Wall -Wextra -fno-exceptions`.

## Commits

- Board (TV3, TV4, TV5): core d14d490, with the board-test expectation updates that were later
  committed as 7ebd55f; tools ff7a7c8, modules c6ace5d, template c98d2a5. `src/` and `examples/`
  are unchanged from d14d490 to ce3a0be.
- Host tests and example compiles: core ce3a0be plus the 3.0.0 preparation (unit-test runner
  without the private ArduinoJson fallback, two process comments removed, the format commit),
  that is, the tree tagged 3.0.0 apart from the version bump.

## Known limitations

- F7: the board's USB-Serial/JTAG link sometimes wedges after a software restart (silent after
  the ROM's `entry` line) or drops off USB at the reset after a flash. This happened three times in
  the campaign; each time a replug fixed it, and no test body failed because of it. The fix is a
  UART connector on the test rig, not firmware.
- Not run: `test_soak_mixed.py` (the board dropped before its first sample) and
  `test_recovery_nvs_wipe.py` (destructive opt-in). The owner closed the campaign without them.
- The first TV3 array had 8 failures. All 8 were board-test expectations that a modules release
  had made stale (reply wording). The expectations were updated and all 8 passed on the board.
- The module board tests that exercised settings tables on a board (fan, led, mlx90614) belong to
  modules that are now parked outside the release.

## Not re-run since the board campaign

The board tests have **not** been re-run on any commit after d14d490: not on 7ebd55f (test strings),
2954e21 (core trim), ce3a0be (parked-module references), nor the 3.0.0 format and preparation
commits. None of those commits change `src/` except the format commit, which a token comparison
shows changes only whitespace, line breaks and the splitting of long string literals
(`"ab" "c"`, same string). The host tests and the example compiles were re-run after the format.
