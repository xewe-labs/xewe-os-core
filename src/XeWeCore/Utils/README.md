# Utils

- [xewe::str](#xewestr)
- [xewe::validate](#xewevalidate)
- [xewe::AsyncTimer\<T\>](#xeweasynctimert)
- [xewe::color](#xewecolor)
- [xewe::pins](#xewepins)
- [xewe::span](#xewespan)
- [xewe::LockGuard](#xewelockguard)
- [Debug macros](#debug-macros)
- [Listeners](#listeners)

## xewe::str

`src/XeWeCore/Utils/String.h`: string helpers: case, hex, trimming, splitting, wrapping, box
drawing, and parsers for numbers, times and days.

Everything here is `inline` and header-only. Arguments are taken as `std::string_view` where the
function only reads, and by value as `std::string` where it returns a modified copy.

### Macros

```cpp
#define STRINGIFY_XEWE(x) #x
#define TO_STRING(x)      STRINGIFY_XEWE(x)
```

Global, not namespaced. `TO_STRING` expands its argument first, so it turns a macro into its
value: `TO_STRING(BUILD_VERSION)`.

### Constants

```cpp
inline constexpr char kCRLF[] = "\r\n";
```

The line ending used across XeWe serial output.

### Case and hex

```cpp
inline std::string lower     (std::string s);
inline std::string to_lower  (std::string s);
inline std::string upper     (std::string s);
inline std::string capitalize(std::string s);
inline std::string to_hex    (const uint8_t* b, size_t n);
```

| | |
|---|---|
| `lower` / `to_lower` | two separate implementations of the same thing; prefer `lower` |
| `upper` | uppercases every character |
| `capitalize` | title-cases each word: uppercase first alphanumeric of a run, lowercase the rest. Any non-alphanumeric character starts a new word |
| `to_hex` | uppercase hex of `n` bytes, no separators and no `0x` prefix |

### Hex colours

```cpp
using color::parse_hex_color;
using color::to_hex_color;
```

`parse_hex_color` and `to_hex_color` are defined in `Color.h` as `xewe::color::` (see
[xewe::color](#hex-colours-1)). `String.h` includes `Color.h` and makes them reachable as
`xewe::str::parse_hex_color` / `xewe::str::to_hex_color` too: both names are the same function.
Code that needs only the hex helpers, such as a host-tested pure header, includes `Color.h`.

### Trimming and splitting

```cpp
inline void                          trim          (std::string& s);
inline void                          rtrim_cr      (std::string& s);
inline std::vector<std::string_view> split_lines_sv(std::string_view text, char delim = '\n');
inline std::vector<std::string>      split_by_token(std::string_view s, std::string_view token);
```

| | |
|---|---|
| `trim` | in place; strips leading and trailing ` `, `\t`, `\r`, `\n` |
| `rtrim_cr` | in place; removes **one** trailing `\r`, for CRLF input |
| `split_lines_sv` | splits on `delim`; always emits a final element, which is empty when the text ends with the delimiter |
| `split_by_token` | splits on a multi-character separator; an empty separator returns the whole input as one element |

**`split_lines_sv` returns views into its argument.** The input must outlive the result; splitting
a temporary is a dangling read.

### Wrapping and alignment

```cpp
inline std::vector<std::string> wrap_fixed    (std::string_view s, size_t width);
inline std::vector<std::string> wrap_words    (std::string_view s, size_t width);
inline std::string              align_into    (std::string_view s, size_t width, char align);
inline std::string              repeat        (char ch, size_t count);
inline std::string              repeat_pattern(std::string_view pat, size_t count);
```

| | |
|---|---|
| `wrap_fixed` | hard character chunks of exactly `width`, ignoring word boundaries |
| `wrap_words` | greedy word wrap; words longer than `width` are hard-split; runs of whitespace collapse to one space |
| `align_into` | pads `s` to `width`; `'r'` right, `'c'` centre (extra pad goes right), anything else left |
| `repeat` | `count` copies of one character |
| `repeat_pattern` | cycles `pat` until `count` characters are produced; an empty pattern yields spaces |

Edge cases: both wrappers return the input unchanged as a single element when `width == 0`;
`wrap_words` on empty input yields one empty string. `align_into` returns `s` unchanged when it is
already at least `width` long, or when `width == 0`.

### Box drawing

```cpp
inline std::string make_spacer_line(uint16_t total_width, std::string_view edge = "|");
inline std::string make_rule_line  (uint16_t total_width, std::string_view fill = "-",
                                    std::string_view edge = "+");
inline std::string compose_box_line(std::string_view content,
                                    std::string_view edge,
                                    size_t           message_width,
                                    size_t           margin_l,
                                    size_t           margin_r,
                                    char             align);
```

`make_spacer_line` draws `|` + spaces + `|`; `make_rule_line` draws `+` + `---` + `+`, with `fill`
cycled by `repeat_pattern` so multi-character fills such as `"-="` work. Both return `{}` when
`total_width` is `0`, and degrade to a truncated edge string when the width is no larger than the
edges.

`compose_box_line` builds one content row: `edge`, `margin_l` spaces, the payload, `margin_r`
spaces, `edge`. When `message_width` is `0` the content is emitted as-is with no field width and
no alignment; otherwise it is padded to `message_width` with `align_into`. These three are what
[`xewe::SerialPort`](../Serial/README.md#printing)
renders its headers, separators and tables with.

### Formatting

```cpp
inline std::string vformat(const char* fmt, va_list ap);
```

`vsnprintf` into a `std::string`. Returns `{}` for a null `fmt` or a non-positive formatted length.

**On GCC and Clang it is exact** (a two-pass `vsnprintf` sizes the result first). On any other
compiler it falls back to a **256-byte stack buffer and truncates** silently. The ESP32 toolchain
is GCC, so on device the result is exact.

```cpp
inline std::string format(const char* fmt, ...);
```

The variadic form of `vformat`, with the same guarantees, for a `std::string` instead of direct
output:

```cpp
Serial.print(xewe::str::format("hue %3u\n", hue).c_str());
```

### Number parsing

```cpp
template <typename T, typename = std::enable_if_t<std::is_integral<T>::value>>
inline bool parse_int(std::string_view s, T& out);
```

Writes to `out` and returns `true` only on a clean parse. It trims surrounding whitespace, accepts
**base 10 only**, rejects trailing characters, and range-checks against
`std::numeric_limits<T>`. Signed `T` goes through `strtoll`, unsigned through `strtoull`.

A leading `-` for an unsigned `T` is rejected (`"-1"`, `"-0"`), and a value beyond the 64-bit
range (`strtoll`/`strtoull` set `ERANGE`) fails instead of saturating: `parse_int<uint64_t>("-1", out)`
and `parse_int<long long>("9223372036854775808", out)` both return `false`.

```cpp
template <typename T, typename = std::enable_if_t<std::is_floating_point<T>::value>>
inline bool parse_float(std::string_view s, T& out);
```

The same contract for floating-point types, through `strtod`. It trims, rejects trailing
characters, and reports `false` on overflow (`ERANGE`), which also fires on denormal
**underflow**, so `parse_float<double>("1e-320", d)` returns `false`. Unlike `parse_int` it is not
base 10 only: `strtod` also reads `inf`, `nan` and hex forms such as `0x1p3`.

Both functions copy the view into a `std::string` first, so neither is allocation-free.

[`xewe::validate`](#xewevalidate) wraps both and adds a range check.

### Time and day parsing

```cpp
inline bool parse_time      (std::string_view time_str, uint16_t& minutes);
inline bool parse_day       (std::string_view day_str,  uint8_t&  day_num);
inline bool parse_gmt_offset(std::string_view s, std::string& normalized_gmt);
```

**`parse_time`** reads `H:MM` with `sscanf` and writes minutes since midnight. Accepts `00:00`
through `23:59`, **plus the special value `24:00`** (`1440`), which schedulers use as an
end-of-day marker. Anything else returns `false`.

**`parse_day`** takes a two-letter, case-insensitive day and writes its index:

| `MO` | `TU` | `WE` | `TH` | `FR` | `SA` | `SU` |
|---|---|---|---|---|---|---|
| 0 | 1 | 2 | 3 | 4 | 5 | 6 |

Only the two-letter form is accepted: `"Mon"` and `"Monday"` both fail.

**`parse_gmt_offset`** normalizes a timezone offset into `GMT±HH:MM`:

| Input | Result |
|---|---|
| `GMT`, `GMT0`, `UTC`, `UTC0` | `GMT+00:00` |
| `GMT-8`, `GMT+12` | `GMT-08:00`, `GMT+12:00`: one or two digits are hours |
| `GMT+5:30`, `GMT+05:30` | `GMT+05:30`: sign, then `H:MM` or `HH:MM` |
| `GMT+0530`, `GMT+530` | `GMT+05:30`: three or four digits are `HHMM` |

Lower case is accepted (`gmt-8`). After the sign only digits and one colon are allowed. Anything
after the offset is rejected: `GMT+5x`, `GMT+5:30 ` and `GMT+05:30x` return `false`. So do a
second sign (`GMT++5`), a space (`GMT+ 5`), one minute digit (`GMT+5:3`) and five or more digits.

Range: `0 ≤ h ≤ 14`, `0 ≤ m < 60`, and `h == 14` requires `m == 0`. Anything outside that, or a
string not starting with `GMT`, returns `false` and leaves `normalized_gmt` untouched.

### Command extraction

```cpp
inline std::vector<std::string> extract_commands(std::string_view blob);
inline std::string              escape_json     (std::string_view s);
```

`extract_commands` pulls double-quoted segments out of a blob, honouring `\` escapes. If exactly
one segment comes out and that segment itself contains two or more unescaped quotes, it recurses
once into it, which unwraps a command list that arrived as a JSON string inside a JSON string.

`escape_json` escapes `"` and `\` only. It is not a general JSON escaper: control characters,
newlines and non-ASCII bytes pass through unchanged.

## xewe::validate

`src/XeWeCore/Utils/Validator.h`: parse a string into `T` and range-check it in one call.

```cpp
if (auto level = xewe::validate<uint8_t>(args[0], 0, 255)) {
    analogWrite(pin, *level);
} else {
    serial.print("Level must be 0-255.");
}
```

### validate

```cpp
template <typename T, typename LimitT>
std::optional<T> validate(std::string_view value, LimitT min, LimitT max);
```

Returns the parsed value, or `std::nullopt` if it does not parse or falls outside `[min, max]`.

`LimitT` is a separate template parameter so plain literals deduce naturally: `validate<uint8_t>(s, 0, 255)`
compiles without casting the bounds.

| `T` | What `min`/`max` mean | Parsed with |
|---|---|---|
| `std::string` | **string length**, inclusive | no parsing; the view is copied |
| signed integral | numeric range, inclusive | `xewe::str::parse_int<T>` |
| unsigned integral | numeric range, inclusive | `xewe::str::parse_int<T>` |
| `float`, `double` | numeric range, inclusive | `xewe::str::parse_float` |
| anything else, **including `bool`** | none | compile error |

An unsupported `T` fails with `static_assert`:
`"Unsupported Validator::validate<T>() type."`

### Notes

* **Exception-free.** It delegates to [`xewe::str::parse_int`](#number-parsing) and
  `parse_float`, which report failure by returning `false`. It compiles with `-fno-exceptions`.
* **Trailing characters are rejected.** `validate<int>("12abc", 0, 100)` and
  `validate<int>("1.5", 0, 100)` return `std::nullopt`.
* **Integers are base 10 only.** `validate<int>("0x1F", 0, 255)` returns `std::nullopt`.
  Surrounding whitespace is trimmed and a leading `+`/`-` is accepted. `float`/`double` go through
  `strtod`, which also reads hex forms (`"0x1p3"` is `8`).
* **The value must fit `T` itself**, whatever the bounds: `validate<int8_t>("300", 0, 1000)`
  returns `std::nullopt`, never a truncated `44`.
* **It allocates.** Each call copies the view into a `std::string` before parsing.
* `min` and `max` are **not** swapped if you pass them inverted. An inverted range simply matches
  nothing and every call returns `std::nullopt`. (The `SerialPort` numeric prompts do swap; this
  does not.)
* The header also exposes `template <typename> struct always_false : std::false_type {};`, used
  for the `static_assert` above.

## xewe::AsyncTimer\<T\>

`src/XeWeCore/Utils/AsyncTimer.h`: non-blocking interpolation between two values over a fixed
duration.

```cpp
xewe::AsyncTimer<uint8_t> fade(2000, 0, 255);  // 0 -> 255 over 2 s

void start_fade() { fade.initiate(); }       // nothing moves until this is called

void loop() {
    if (fade.is_active()) analogWrite(pin, fade.get_current_value());
}
```

`T` must be arithmetic; anything else is a `static_assert` failure
(`"AsyncTimer<T> requires an arithmetic type"`).

Debug flag: `DEBUG_AsyncTimer`, defaulted to `0` in the header. See [Debug macros](#debug-macros).

### Constructor

```cpp
AsyncTimer(uint32_t delay, T start = T(), T target = T());
```

| Parameter | |
|---|---|
| `delay` | duration of the interpolation, in milliseconds |
| `start` | value at progress `0.0` |
| `target` | value at progress `1.0` |

Constructing does **not** start the timer. `is_active()` is `false` until `initiate()`.

### initiate

```cpp
void initiate();
```

Starts (or restarts) the run: stamps `millis()`, clears `done`, sets `progress` to `0.0` and
`initiated` to `true`. It back-dates the internal calculation stamp so the first sample is not
throttled.

### reset

```cpp
void reset();
void reset(T new_start, T new_target);
void reset(uint32_t new_delay, T new_start, T new_target);
```

Clears all state, including `initiated`, so **a fresh `initiate()` is required** before the timer
runs again. The two- and three-argument overloads replace the endpoints (and the delay) first,
then do the same reset.

### get_current_value

```cpp
T get_current_value() const;
```

Recomputes progress (subject to the throttle below) and returns the interpolated value. Returns
`target` exactly once the run is done; otherwise `T(start + (target - start) * progress)`.

### Other getters

```cpp
T        get_start_value () const;
T        get_target_value() const;
double   get_progress    () const;
uint32_t get_delay_ms    () const;
bool     is_done         () const;
bool     is_not_done     () const;
bool     is_active       () const;
```

| | |
|---|---|
| `get_progress` | `0.0`-`1.0`. **Does not recompute**, see the note below |
| `is_done` | recomputes, then reports whether the run has finished |
| `is_not_done` | `!is_done()` |
| `is_active` | whether `initiate()` has been called and `terminate()`/`reset()` has not |

### terminate

```cpp
void terminate();
```

Stops the run early by clearing `initiated`. It leaves `done` and `progress` at their last values,
and because the internal recalculation early-returns when `!initiated`, `is_done()` keeps
reporting whatever it reported before. Use `reset()` when you want the state cleared too.

### debug_dump

```cpp
void debug_dump(const char* label = "DUMP") const;
```

Prints the full internal state through `DBG_PRINTF`, so it produces output only when
`DEBUG_AsyncTimer=1`. `initiate()` and `reset()` call it themselves.

### Notes

* **Progress is recomputed at most every 5 ms** (`calc_interval_ms`, private, from the
  compile-time constant `XEWE_CORE_TIMER_TICK_MS` of the core's [`Config.h`](../Config.h); `0`
  recomputes on every call), and only from `get_current_value()` and `is_done()`.
  `get_progress()` returns the cached value, so it can be up to one tick stale, or `0.0` if
  neither of the other two has been called since `initiate()`.
* All the state getters are `const`; the cached fields are `mutable` to allow it.
* **Integral `T` truncates.** The interpolation is done in `double` and cast back, so an
  `AsyncTimer<int>` steps rather than glides, and a short `delay` over a wide range skips values.
* **A descending run needs a signed or small `T`.** The expression evaluates `target - start` in
  `T`'s promoted type: `uint8_t` and `uint16_t` promote to `int` and are fine, but an
  `AsyncTimer<uint32_t>` with `target < start` wraps around and produces nonsense. Use a signed
  type for a countdown.
* Nothing here uses interrupts or tasks. Progress advances only when you call a getter.

## xewe::color

`src/XeWeCore/Utils/Color.h`: HSV ⇄ RGB conversion for 8-bit channels, and hex colour strings.

**Host-includable:** the header uses the standard library only (no `<Arduino.h>`), so pure code
such as effect math can include it and build in host tests. `tests/unit/run.sh` compiles it
without the Arduino shim to keep it that way.

**All six HSV/RGB channels are `0-255`,** including hue and saturation. Hue is *not* 0-360 and saturation
and value are *not* 0-100. This is the most common mistake with these two functions.

### hsv_to_rgb

```cpp
inline std::array<uint8_t, 3> hsv_to_rgb(const std::array<uint8_t, 3>& hsv);
```

`{hue, saturation, value}` → `{red, green, blue}`.

```cpp
auto rgb = xewe::color::hsv_to_rgb({0, 255, 255});      // full-saturation red
analogWrite(pin_r, rgb[0]);
```

### rgb_to_hsv

```cpp
inline std::array<uint8_t, 3> rgb_to_hsv(const std::array<uint8_t, 3>& rgb);
```

`{red, green, blue}` → `{hue, saturation, value}`. Returns hue `0` for any greyscale input
(`r == g == b`), since hue is undefined there.

### Hex colours

```cpp
inline bool        parse_hex_color(const std::string& s, uint8_t& r, uint8_t& g, uint8_t& b);
inline std::string to_hex_color   (uint8_t r, uint8_t g, uint8_t b);
```

| | |
|---|---|
| `parse_hex_color` | accepts `rrggbb` or `#rrggbb`: exactly six hex digits, either case, at most one leading `#`. Returns `false` and leaves `r`/`g`/`b` untouched for anything else: `""`, `#`, `#ff`, `fff`, `ff00zz`, seven digits, `##00ffff`, `0xff00`, a sign, spaces |
| `to_hex_color` | `#RRGGBB`, uppercase like `str::to_hex`; `parse_hex_color` reads it back |

`String.h` includes `Color.h` and keeps both as `xewe::str::parse_hex_color` /
`xewe::str::to_hex_color` (using-declarations: the same functions under a second name), so either
spelling works.

```cpp
uint8_t r, g, b;
if (!xewe::color::parse_hex_color(args[0], r, g, b)) { os.serial.print("! Expected RRGGBB"); return; }
```

### Notes

* **Conversion is lossy.** Both functions work in `float` internally and truncate with
  `static_cast<uint8_t>` on the way out, so a round trip does not always return the original
  triplet. Expect drift of a unit or so, most visibly at hue boundaries.
* No clamping is needed or performed: `uint8_t` inputs are already in range.
* Everything here is `inline` and header-only; there is nothing to link.
* **`hsv_to_rgb` is pinned bit for bit** by `tests/unit` (`color_hsv_to_rgb_pinned`: spot values
  and a checksum over a 256 × 256 × 16 grid). Effect code, such as an LED strip's colour modes,
  calls it and depends on its exact output, so the arithmetic does not change (operation order
  included: an FMA-contracted build already gives different bytes).

## xewe::pins

`src/XeWeCore/Utils/Pins.h`: which module owns which GPIO, and which GPIOs are strapping pins on
the chip being built for. Header-only, host-includable, no heap.

```cpp
if (!xewe::pins::claim(cfg.pin, id.c_str())) return;   // in a module's begin, before pinMode
...
xewe::pins::release(cfg.pin, id.c_str());              // when the module lets the pin go
```

The core's own `System` module claims no pins. A pin that nobody claims is not checked: two
modules that both claim their pins are protected from each other, and a module that does not
claim is invisible to the registry.

### claim, release, owner_of

```cpp
inline bool        claim   (int gpio, const char* owner);
inline bool        release (int gpio, const char* owner);
inline const char* owner_of(int gpio);
```

| | |
|---|---|
| `claim` | `true` when the pin was free (now `owner`'s) or already `owner`'s (names compared with `strcmp`). `false` when another owner holds it, and for a GPIO outside `0`–`48`. A null `owner` is stored as `"?"` |
| `release` | frees the pin if `owner` holds it (names compared with `strcmp`); `false` and no change otherwise |
| `owner_of` | the owner's name, or `nullptr` when free or out of range |

**The owner pointer is stored, not copied:** pass a string literal or a module's `id.c_str()`
(stable for the module's lifetime), never a temporary.

**A strapping pin is claimed with a warning, never refused.** Its level at reset selects the boot
mode, so a pull-up, pull-down or load on it can stop the chip from booting normally; the module
author decides whether that matters for the hardware.

### Messages

Reported through `xewe::pins::error_handler`, called as `error_handler(error_context, message)`:

```cpp
inline void (*error_handler)(void* context, const char* message) = nullptr;
inline void*  error_context = nullptr;
```

A plain function pointer rather than a `std::function` (as `flex_error_handler` is) because a
`std::function` global costs flash and RAM in every firmware that includes the header, claim or
not. The `Os` constructor points it at [`Os::report_error`](../Os/README.md#report_error), so a claim
from a module constructor is queued and printed after the banner. Unset (no `Os`), the registry is
silent.

| Case | Message |
|---|---|
| held by someone else | `! GPIO 8 already claimed by led, refused for fan` |
| out of range | `! GPIO 60 out of range (0-48): not claimed by fan` |
| strapping pin (claimed) | `! GPIO 8 is a strapping pin (led): its level at reset selects the boot mode` |

The strapping warning is printed once, when the pin goes from free to claimed.

### Strapping pins

```cpp
inline constexpr uint64_t kStrappingEsp32, kStrappingEsp32C3, kStrappingEsp32C6, kStrappingEsp32S3;
inline constexpr uint64_t kStrapping;          // the one for CONFIG_IDF_TARGET_*, 0 on the host
constexpr bool            is_strapping(int gpio);
```

| Chip | Strapping GPIOs | Source |
|---|---|---|
| ESP32-C3 | 2, 8, 9 | ESP32-C3 datasheet, "Strapping Pins" |
| ESP32-C6 | 4 (MTMS), 5 (MTDI), 8, 9, 15 | ESP32-C6 datasheet, "Boot Configurations"; core 3.3.12 `soc/esp32c6/register/soc/io_mux_reg.h` (GPIO4 = MTMS, GPIO5 = MTDI) and `efuse_reg.h` (JTAG select strap on GPIO15) |
| ESP32-S3 | 0, 3, 45, 46 | ESP32-S3 datasheet, "Boot Configurations"; core 3.3.12 `variants/waveshare_esp32_s3_rgb_matrix/pins_arduino.h` ("GPIO45 and GPIO46 are strapping pins") |
| ESP32 | 0, 2, 5, 12 (MTDI), 15 (MTDO) | ESP32 datasheet, "Strapping Pins" |

Any other target gets `kStrapping == 0`. The target comes from `<sdkconfig.h>`, included when the
ESP32 core provides it.

### Cost

Nothing unless a module calls `claim`, `release` or `owner_of`: then a 49-entry owner table
(196 bytes on the ESP32), the strapping mask and the functions are linked. The `Os` constructor
always sets `error_handler` and `error_context` (two pointers and a one-line function).

## xewe::span

`src/XeWeCore/Utils/Span.h`: a contiguous view over elements someone else owns.

On C++20 and later `xewe::span<T>` **is** `std::span<T>`, an alias and nothing more. On C++17 it
is a small stand-in with only the operations the XeWe code uses.

The ESP32 core builds at `-std=gnu++2b`, so on device this is always the alias. The stand-in
serves host builds at `-std=c++17`. Public signatures such as `command_function_t` are spelled
`xewe::span` so they are identical on both.

```cpp
#include <XeWeCore.h>

void handler(xewe::span<const std::string> args) {
    if (args.empty()) return;
    for (const auto& a : args) { /* ... */ }
}
```

### What it supports

| Member | Notes |
|---|---|
| `span()` | empty |
| `span(pointer, size_type)` | pointer and length |
| `span(C&)` / `span(const C&)` | any contiguous container whose `data()` converts, such as `std::vector`, `std::array` |
| `span(T (&)[N])` | a C array |
| `size()`, `empty()`, `data()` | |
| `operator[]` | unchecked |
| `begin()`, `end()` | range-`for` |

### Notes

* **It does not own anything.** The storage it points at must outlive the span. The usual trap is
  building one from a temporary container.
* **It is not a `std::span` implementation.** No `subspan`, `first`, `last`, `extent`, reverse
  iterators or static extents. A new member must be one C++20 `std::span` also has, or the two
  stop behaving alike.
* **The C++17 fallback accepts a temporary** where a real `std::span` would reject it (it has no
  borrowed-range constraint). Code that compiles under C++17 can therefore fail on a C++20 core.
  Do not rely on it.

## xewe::LockGuard

`src/XeWeCore/Utils/LockGuard.h`: RAII guard for a FreeRTOS mutex.

This header includes `<freertos/FreeRTOS.h>` and `<freertos/semphr.h>`, so it needs a core with
FreeRTOS, which every ESP32 core has. `<XeWeCore.h>` always includes it.

```cpp
SemaphoreHandle_t mutex = xSemaphoreCreateMutex();

void touch_shared_state() {
    xewe::LockGuard guard(mutex);    // takes here
    shared_value++;
}                                    // gives here, on every exit path
```

### Constructor

```cpp
explicit LockGuard(SemaphoreHandle_t mutex_handle);
```

Takes the mutex with `portMAX_DELAY`.

### Destructor

```cpp
~LockGuard();
```

Gives the mutex. Runs on every scope exit, including an early `return`.

### Copy and move

```cpp
LockGuard(const LockGuard&)            = delete;
LockGuard& operator=(const LockGuard&) = delete;
```

Non-copyable. No move constructor is declared either, and declaring the copy operations as deleted
suppresses the implicit ones, so a `LockGuard` **cannot be moved or returned from a function**.
It is a scope-local object only.

### Notes

* **The constructor blocks indefinitely.** `portMAX_DELAY` means there is no timeout and no
  failure path: if the mutex is never given, the task waits forever. `xSemaphoreTake`'s return
  value is not checked.
* **Not recursive.** Taking the same mutex twice from one task deadlocks. A plain
  `xSemaphoreCreateMutex()` is not recursive; if you need reentrancy, use
  `xSemaphoreCreateRecursiveMutex()` and its own take/give calls rather than this guard.
* The handle is not validated. Constructing a guard over a null handle is undefined behaviour;
  check the result of `xSemaphoreCreateMutex()` at creation time.

## Debug macros

`src/XeWeCore/Utils/Debug.h`: opt-in debug printing, enabled per class from build flags.

The macros are in the global namespace, not `xewe::`. They print to `Serial`, so a sketch using
them must have called `Serial.begin()` (or `xewe::SerialPort::begin()`, which does).

### The flag convention

Each class defines its own flag with a default of `0` next to its code:

```cpp
#ifndef DEBUG_MyClass
#define DEBUG_MyClass 0
#endif
```

Enable it from the build instead of editing the library:

```bash
arduino-cli compile --build-property "compiler.cpp.extra_flags=-DDEBUG_MyClass=1" ...
```

```ini
; PlatformIO
build_flags = -DDEBUG_MyClass=1
```

`AsyncTimer` is the only class in this library that ships a flag: `DEBUG_AsyncTimer`.

### DBG_ENABLED

```cpp
#define DBG_ENABLED(cls)       (DEBUG_##cls)
```

Expands to the flag itself, so it can be used in an `if` of your own.

### DBG_PRINTLN

```cpp
DBG_PRINTLN(cls, msg)
```

Prints `[DBG] [<cls>]: ` followed by `Serial.println(msg)`. `cls` is a bare class name, not a
string: `DBG_PRINTLN(MyClass, "started")`.

### DBG_PRINTF

```cpp
DBG_PRINTF(cls, fmt, ...)
```

Same prefix, then the formatted text. No trailing newline is added, so put `\n` in the format
string. Formats with `snprintf` into a stack buffer and prints the result, so it does not depend on
`Print::printf`. Output longer than
`DBG_PRINTF_BUFFER_SIZE` (128 by default) is truncated; raise it from build flags if you need
more. For formatting outside a debug macro, use
[`xewe::str::format`](#formatting).

### Notes

* **The check is a runtime `if`, not `#if`.** Both macros expand to
  `do { if (DEBUG_<cls>) { ... } } while (0)`, so the arguments are still compiled and `Serial` is
  still referenced at link time even when the flag is `0`. The compiler drops the dead branch, but
  a `msg` expression with side effects still has to compile, and a `Serial` must exist.
* A missing flag is a compile error, not a silent `0`, because `DEBUG_##cls` has to expand to something.
  That is why each class defines its own default.

## Listeners

`xewe::ListenerSet` (`src/XeWeCore/Utils/Listeners.h`) is documented with modules:
[Module/README.md#listeners](../Module/README.md#listeners).
