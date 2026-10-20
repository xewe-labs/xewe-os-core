# XeWeCore documentation

XeWeCore is a modular firmware core for ESP32: a serial console, a `$group command` command line,
typed NVS storage, helpers and a module framework, in one Arduino library. Sketches include
`<XeWeCore.h>`; the component headers under `src/XeWeCore/` can be included after it.

## Reading path

1. **[Concepts](concepts.md)**: what the core is for, modules, the console, storage, the
   settings schema, listeners, and the principles behind them.
2. **Pick your level** (below) and run its example.
3. **[Os](../src/XeWeCore/Os/README.md#os) → [Module](../src/XeWeCore/Module/README.md) → [Settings table](../src/XeWeCore/Settings/README.md)**: the three
   pages a module author needs.
4. **[Configuration](config.md)**: the build-time values, their names and how a build overrides
   them; the same scheme for the core, the modules and xewe projects.
5. **The reference pages** below, when you need the exact behaviour of a function, command or
   stored key.

## Three levels

| Level | Who | Tooling | What you get |
|---|---|---|---|
| 1 | Arduino IDE user | Library Manager → `XeWeCore`; compile, upload | the console: `$help`, `$system status`, a device name in NVS, prompts. Example [`01_Hello`](../examples/01_Hello/01_Hello.ino) |
| 2 | Arduino IDE user | the same, plus one module of your own in the sketch folder | your own `$mymodule …` commands, settings in NVS, enable/disable. Example [`02_MyModule`](../examples/02_MyModule/02_MyModule.ino) |
| 3 | project builder | the [xewe-os](https://github.com/xewe-labs/xewe-os) template and its build tools | ready-made modules (Wi-Fi, web interface, scheduler, …), multi-chip builds, board tests, releases |

The modules repository is not an Arduino library: ready-made modules are level 3. Level 2 is
always *your own* module.

## Reference

### Configuration: `src/XeWeCore/Config.h`

| Section | Covers |
|---|---|
| [The module Config.h](config.md#the-module-configh) | the file, its two sections, the entry form, the values the first boot asks for and `_PROMPT` |
| [Names](config.md#names) | `XEWE_<SLUG>_<PARAM>`, the settings-key rule, no prefix nesting |
| [The project's Config.h](config.md#the-projects-configh) | the core and module blocks, pre-answering, the `INJECTED_FROM_DOTENV` sentinel |
| [Override ladder](config.md#override-ladder) | `--define`, dotenv, project, module fallback; the three generated or project headers |
| [The dotenv file](config.md#the-dotenv-file), [Releases](config.md#releases) | injection, errors, provisioning keys; what a release refuses |
| [Build info](config.md#build-info) | `XeWeBuildInfo.h`: `BUILD_VERSION`, `BUILD_TIMESTAMP`, `BUILD_CHIP`, `XEWE_CHIP_<X>` |
| [What a validator checks](config.md#what-a-validator-checks) | the rules a module's `Config.h` passes |

### Os: `src/XeWeCore/Os/XeWeOs.h`, `Module/Module.h`, `Settings/Settings.h`

| Section | Covers |
|---|---|
| [Os](../src/XeWeCore/Os/README.md#os) | `xewe::Os` / `XeWeOs`, `OsConfig`, `begin`, `loop`, module lookup, the core services, the first-boot device name (`XEWE_CORE_DEVICE_NAME`) |
| [Module](../src/XeWeCore/Module/README.md) | `xewe::Module`: constructor, lifecycle, enable/disable/reset, requirements, commands, listeners, NVS keys |
| [Settings table](../src/XeWeCore/Settings/README.md) | the settings table: `setting<>`, flags, `$<id> set\|get\|schema`, schema lines, `schema_extra` |
| [System](../src/XeWeCore/Os/README.md#system) | `xewe::System`, the built-in module, and the `$system` commands including `$system schema` |

### Serial: `src/XeWeCore/Serial/Serial.h`

| Section | Covers |
|---|---|
| [SerialPortConfig and begin](../src/XeWeCore/Serial/README.md#serialportconfig-and-begin) | `xewe::SerialPortConfig` and `begin` |
| [Printing](../src/XeWeCore/Serial/README.md#printing) | `print`, `printf`, boxes, separators, headers, tables |
| [Reading lines](../src/XeWeCore/Serial/README.md#reading-lines) | non-blocking line input: `loop`, `has_line`, `read_line` |
| [Prompts](../src/XeWeCore/Serial/README.md#prompts) | blocking typed prompts: `get_string`, `get_int`, `get_yn`, ... |

### Cli: `src/XeWeCore/Cli/Cli.h`

| Section | Covers |
|---|---|
| [Commands and groups](../src/XeWeCore/Cli/README.md#commands-and-groups) | `Command`, groups, registration |
| [Executing commands](../src/XeWeCore/Cli/README.md#executing-commands) | the two `execute` overloads, tokenizer and error strings |
| [Help output](../src/XeWeCore/Cli/README.md#help-output) | `$help` output |

### Nvs: `src/XeWeCore/Nvs/Nvs.h`, `Nvs/FlexData.h`

| Section | Covers |
|---|---|
| [xewe::Nvs](../src/XeWeCore/Nvs/README.md#xewenvs) | `xewe::Nvs`: typed read/write, namespaces, errors |
| [xewe::FlexData\<T\>](../src/XeWeCore/Nvs/README.md#xeweflexdatat) | `xewe::FlexData<T>`: declare fields once, get blob and JSON forms; type rules, field presence |
| [Blob format and versioning](../src/XeWeCore/Nvs/README.md#blob-format-and-versioning) | the stored byte layout and how to version a struct |

### Utils: `src/XeWeCore/Utils/Utils.h`

| Section | Covers |
|---|---|
| [xewe::str](../src/XeWeCore/Utils/README.md#xewestr) | `xewe::str`: case, hex colours (aliases of `xewe::color`), trimming, parsing, wrapping, formatting, box lines |
| [xewe::validate](../src/XeWeCore/Utils/README.md#xewevalidate) | `xewe::validate<T>` |
| [xewe::AsyncTimer\<T\>](../src/XeWeCore/Utils/README.md#xeweasynctimert) | `xewe::AsyncTimer<T>` |
| [xewe::color](../src/XeWeCore/Utils/README.md#xewecolor) | `xewe::color`: HSV/RGB, hex colour strings |
| [xewe::pins](../src/XeWeCore/Utils/README.md#xewepins) | `xewe::pins`: GPIO ownership registry, strapping pins |
| [xewe::span](../src/XeWeCore/Utils/README.md#xewespan) | `xewe::span` |
| [xewe::LockGuard](../src/XeWeCore/Utils/README.md#xewelockguard) | `xewe::LockGuard` |
| [Debug macros](../src/XeWeCore/Utils/README.md#debug-macros) | `DBG_*` macros and `DEBUG_<Class>` flags |

`xewe::ListenerSet` (`Utils/Listeners.h`) is documented with modules:
[Module: Listeners](../src/XeWeCore/Module/README.md#listeners).

## Also

* [Configuration](config.md): build-time values for the core, the modules and xewe projects.
* [Examples](examples.md): what each sketch in `examples/` shows.
* [Tests](tests.md): the host unit tests and the board tests.
* [Library rules](library-rules.md): what keeps XeWeCore a valid Arduino library (layout,
  `library.properties`, `library.json`, names).
* Rules for changing the core (layout, include direction, what a change must carry):
  [`.agents/AGENTS.md`](../.agents/AGENTS.md).
