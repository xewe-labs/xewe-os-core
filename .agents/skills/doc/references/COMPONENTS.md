# Component pitfalls

Facts per component that are easy to break. The full reference is the component's `README.md`
under `src/XeWeCore/`.

## Contents

- Utils
- Serial
- Cli
- Nvs and FlexData
- Os, Module and System

## Utils

- Header-only. `Color.h`, `String.h`, `Pins.h` and `Listeners.h` use the standard library only.
  `Pins.h` may include `<sdkconfig.h>` behind `__has_include`.
- `color::hsv_to_rgb` is pinned bit for bit by the test `color_hsv_to_rgb_pinned`.
- `color::parse_hex_color`, also reachable as `str::` through `String.h`, accepts exactly
  `rrggbb` or `#rrggbb` and leaves its outputs untouched on failure. `to_hex_color` writes
  uppercase `#RRGGBB`.
- `xewe::pins` is a fixed table. `claim` refuses a pin held by another owner or out of range and
  only warns on a strapping pin. The strapping lists cite datasheets in
  `src/XeWeCore/Utils/README.md`.
- `lower` and `to_lower` are both public and both have callers. Keep both.
- `xewe::validate` delegates to `str::parse_int` and `str::parse_float`.

## Serial

- The type is `xewe::SerialPort`, because `Serial` is a core macro.
- In prompts, `retry_count == 0` means infinite and `timeout_ms == 0` means no timeout. Modules
  rely on those defaults.
- The core's own confirmations in `Module::disable` and `System::reset` are bounded:
  `get_yn("OK?", 2, 15000, false, answered)`.
- `get_core` sets `success_sink` on every exit path. A new prompt type goes through it.
- A line buffer is 255 bytes, 254 usable. The queue holds 4 lines. An over-long line is dropped
  whole with one notice.
- Output is CRLF. `print` wraps only when `message_width > 0`. There is no `println`, so use
  `print` or `printf`.
- Table cells are `std::string_view`, so callers keep them alive.

## Cli

- Handlers get a `xewe::span` into a local vector. Copy what you keep.
- The parsed `execute` matches on the name only. The direct one matches on the name and
  `arg_count`.
- `$<group>`, `$<group> help` and `$help <group>` all print the group.
- The argument count is checked before a handler runs.
- `add_group` on an existing id keeps its commands. `Os::register_module` validates module ids
  earlier, through `Cli::name_error`.

## Nvs and FlexData

- Everything here persists across reflashes (`STABILITY.md`).
- Version a struct with a `schema` field. `kBlobVersion` is one shared constant for the library.
- `from_blob` overwrites in place.
- Read misses are silent. Name errors, init failures (reported once), the automatic partition
  erase and open, set and commit failures are reported with the exact text in
  `src/XeWeCore/Nvs/README.md`.
- FlexData JSON assignment is type-matched: `is<M>()` before `as<M>()`.
- Field presence is a `uint32_t`, so a struct has at most 32 fields. Only the JSON load sets it,
  and it is never stored.
- `FlexData.h` stays platform-neutral.

## Os, Module and System

- `System` is the only module in this repository.
- `disable()` resets the module, which wipes its namespace, and cascades to its dependents. With
  `verbose == false` it asks no confirmation. `System::reset()` erases the whole partition.
- The first-boot name prompt runs only under `#ifdef XEWE_CORE_DEVICE_NAME_PROMPT`, which
  `Config.h` sets while `XEWE_CORE_DEVICE_NAME` is not pre-answered. A pre-answer is a build flag
  or, with the tools, a project `Config.h` line or a dotenv value. A sketch `#define` never
  reaches `XeWeOs.cpp`.
- The lifecycle order in `Module::begin()` is part of the contract
  (`src/XeWeCore/Module/README.md`).
- In `Os`, the private `modules` vector is declared before the service members. Do not reorder
  them.
- `Module` is neither copyable nor movable.
- `System::begin_routines_required()` silences the ESP log on purpose.
- A firmware reaches the settings engine only through `settings_engine`, so one without a table
  does not link it. Never call `detail::settings_*` or `register_settings_commands` from code
  that always links.
- Secrets are never printed.
- A change to the schema line format raises `"schema":1` in `Settings::header` and updates
  `src/XeWeCore/Settings/README.md`.
- `ListenerSet::notify` re-reads each slot, so `remove` during `notify` is safe.
