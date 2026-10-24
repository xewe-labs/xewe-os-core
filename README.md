# XeWeCore

XeWeCore is an Arduino library for ESP32 firmware authors: a serial console, a `$group command`
command line, typed NVS storage, small helpers and a module framework. You write modules, and the
core gives each one its commands, its stored settings and its place in the boot order.

## Problem

Every ESP32 firmware needs the same plumbing, and it's usually rebuilt by hand:

- A serial console and a command parser get written again for each project, each with its own
  syntax and its own error messages.
- Settings go to NVS under ad-hoc keys with no validation. A renamed key or a changed struct
  loses the data on devices that are already deployed.
- Features share one `loop()` and one `setup()`, so one blocking prompt or one slow feature
  freezes the whole device.

## Solution

XeWeCore puts that plumbing in one library with one include, `<XeWeCore.h>`. Each feature is a
module, and the core walks every module through the same boot sequence, runs its commands and
keeps its settings. Three ideas carry the rest.

1. A module's id, at most 15 characters, is its command group (`$fan …`), its NVS namespace and
   its name in `$system status`, all at once.
2. Every action has one text form, `$group command arguments`, whether a person types it, a
   button fires it or a web page sends it, so arguments are checked in one place.
3. Settings are declared once, as a table. The core loads them at boot, validates and saves
   `$<id> set`, and describes them as JSON Lines in `$system schema`.

## See it

This is `examples/02_MyModule` on the Serial Monitor at 115200 baud, after the first boot:

```text
$my set number 42
number=42
$my set number 5000
! $my set number: expected u16 in [0, 1000]
$my get number
number=42
$system schema
{"schema":1,"core":"2.1.0","device":"Kitchen Lights","modules":["system","my"]}
{"module":"my","key":"number","type":"u16","min":0,"max":1000,"default":0,"value":42,"doc":"The remembered number"}
{"end":"system","count":1}
```

The value 42 is still there after `$system restart`.

## Why not Serial and Preferences by hand

| | By hand | XeWeCore |
|---|---|---|
| Command parsing | you write it | `$group command args` with quoting, and a `$help` table per group |
| Setting validation | you write it per setting | from the table: type, range, length and default |
| Stored data | you track keys and layouts | a namespace per module, typed reads with defaults, versioned `FlexData` structs |
| Prompt timeouts | you write them | confirmations give up after 2 tries of 15 s, so an unattended device keeps running |
| Machine-readable surface | you write it | `$system schema`, for a web page, an app or a test |

The parts also work alone. You can use `xewe::SerialPort`, `xewe::Cli` or `xewe::Nvs` without
the module framework.

## Install

In the Arduino IDE, open the Library Manager, search for `XeWeCore` and install it. ArduinoJson 7
installs with it. With arduino-cli:

```sh
arduino-cli lib install XeWeCore
```

XeWeCore runs on the ESP32 family with arduino-esp32 3.x. The smallest sketch:

```cpp
#include <XeWeCore.h>

XeWeOs os({.version = "0.1.0"});

void setup() { os.begin(); }
void loop()  { os.loop();  }
```

Upload it, open the Serial Monitor at 115200 baud and type `$help`.

## Usage

Use the console as it comes. [`examples/01_Hello`](examples/01_Hello/01_Hello.ino) gives you
`$help`, `$system status` and a device name that is kept in NVS.

Write a module of your own. [`examples/02_MyModule`](examples/02_MyModule/02_MyModule.ino) adds
`$my …` commands, a settings table, a listener and enable and disable. Copy `MyModule.h` and
`MyModule.cpp` to start yours.

Build a product with the [xewe-os](https://github.com/xewe-labs/xewe-os) project template and its
tools. They add ready-made modules such as Wi-Fi, a web interface and a scheduler, plus multi-chip
builds, board tests and releases.

Levels 1 and 2 need nothing but the Arduino IDE. The other examples, `11_Utils` to `15_Os`, show
one part of the core each ([doc/EXAMPLES.md](doc/EXAMPLES.md)). [`doc/`](doc/README.md) explains
the concepts and indexes the reference for every public type, command and stored key. Build-time
values, such as the serial defaults and the first-boot device name, and how a build overrides
them, are in [doc/CONFIG.md](doc/CONFIG.md).

## Status

The version in `library.properties` is 3.1.2, and the library is registered in the Arduino
Library Manager. CI compiles every example for ESP32-C3, C6 and S3 and runs the host unit tests,
100 at `c++17` and 125 at `gnu++2b`. The 16 board test files run from an xewe project with a
board attached.

---

## Development

Run the host tests with a host `g++` and an ArduinoJson checkout at `v7.4.3`:

```sh
ARDUINOJSON_SRC=<path to ArduinoJson>/src tests/unit/run.sh
```

[doc/TESTS.md](doc/TESTS.md) covers the example builds, CI and the board tests. A change to the
core carries four things together: the code in `src/XeWeCore/`, a host test in
`tests/unit/test/`, the component's `README.md` for every public function, command, prompt, NVS
key or build define it adds or changes, and `examples/02_MyModule` when the module API changes.
[doc/LIBRARY_RULES.md](doc/LIBRARY_RULES.md) says what keeps the library valid for the Library
Manager. Maintainers release with `scripts/release.sh` ([scripts/README.md](scripts/README.md)).

## Layout

- [`src/`](src/README.md) holds the library. Each component folder under `src/XeWeCore/` has a
  README with its reference.
- [`examples/`](examples/README.md) holds the sketches that the Arduino IDE lists under File,
  Examples, XeWeCore.
- [`tests/`](tests/README.md) holds the host unit tests and the board tests.
- [`scripts/`](scripts/README.md) holds the release script.
- [`doc/`](doc/README.md) holds the concepts, configuration, examples, tests and library rules.

## License

GPL-3.0-only. See [LICENSE.txt](LICENSE.txt).
