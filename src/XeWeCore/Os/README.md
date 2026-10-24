# Os and System

- [Os](#os)
- [System](#system)

## Os

`src/XeWeCore/Os/XeWeOs.h`. The Os owns the core services and every registered module.

```cpp
XeWeOs os({
    .version         = "0.1.0",
    .build_timestamp = __DATE__ " " __TIME__,
});

BlinkModule blink(os, {.pin = 8});           // declared after the Os

void setup() { os.begin(); }
void loop()  { os.loop();  }
```

### OsConfig

```cpp
struct OsConfig {
    std::string            version         = {};
    std::string            build_timestamp = {};
    std::string            url             = "https://github.com/xewe-labs/xewe-os-core";
    SerialPortConfig       serial          = {};
    bool                   print_banner    = true;
};
```

| Field | Default | |
|---|---|---|
| `version` | `BUILD_VERSION`, else `"0.0.0"` | printed as `Version <version>` |
| `build_timestamp` | `BUILD_TIMESTAMP`, else empty | printed only when set; `__DATE__ " " __TIME__` is the usual value |
| `url` | this library's repo | printed under a separator; **set it to your own project or clear it** |
| `serial` | see [SerialPortConfig](../Serial/README.md#serialportconfig-and-begin) | `115200` baud, 2048/1024 buffers, 1000 ms startup delay, echo on, from the `XEWE_CORE_SERIAL_*` defines |
| `print_banner` | `true` | the ASCII XeWe banner at the top of the boot log |

`version` and `build_timestamp` left empty are filled by the constructor from `BUILD_VERSION` and
`BUILD_TIMESTAMP` of the tools' generated `<XeWeBuildInfo.h>`, which `XeWeOs.cpp` includes when the
build has it ([configuration](../../../doc/CONFIG.md#build-info)). Without it `version` is
`"0.0.0"` and `build_timestamp` stays empty. A value set in the sketch always wins. The defaults
that come from defines are listed in the core's [`Config.h`](../Config.h).

### Core services

Public members, available to every module as `os.<name>`:

| Member | Type | Docs |
|---|---|---|
| `serial` | `xewe::SerialPort` | [Serial](../Serial/README.md#printing) |
| `nvs` | `xewe::Nvs` | [Nvs](../Nvs/README.md#xewenvs) |
| `cli` | `xewe::Cli` | [Cli](../Cli/README.md#commands-and-groups) |
| `system` | `xewe::System` | [System](#system) |

`system` is a member, so it is always the first module registered and the first to begin.

### Constructor

```cpp
explicit Os(OsConfig config = {});

Os(const Os&)            = delete;
Os& operator=(const Os&) = delete;
```

Non-copyable. Modules hold a reference to it.

The constructor points [`xewe::pins::error_handler`](../Utils/README.md#messages) at
`report_error`, so GPIO claim conflicts from module constructors are queued like registration
errors.

The private `modules` vector and `config` are declared before the public service members. The
vector therefore exists when `system` constructs itself and registers.

### begin

```cpp
void begin();
```

Call once from `setup()`. In order:

1. `serial.begin(config.serial)`, which blocks for `startup_delay_ms`.
2. Points the Nvs error handler and `xewe::flex_error_handler` at `serial.print`. Nvs and FlexData
   errors therefore appear on the console, not in the ESP log.
3. Prints the banner when `config.print_banner` is set, then any errors queued by
   [`report_error`](#report_error) (rejected module ids or command names).
4. With `XEWE_TESTING` defined, registers the `$test` hooks used by the board tests.
5. Reads `init_setup_flag` from the **`root` NVS namespace**. It is unset on the first boot of a
   device.
6. Calls `begin()` on every registered module, in registration order.
7. **On the first boot only:** prints `Initial Setup Complete`, writes `root/init_setup_flag` and
   **restarts the device** if that write succeeded. If NVS cannot be written (init failure,
   missing or full partition, commit error), it prints
   `! NVS write failed: init_setup_flag not saved, not restarting` after the Nvs error and carries
   on. A device with broken NVS stays reachable over the CLI instead of boot-looping. Module
   first-boot setup then runs again on every boot until NVS works.
8. Prints `System Setup Complete`.

**The first boot of a new device ends in a reboot** when NVS works (step 7). Code after
`os.begin()` in `setup()` does not run on that boot. Anything with a one-time side effect outside
NVS has to tolerate running again.

Boot output order: banner → queued errors → the `System` header (device name, version) → each
module's `<name> Setup` header → `System Setup Complete`.

#### First-boot device name

The device name (`system/device_name`) is a default runtime value of the core's
[`Config.h`](../Config.h) ([configuration](../../../doc/CONFIG.md)):

```c
/* Device name (system/device_name), string literal, up to 254 characters; asked at first boot */
#ifndef XEWE_CORE_DEVICE_NAME
#define XEWE_CORE_DEVICE_NAME "xewe-device"
#define XEWE_CORE_DEVICE_NAME_PROMPT 1
#endif
```

* **Not pre-answered** (`XEWE_CORE_DEVICE_NAME_PROMPT` defined): the first boot asks for the name
  and shows `XEWE_CORE_DEVICE_NAME` as the suggestion; an empty answer takes it
  ([begin_routines_init](#begin_routines_init)).
* **Pre-answered** (`XEWE_CORE_DEVICE_NAME` defined before `Config.h` is read, so the
  `_PROMPT` define is not set): no prompt. If `system/device_name` is empty, the first boot writes
  `XEWE_CORE_DEVICE_NAME` there. Either way it prints `Device name: <name>`. A name already in NVS is
  kept, and `$system set_device_name` still renames the device afterwards.

Pre-answer it with a build flag, a string literal:

```bash
xewe build --chip s3 --define 'XEWE_CORE_DEVICE_NAME="Laptop Chiller"'
arduino-cli compile --build-property "compiler.cpp.extra_flags='-DXEWE_CORE_DEVICE_NAME=\"Laptop Chiller\"'" ...
```

The inner single quotes keep a name with spaces in one compiler argument. arduino-cli splits the
recipe on spaces outside quotes; without them `Chiller"` becomes a stray file name.

In an xewe project the line `// #define XEWE_CORE_DEVICE_NAME "xewe-device"` of the project's
`Config.h` does the same once uncommented, and `#define XEWE_CORE_DEVICE_NAME INJECTED_FROM_DOTENV`
takes the name from the dotenv file at build time ([override ladder](../../../doc/CONFIG.md#override-ladder)).

A `#define` in the sketch does **not** work. The name is read by `XeWeOs.cpp`, a library file, so
it has to reach every translation unit: a build flag, or the headers the tools put in front of
every file.

### loop

```cpp
void loop();
```

Call every iteration. Runs `cli.loop()` first, then `loop()` on each **enabled** module. A
disabled module's `loop()` is never called. Public functions of a module that can be disabled
should still start with `if (is_disabled()) return;`, because other code can call them.

### register_module

```cpp
bool register_module(Module& module);
```

Called from `Module`'s constructor; a sketch does not call it. Returns `false` and registers
nothing when the id is empty, contains whitespace, equals `help` in any case, is longer than 15
characters, or is already registered. "Already registered" includes a CLI group whose id differs
only in case. The rejection is reported through `report_error` as
`! Module id '<id>' <reason>: module not registered`. The module gets no CLI group, so it never
begins, never loops and adds no commands. See [Module](../Module/README.md#constructor).

### report_error

```cpp
void report_error(const char* fmt, ...);
```

`printf`-style; prints the whole message, however long. Before `begin()` (static
constructors, Serial not up yet) the message is queued, and `begin()` prints it right after the
banner.

### get_module, get_modules, get_config

```cpp
Module*                       get_module (std::string_view id) const;
const std::vector<Module*>&   get_modules()                    const;
const OsConfig&               get_config ()                    const;
```

`get_module` returns `nullptr` when nothing matches; the match is exact and case-sensitive. Use it
to reach a module you hold no reference to. For a real dependency, prefer a constructor reference
plus `add_requirement` ([Module](../Module/README.md#add_requirement)).

`get_config` is how `System` reads the version, build timestamp and url for the boot header.

### Declaration order

Modules register themselves from their constructors, and globals in one translation unit are
constructed top to bottom. So:

* the Os is declared **first**,
* a module is declared **after** every module it depends on,
* declaration order is begin order is loop order.

```cpp
XeWeOs os({...});
Wifi         wifi(os);
WebInterface web(os, wifi);        // after wifi
```

## System

`src/XeWeCore/Os/XeWeOs.h`. The built-in module: always present, always first, cannot be disabled.

`System` is a member of `Os`, reachable as `os.system`. It is constructed as:

```cpp
Module(os, "system", "System", "Stores integral commands and routines",
       /* requires_init_setup */ true,
       /* can_be_disabled     */ false,
       /* has_cli_commands    */ true)
```

Because it is a member, it registers before any module declared in the sketch, so it begins first
and its boot header is the first thing after the banner.

### Class

```cpp
class System : public Module {
public:
    explicit    System                 (Os& os);

    void        begin_routines_required()                               override;
    void        begin_routines_init    ()                               override;
    void        reset                  (const bool verbose      = false,
                                        const bool do_restart   = true,
                                        const bool keep_enabled = true) override;
    std::string status                 (const bool verbose = false)     const override;

    std::string get_device_name        ();
    void        print_schema_all       ();   // $system schema
    void        restart                (uint16_t delay_ms = 1000);
};
```

### $system commands

| Command | Args | Effect |
|---|---|---|
| `$system restart` | 0 | `restart(1000)` |
| `$system reboot` | 0 | identical alias |
| `$system info` | 0 | chip and build info, [below](#system-info) |
| `$system set_device_name "<name>"` | 1 | stores `system/device_name` and prints `Device name set to: <name>` |
| `$system mac` | 0 | one line per interface that reads back: `wifi_sta`, `wifi_ap`, `bt`, `eth` |
| `$system schema` | 0 | every module's settings as JSON Lines, [below](#system-schema) |
| `$system uid` | 0 | `base_mac <hex>` from the eFuse base MAC, and `uid64 <hex>`: the first 8 bytes of its SHA-256 |
| `$system status` | 0 | inherited, [overridden](#status) to print a table of every module |
| `$system reset` | 0 | inherited, [overridden](#reset): a full factory reset |

There is **no** `$system enable` or `$system disable`, because `can_be_disabled` is `false`.

`$help`, `$system` and `$system help` print the command table ([help](../Cli/README.md#help-output)).

**`set_device_name` does not reboot and does not notify anything.** A module that cached the name
at boot keeps the old one until the next restart.

#### $system info

One `printf`, four lines:

```text
Model <n>  Cores <n>  Rev <n>
IDF <esp-idf version>
Flash <bytes> bytes @ <hz> Hz
MAC <AA:BB:CC:DD:EE:FF>
```

`Model` is the numeric `esp_chip_model_t`. `MAC` is the Wi-Fi station MAC, formatted like
`$system mac`.

#### $system schema

Every module's [settings](../Settings/README.md) as JSON Lines: a header
`{"schema":1,"core":"2.1.0","device":"<name>","modules":["system",...]}`, then each module's rows
(table rows, then `schema_extra` rows) with `"module":"<id>"` first, then
`{"end":"system","count":<rows>}`. `modules` lists every registered module. Implemented by
`System::print_schema_all()`.

### begin_routines_required

Prints the boot header: the device name (`system/device_name`, or `XEWE_CORE_DEVICE_NAME` while
none is stored), `Version <version>`, `Build Timestamp <build_timestamp>` when set, and the url when
set, the last three from the Os config. Then it calls:

```cpp
esp_log_level_set("*", ESP_LOG_NONE);
```

**This silences all ESP-IDF logging for the entire firmware**, not just this library. Every
`ESP_LOGE`/`ESP_LOGW`/`ESP_LOGI` from the IDF, from Wi-Fi and from any other library goes quiet
from the first boot header on. The console is a user interface here, not a log. When something
should have logged and did not, undo this first.

It also mutes the Nvs default `ESP_LOGE` sink. That is harmless: `Os::begin` has already pointed
Nvs errors at the serial console.

### begin_routines_init

The one-time device naming, run until it is confirmed:

```
Name your device (Enter for "xewe-device"):
>
Kitchen Lights
Confirm "Kitchen Lights"?
(y/n) >
y
```

The `>` marker is printed on its own line, so typed input echoes on the line below it. The
suggestion in the prompt is `XEWE_CORE_DEVICE_NAME`; an empty answer takes it, so the confirmation
then reads `Confirm "xewe-device"?`. A "no" asks for the name again.

The confirmed value is written to `system/device_name`.

With a pre-answered `XEWE_CORE_DEVICE_NAME` there is no prompt: the name is written when
`system/device_name` is empty and `Device name: <name>` is printed. See
[First-boot device name](#first-boot-device-name).

### status

```cpp
std::string status(const bool verbose = false) const override;
```

With `verbose`, prints a table titled `System Status` with a row per registered module. The
`Status` cell is that module's `status(false)`; for `System` itself that is `System OK`. A module
with a settings table adds its `key: value` lines to the cell.

```
+-----------------------------------------------+
|                 System Status                 |
+-------------+---------+-----------------------+
| Module Name | Enabled | Status                |
+-------------+---------+-----------------------+
| System      | Yes     | System OK             |
+-------------+---------+-----------------------+
| Blink       | No      | Blink module disabled |
+-------------+---------+-----------------------+
```

**The return value is the literal string `"System OK"`, not the table.** The table is printed as a
side effect and is not obtainable as a string from here.

### reset

```cpp
void reset(const bool verbose = false, const bool do_restart = true,
           const bool keep_enabled = true) override;
```

A **factory reset**:

1. When `verbose`, prints `[WARNING] / Resetting System / Will reset all modules` and asks `OK?`
   with a bounded prompt: two attempts of 15 s, default "no"; a typo or a timeout re-prompts once.
   A "no" prints `Aborted`. A second timeout or invalid answer prints
   `! No answer: reset cancelled`, then `Aborted`. Nothing is reset in either case.
2. Calls `reset(true, false, false)` on every other registered module. Each namespace is wiped,
   with no reboot in between.
3. Calls `nvs.erase_all()`, which wipes the **entire NVS partition**. That includes
   `root/init_setup_flag`, so the next boot runs the whole initial setup again, and data that
   belongs to other libraries.
4. Calls `Module::reset(verbose, do_restart, keep_enabled)`.

**The confirmation is mandatory.** Without `verbose` there is no prompt and the reset counts as
not confirmed, so `system.reset(false, ...)` from code prints `Aborted` and does nothing. Only a
call with `verbose = true`, such as `$system reset`, can reset the device.

### get_device_name

```cpp
std::string get_device_name();
```

Reads `system/device_name`, returning `""` when it has never been set.

**It is not `const`**, so it cannot be called from a `const` member function, such as a
`status() const` override. Cache the name in your module instead.

### restart

```cpp
void restart(uint16_t delay_ms = 1000);
```

Prints a `Rebooting` header, waits `delay_ms`, then calls `ESP.restart()`. The delay gives the
serial buffer time to flush so the user sees why the device went away.

This is what every module's `enable`, `disable` and `reset` call when `do_restart` is true.
