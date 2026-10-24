# Code rules

## Headers and includes

`src/XeWeCore.h` is the only header directly under `src/`, and everything else lives in
`src/XeWeCore/`. Every sketch, example and doc snippet includes `<XeWeCore.h>` first, because
arduino-cli finds the library only from its top-level header. Files inside the library include
each other with relative quotes.

The include direction runs one way. `Config.h` is above everything and includes nothing, so any
header may read it, the host-includable ones too. Then Utils, Serial, Cli. FlexData comes before
Nvs. Settings sees Serial and only forward-declares Nvs. Module depends on all of them, and
XeWeOs on Module. These lines must keep holding:

- Nothing below `Module.h` includes upward, and `Module.h` forward-declares `class Os;` instead
  of including `XeWeOs.h`. Only `.cpp` files include `XeWeOs.h`.
- `Serial` includes none of `XeWeOs.h`, `Nvs.h` or `Cli.h`. `Cli` does not include `XeWeOs.h`.
- `Nvs` never includes `Utils.h` or `Serial.h`, and reports through `set_error_handler`.
- `FlexData.h` includes no `esp_*` header and no `nvs.h`.
- `Utils/` has no `.cpp` file.
- `Color.h`, `String.h`, `Pins.h` and `Listeners.h` include no `<Arduino.h>`. Other
  repositories include them in host tests, and `tests/unit/run.sh` compiles each one without the
  shim.

## Names

Everything is in namespace `xewe`, with `xewe::str`, `xewe::color`, `xewe::pins`, `xewe::detail`
and `xewe::testing` below it. The only global symbols are `XeWeOs`, the `DBG_*`, `DEBUG_*`,
`STRINGIFY_XEWE` and `TO_STRING` macros, and `XEWE_CORE_VERSION` with its `_MAJOR`, `_MINOR` and
`_PATCH` parts, which equal `library.properties`.

## Patterns that are refused

- `cli(` or `cli (` anywhere, because the core defines `cli()` as a macro. A class named
  `xewe::Serial`, because `Serial` is a macro too.
- `try`, `catch`, `throw`, `std::stoll` and `std::stod`. The host build uses `-fno-exceptions`.
- A `std::function` global where a function pointer does the job.
- A `DEBUG_<Class>` flag enabled in a header.
- A module constructor parameter named `os`. Name it `host`.
- `[&]` in a module's command handler. Capture `[this]`.
- Blocking in any `loop()`, and a prompt outside a setup routine.
- A feature module, such as Wi-Fi, buttons or a web interface, in this repository. Those live in
  xewe-os-modules.

## C++17 floor

New code uses no `std::span` and no other C++20 library feature. Use `xewe::span`. The one
exception is `Nvs::write_blob`, which keeps its `std::span` signature.

## Source files

Every source file starts with the SPDX lines from `guidelines/license-header.txt` of the
xewe-labs organization repository, and the third line is the path, as in
`// xewe-os-core/src/XeWeCore/Config.h`. Markdown files have no header.

A comment says what the code does or why: an invariant, a limit, a hardware fact. It never names
an agent, a session, a date, a decision or finding id, a review or a report, and it never says
what the code used to be.

`src/XeWeCore/Config.h` follows the format in `doc/CONFIG.md`, which lets the tools copy it into
a project unchanged. Its block comments and section marker lines are part of that format, so edit
them only together with that page.

The xewe-labs organization guidelines at `https://github.com/xewe-labs/.github/tree/main/guidelines` apply where this skill is silent.
