# XeWeCore

XeWeCore is an Arduino library for ESP32 firmware authors: a serial console, a `$group command` command line, typed NVS storage and a module framework.

## Problem

- Each project rewrites its serial console and command parser, with its own syntax and error messages.
- Settings go to NVS under ad-hoc keys with no validation, and a renamed key loses the data on deployed devices.
- Features share one `loop()`, so one blocking prompt freezes the whole device.

## Solution

XeWeCore puts that plumbing in one library with one include, `<XeWeCore.h>`. You write modules, and the core gives each one its commands, its stored settings and its place in the boot order. Three ideas carry it:

1. A module's id, at most 15 characters, is its command group (`$fan ...`), its NVS namespace and its name in `$system status`.
2. Every action has one text form, `$group command arguments`, whether a person types it, a button fires it or a web page sends it.
3. Settings are declared once, as a table. The core loads them at boot, validates and saves `$<id> set`, and describes them in `$system schema`.

## See it

This is `examples/02_MyModule` on the Serial Monitor at 115200 baud:

```text
$my set number 42
number=42
$my set number 5000
! $my set number: expected u16 in [0, 1000]
$system schema
{"schema":1,"core":"2.1.0","device":"Kitchen Lights","modules":["system","my"]}
{"module":"my","key":"number","type":"u16","min":0,"max":1000,"default":0,"value":42,"doc":"The remembered number"}
{"end":"system","count":1}
```

## Why not Serial and Preferences by hand

| | By hand | XeWeCore |
|---|---|---|
| Commands | you write the parser | `$group command args` with quoting and a `$help` table per group |
| Settings | you validate each one | type, range, length and default from the table |
| Stored data | you track keys and layouts | a namespace per module and versioned `FlexData` structs |
| Prompts | you write the timeouts | a confirmation gives up after 2 tries of 15 s |

## Install

```sh
arduino-cli lib install XeWeCore
```

The Arduino IDE Library Manager works too. It needs an ESP32 with arduino-esp32 3.x. The smallest sketch:

```cpp
#include <XeWeCore.h>

XeWeOs os({.version = "0.1.0"});

void setup() { os.begin(); }
void loop()  { os.loop();  }
```

Upload it and type `$help` in the Serial Monitor at 115200 baud.

## Usage

Use the console as it comes with [`examples/01_Hello`](examples/01_Hello/01_Hello.ino), which gives you `$help` and `$system status`.

Write a module of your own by copying `MyModule.h` and `MyModule.cpp` from [`examples/02_MyModule`](examples/02_MyModule/02_MyModule.ino).

Build a product with the [xewe-os](https://github.com/xewe-labs/xewe-os) template, which adds Wi-Fi, a web interface and releases.

[`doc/`](doc/README.md) explains the concepts and indexes every public type, command and stored key. See [doc/CONFIG.md](doc/CONFIG.md) for build-time values.

## Status

Version 3.1.2 is in the Arduino Library Manager. CI compiles every example for ESP32-C3, C6 and S3 and runs the host unit tests. The board tests run from an xewe project with a board attached.

---

## Development

```sh
ARDUINOJSON_SRC=<path to ArduinoJson>/src tests/unit/run.sh
```

This needs a host `g++` and ArduinoJson at `v7.4.3`. [doc/TESTS.md](doc/TESTS.md) covers the example builds, CI and the board tests. A change carries its code, a host test in `tests/unit/test/`, the component README for every public function, command, NVS key or build define it touches, and `examples/02_MyModule` when the module API changes. [doc/LIBRARY_RULES.md](doc/LIBRARY_RULES.md) lists what keeps the library valid.

## Layout

- [`src/`](src/README.md) holds the library.
- [`examples/`](examples/README.md) holds the sketches in the Arduino IDE's Examples menu.
- [`tests/`](tests/README.md) holds the host unit tests and the board tests.
- [`scripts/`](scripts/README.md) holds the release script.
- [`doc/`](doc/README.md) holds the concepts, configuration, examples, tests and library rules.

## License

GPL-3.0-only. See [LICENSE.txt](LICENSE.txt).
