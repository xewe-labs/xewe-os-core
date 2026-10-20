# Configuration

How every XeWe OS repository names, declares and overrides a build-time value: the core, the
modules, the projects built from the [xewe-os](https://github.com/xewe-labs/xewe-os) template and
the build tools. This page is the normative description; the tools implement their part of it in
`xewe build` and `xewe modules generate` (`doc/spec.md` §7, §10 and §13 of
[xewe-os-tools](https://github.com/xewe-labs/xewe-os-tools)).

The core follows it with [`src/XeWeCore/Config.h`](../src/XeWeCore/Config.h). The modules adopt it
one module at a time; a module without a `Config.h` in this form keeps its own defines until it
does.

- [The module Config.h](#the-module-configh)
- [Names](#names)
- [The project's Config.h](#the-projects-configh)
- [Override ladder](#override-ladder)
- [The dotenv file](#the-dotenv-file)
- [Releases](#releases)
- [Build info](#build-info)
- [What a validator checks](#what-a-validator-checks)

## The module Config.h

### File

Each module that has values keeps them in one file, `src/<Folder>/Config.h`, next to its sources.
The core is the module `CORE`; its file is `src/XeWeCore/Config.h`. A module without values has no
`Config.h`.

The file is pure preprocessor: block comments, `#pragma once`, `#ifndef` groups and `#define` lines. It
includes nothing and declares no code, so any header of the module can include it, host-testable
ones too, and the tools can copy it into a project unchanged. The module's headers read it with a
relative include (`#include "Config.h"`, or `"../Config.h"` from a subdirectory); the core's
headers do this, so `Config.h` sits above everything else in the include direction.

### Sections

After the header (the SPDX lines, the path, one paragraph, `#pragma once`) come two sections, in
this order, each opened by its marker line exactly as written here:

| Marker | Holds |
|---|---|
| `/* ---- default runtime values ---- */` | the default of a value the user changes at runtime (a settings row), including a value the first boot asks for |
| `/* ---- compile time defined constants ---- */` | pins, sizes, task parameters, debug switches |

A default runtime value is only a value a settings row stores; a struct field read once at begin is
a compile time defined constant.

Text is written in `/* */` and commented-out code in `//`, so the two are told apart at a glance.
In the module's file every text line is a single-line block comment, and the header paragraph is
one multi-line block comment; `//` appears only in the three SPDX lines.

A section may be empty, but its marker stays. The tools find the sections by these lines, so they
are never reworded.

### Entry form

Every value is one block comment line, saying what it is, its unit and its range, followed by an
`#ifndef` group:

```c
/* Serial baud rate (SerialPortConfig::baud_rate), bits per second */
#ifndef XEWE_CORE_SERIAL_BAUD
#define XEWE_CORE_SERIAL_BAUD 115200
#endif
```

The `#ifndef` makes the value a fallback: a definition that comes earlier in the build wins
([Override ladder](#override-ladder)). A string value is a string literal, a number is bare.

### Values the first boot asks for and `_PROMPT`

A value the first boot asks for is a default runtime value. Its entry also defines `<NAME>_PROMPT` inside its `#ifndef`:

```c
/* Device name (system/device_name), string literal, up to 254 characters; asked at first boot */
#ifndef XEWE_CORE_DEVICE_NAME
#define XEWE_CORE_DEVICE_NAME "xewe-device"
#define XEWE_CORE_DEVICE_NAME_PROMPT 1
#endif
```

`<NAME>_PROMPT` is therefore defined only while nothing earlier in the build defined `<NAME>`. The
first-boot code (the wizard) asks only under `#ifdef <NAME>_PROMPT` and shows `<NAME>` as the
suggested answer; without it the value counts as pre-answered and is stored without a question:

```cpp
#ifdef XEWE_CORE_DEVICE_NAME_PROMPT
    // ask, with XEWE_CORE_DEVICE_NAME as the suggestion; an empty answer takes it
#else
    // no question: store XEWE_CORE_DEVICE_NAME when nothing is stored yet
#endif
```

The settings row of the value, where it has one, always takes `<NAME>` as its default, prompt or
not. The core's device name is the reference implementation
([First-boot device name](../src/XeWeCore/Os/README.md#first-boot-device-name)).

## Names

Every define of a module's `Config.h` is named `XEWE_<SLUG>_<PARAM>`.

* **`<SLUG>`** is the module slug in upper case with `-` written as `_`: `led` → `LED`, `led-web`
  → `LED_WEB`, `web-interface` → `WEB_INTERFACE`. The core's slug is `CORE`.
* **`<PARAM>`** of a default runtime value is the value's settings key in upper
  case: the key `device_name` gives `XEWE_CORE_DEVICE_NAME`. Settings keys and NVS keys are 1 to 15
  characters and are never renamed once stored, so `<PARAM>` is at most 15 characters and keeps
  its name. The module id is the namespace of the key and is not
  part of the name: `XEWE_CORE_DEVICE_NAME` is `device_name` in the namespace `system`.
* **`<PARAM>`** of a compile-time constant is any upper-case name.
* **`_PROMPT` is reserved.** No `<PARAM>` ends in `_PROMPT`; the suffix exists only as the marker of
  a value the first boot asks for.
* **No prefix nesting.** One module's prefix is never the start of another module's define:
  `XEWE_LED_WEB_*` belongs to `led-web`, so `led` defines no `XEWE_LED_WEB_*` name.

A module defines names with its prefix only in its `Config.h`.

## The project's Config.h

A project (the template and every product made from it) has one `Config.h` in its root. The
template owns the file; the tools append to it and never create or rewrite it. It is a catalogue:
`xewe modules generate` appends one block per module, the core first, and nothing in the file is
active until the user uncomments a line.

```c
/* ---- core (xewe modules generate) ---- */
/* Values of the core. Uncomment a line to override; keep both markers. */
/* ---- default runtime values ---- */

/* Device name (system/device_name), string literal, up to 254 characters; asked at first boot */
// #define XEWE_CORE_DEVICE_NAME "xewe-device"

/* ---- compile time defined constants ---- */

/* Serial baud rate (SerialPortConfig::baud_rate), bits per second */
// #define XEWE_CORE_SERIAL_BAUD 115200
...
/* ---- end core ---- */

/* ---- wifi (xewe modules generate) ---- */
/* Values of the wifi module. Uncomment a line to override; keep both markers. */
...
/* ---- end wifi ---- */
```

* **Every entry is a block comment line followed by its definition commented out**: the comment
  line of the module's file, then `// #define NAME value`. The `#ifndef` guard and `<NAME>_PROMPT` are
  left out. A chip-conditional entry keeps its `#if`, `#elif`, `#else` and `#endif` lines, each
  commented.
* **Nothing is active until the user uncomments a line.** A fresh project defines no value of its
  own, so every module fallback applies and every question of the first boot is asked.
* **An uncommented line is a bare `#define`**, with no `#ifndef`. The generated `XeWeOverrides.h`
  is read after the project's `Config.h` and carries the `--define` and dotenv values, so a bare
  line here still yields to them ([Override ladder](#override-ladder)).
* **A line for a value the first boot asks for, once uncommented, pre-answers its question**, or carries
  `INJECTED_FROM_DOTENV` to take the answer from the dotenv file.
* **A block is appended once and never rewritten.** `xewe modules generate` adds a block when the
  file has no block of that slug; the user's edits survive every generate, and a block whose
  module is no longer selected stays.
* No `#include` and no build macros (`BUILD_VERSION` and the like). The one exception is
  `XEWE_CHIP_C3`, `XEWE_CHIP_C6` or `XEWE_CHIP_S3`, which the build defines before this file is
  read, for chip-dependent values (`#ifdef XEWE_CHIP_C3`).

What the user does in it:

| To | Write |
|---|---|
| change a default or a constant | uncomment its line and set the number or string: `#define XEWE_CORE_SERIAL_BAUD 921600` |
| pre-answer a question of the first boot | uncomment its line: `#define XEWE_CORE_DEVICE_NAME "Desk Lamp"` |
| take a value from the dotenv file at build time | `#define XEWE_WIFI_PSW INJECTED_FROM_DOTENV` |

`INJECTED_FROM_DOTENV` is the sentinel, a bare token in place of the value. A line that holds it
is active when it is not commented out; a trailing comment is allowed.

## Override ladder

For one name, the first of these that defines it wins:

1. `xewe build --define NAME=VALUE` (a release-matrix column is such a define).
2. The dotenv value, where the project's `Config.h` says `INJECTED_FROM_DOTENV`.
3. The project's `Config.h`.
4. The module's `Config.h` fallback.

The tools put three generated or project headers in front of every C++ file of the build, the
sketch, the modules, the libraries and the esp32 core alike (`-include`, in this order):

| Order | Header | Holds |
|---|---|---|
| 1 | `XeWeBuildInfo.h` (generated) | `BUILD_VERSION`, `BUILD_TIMESTAMP`, `BUILD_CHIP`, `XEWE_CHIP_<C3\|C6\|S3>` ([Build info](#build-info)) |
| 2 | the project's `Config.h` | the project's values, bare or guarded |
| 3 | `XeWeOverrides.h` (generated) | an `#undef NAME` / `#define NAME value` pair for every injected dotenv value, then for every `--define`; one pair per name, a `--define` replacing an injected value of the same name |

The module's `Config.h` is read later, when the module's own header includes it, so its `#ifndef`
groups yield to all three. Because the overrides come after the project's `Config.h` and undefine
before they define, a bare line there (an uncommented value the first boot asks for, a sentinel) still loses to
the dotenv value and to `--define`, without a redefinition warning. A value the first boot asks for, defined at
any rung leaves `<NAME>_PROMPT` undefined, so the device does not ask for it.

Outside the tools (Arduino IDE, plain arduino-cli) there is no project `Config.h` and there are no
generated headers: a compiler flag (`-DNAME=value`, in arduino-cli
`--build-property "compiler.cpp.extra_flags=..."`) beats the module fallback, and a `#define` in
the sketch reaches the sketch only, never a library file.

## The dotenv file

The dotenv file (the file `--env FILE` or `XEWE_ENV` names, else `.env` in the project, else the
one in the tools checkout) holds secrets and bench settings. It is never committed, and nothing
writes it.

* A value goes into the firmware only where the project's `Config.h` holds an active
  `INJECTED_FROM_DOTENV` line. The dotenv key is the define name; a variable of the same name in the
  real environment wins over the file.
* A sentinel whose key is missing or empty stops the build before anything is compiled, one line
  per name: `Config.h:<line>: <NAME> is INJECTED_FROM_DOTENV but the dotenv file has no value
  (looked in <file>)`.
* The value is written as a C literal: a decimal integer without a leading zero, a hexadecimal
  integer or a floating literal bare, anything else as a string literal with `\`, `"` and control
  characters escaped.
* Values never appear in a command line, a log or `meta.json`. The build logs the injected names
  only, and `meta.json` and the release card list them as `NAME=(dotenv)`.

The values the first boot asks for double as the keys `xewe provision` reads to answer the first boot over the
serial port: `XEWE_CORE_DEVICE_NAME`, `XEWE_WIFI_SSID`, `XEWE_WIFI_PSW`, `XEWE_TIME_TZ_GMT_STR`. The
dotenv file may also hold tool settings (`XEWE_PORT`, `XEWE_CHIP`, `XEWE_PROVISION_MODULES`, the
`XEWE_TEST_*` keys), which never reach the firmware.

## Releases

* `xewe release` refuses (exit 2) a project `Config.h` with an active `INJECTED_FROM_DOTENV` line,
  naming each line: a release image takes no value from anyone's dotenv file.
* A release-matrix column is a `--define`. Columns name compile time defined constants only;
  default runtime values stay out of the matrix.
* The template ships every line for a value the first boot asks for commented out, so a release
  image, the board tests and provisioning see the questions of the first boot.

## Build info

`xewe build` generates `build/builds/<chip>/gen/XeWeBuildInfo/src/XeWeBuildInfo.h` (git-ignored
with the rest of `build/`), next to `XeWeOverrides.h`:

```c
// generated by xewe build; do not edit
#pragma once
#define BUILD_VERSION "2.0.15"
#define BUILD_TIMESTAMP "2026-10-08T12:00:00Z"
#define BUILD_CHIP "c3"
#define XEWE_CHIP_C3 1       // the chip as a macro: C3, C6 or S3
```

`BUILD_VERSION` is `[project] version` of `xewe.toml`; `BUILD_TIMESTAMP` is the build time in UTC (`YYYY-MM-DDTHH:MM:SSZ`).
The project's `Config.h` never includes this header (the build reads it first anyway). The core
includes it under `__has_include(<XeWeBuildInfo.h>)` in `XeWeOs.cpp` and fills an empty
`OsConfig::version` and `build_timestamp` from it
([OsConfig](../src/XeWeCore/Os/README.md#osconfig)); without it `version` is `"0.0.0"`.
`XeWeBuildInfo.h` does not include `XeWeOverrides.h`: a source that needs a `--define` sees it
because every file gets all three headers before its first line.

## What a validator checks

A module's `Config.h`, and the sources that read it, pass these checks. The modules repository's
validator applies them to every module that has adopted this scheme; the core is held to them by
its host tests (`tests/unit/probe/Config.probe.cpp`) and by review.

* The two section markers are present, exactly as written, in their order, as single-line block
  comments.
* Every text line is a block comment; `//` appears only in the SPDX lines of a module's file and in
  front of commented-out code in a project's `Config.h`.
* Every define is inside an `#ifndef` group of its own name, with one block comment line above
  the `#ifndef`.
* Every name starts with the module's prefix `XEWE_<SLUG>_`; no name of one module starts with
  another module's prefix.
* `<NAME>_PROMPT` appears only inside the group of a value the first boot asks for, defined as `1`, and never in a project's
  `Config.h`.
* No source of the module defines a name with the module's prefix outside `Config.h`.
* Every settings-row default of the module is one of its default runtime values,
  and every such define names a key of at most 15 characters.
* Every value the first boot asks for is asked for only under an `#ifdef <NAME>_PROMPT` guard in the module's
  sources.
* `Config.h` includes nothing and holds no code.
