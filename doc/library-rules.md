# Library rules

What keeps XeWeCore a valid Arduino library in the Library Manager (and on PlatformIO). CI checks
the Library Manager side with `arduino-lint --compliance strict --library-manager update` (the
`arduino-lint` job of the tools' `xewe-core-tests.yml`, [tests.md](tests.md#ci)); the rest is
kept by hand and by `scripts/release.sh`.

## Layout

* The Arduino 1.5 library layout at the repository root: `library.properties`, `src/`,
  `examples/<Name>/<Name>.ino`, `LICENSE.txt`, `README.md`. No `.gitmodules`, `.development`,
  symlinks or `.exe` files anywhere (the Library Manager rejects the release).
* `src/` has exactly one top-level header, `src/XeWeCore.h`, the entry header named in
  `includes=`. Arduino finds a library by its top-level header names and puts every library's
  `src/` on the include path, so generic names there (`String.h`, `Timer.h`, `Module.h`) would
  collide with other libraries or, on macOS and Windows, with system headers. Everything else is
  under `src/XeWeCore/`, and files include each other with relative quotes.
* Other libraries are included only through their entry header (`#include <ArduinoJson.h>`).
* Every example compiles for esp32c3, esp32c6 and esp32s3 ([tests.md](tests.md)).

## `library.properties`

* `name=XeWeCore`; `version=` is `MAJOR.MINOR.PATCH`, the same as the release tag (no `v`).
* `url=` is the repository's GitHub URL; `category=` is one of the Arduino categories.
* `architectures=` is an explicit, comma-separated list of what CI compiles the examples for
  (today `esp32`), never `*`: `*` claims every architecture, 8-bit AVR included, which has no C++
  standard library.
* `depends=` declares every library a source file includes (ArduinoJson) and nothing else.

`library.json` is the PlatformIO manifest and mirrors it: `name`, `version`, `description`
(= `sentence=`), `platforms` (`esp32` → `espressif32`), `headers` (= `includes=`) and
`dependencies` (`bblanchon/ArduinoJson`, the same constraint). Change both together;
`scripts/release.sh --prepare` moves the version in both.

## Names

* Code lives in `namespace xewe`; class names carry no prefix (`xewe::Cli`, `xewe::Nvs`).
* The AVR and ESP32 cores define `cli`, `sei`, `constrain`, `radians`, `degrees`, `sq`, `bit`,
  `lowByte` and `highByte` as function-like macros, so none of these may be followed directly by
  `(` as anything else. `xewe::Cli cli(serial);` does not compile (`cli(` expands to
  `portDISABLE_INTERRUPTS()`); the class `xewe::Cli`, `os.cli.loop()` and brace initialization
  `cli{serial}` are fine. A sketch-level object is named `xewe_cli`.
* Debug flags default to 0 with `#ifndef DEBUG_<Class>` and are enabled from build flags
  ([Debug macros](../src/XeWeCore/Utils/README.md#debug-macros)).

## Library Manager

XeWeCore is registered in `arduino/library-registry`, so its `name=` can no longer change. The
Library Manager picks up each new tag by itself, usually within a day; a tag is never moved or
reused, so a fix is a new version. Releases
go through `scripts/release.sh` (README "Releasing").
