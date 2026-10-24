# src

This folder is the XeWeCore library. `XeWeCore.h` is the umbrella header and the only header
directly under `src/`, because Arduino finds a library by its top-level headers. Everything else
is in `XeWeCore/`, one folder per component, and the files include each other with relative
quotes.

Each component folder has a README with its reference: [Utils](XeWeCore/Utils/README.md),
[Serial](XeWeCore/Serial/README.md), [Cli](XeWeCore/Cli/README.md), [Nvs](XeWeCore/Nvs/README.md),
[Settings](XeWeCore/Settings/README.md), [Module](XeWeCore/Module/README.md) and
[Os](XeWeCore/Os/README.md). `Testing/` holds the `$test` hooks that the board tests drive, and it
compiles only with `XEWE_TESTING` defined. `XeWeCore/Config.h` holds the build-time values in the
form [doc/CONFIG.md](../doc/CONFIG.md) specifies.

Includes point one way. `Config.h` includes nothing, so every header can read it. Utils comes
before Serial, and Serial before Cli and Settings. FlexData comes before Nvs. Module depends on
all of them, and `Os/XeWeOs.h` on Module. `Module.h` forward-declares `class Os`, and only `.cpp`
files include `XeWeOs.h`. `Utils/Color.h`, `String.h`, `Pins.h` and `Listeners.h` use the
standard library only, so host tests in other repositories can include them.

Test a change with the host tests:

```sh
ARDUINOJSON_SRC=<path to ArduinoJson>/src tests/unit/run.sh
```
