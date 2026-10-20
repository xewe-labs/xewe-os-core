# Serial

- [SerialPortConfig and begin](#serialportconfig-and-begin)
- [Printing](#printing)
- [Reading lines](#reading-lines)
- [Prompts](#prompts)

## SerialPortConfig and begin

`src/XeWeCore/Serial/Serial.h` — how the port is opened.

### SerialPortConfig

```cpp
struct SerialPortConfig {
    unsigned long baud_rate        = XEWE_CORE_SERIAL_BAUD;
    std::size_t   tx_buffer_size   = XEWE_CORE_SERIAL_TX_BUF;
    std::size_t   rx_buffer_size   = XEWE_CORE_SERIAL_RX_BUF;
    uint32_t      startup_delay_ms = XEWE_CORE_SERIAL_DELAY_MS;  // give USB CDC time to enumerate
    bool          echo             = XEWE_CORE_SERIAL_ECHO != 0; // echo typed characters back
};
```

| Field | Default | Define | |
|---|---|---|---|
| `baud_rate` | `115200` | `XEWE_CORE_SERIAL_BAUD` | passed to `Serial.begin` |
| `tx_buffer_size` | `2048` | `XEWE_CORE_SERIAL_TX_BUF` | set **before** `Serial.begin`; a table or header can be several hundred bytes in one burst |
| `rx_buffer_size` | `1024` | `XEWE_CORE_SERIAL_RX_BUF` | the hardware buffer, separate from the 255-byte line buffer |
| `startup_delay_ms` | `1000` | `XEWE_CORE_SERIAL_DELAY_MS` | a plain `delay()` after opening the port |
| `echo` | `true` | `XEWE_CORE_SERIAL_ECHO` (`1`) | echo each received character back, so a terminal shows what is typed |

The defaults are the compile-time constants of the core's [`Config.h`](../Config.h)
([configuration](../../../doc/config.md)); a build flag or the project's `Config.h` changes them for
the whole build, a field set in code changes them for that port.

### begin

```cpp
void begin(const SerialPortConfig& cfg = {});
```

Stores `echo`, sets the TX and RX buffer sizes, calls `Serial.begin(baud_rate)`, then waits
`startup_delay_ms`.

```cpp
xewe::SerialPort serial;

void setup() {
    serial.begin();                                  // defaults
    serial.begin({.baud_rate = 921600, .echo = false});
}
```

**`begin()` blocks for a second by default.** A USB CDC port (ESP32-C3, C6 and S3 with
`CDCOnBoot`) needs time to enumerate on the host. Without the delay the first lines go to a port
nobody listens to yet. On a real UART, set `startup_delay_ms = 0` to boot faster.

**The buffer sizes apply on ESP32 only** (the calls sit behind `ARDUINO_ARCH_ESP32`). They must be
set before `Serial.begin`, so they cannot change after `begin()`.

### Notes

* `SerialPort` uses no heap for input. Its line buffer and four-line queue take about 1.3 KB of
  static RAM. Use one instance per physical port, usually a global.
* Calling `begin()` twice re-opens the port and waits again.
* `SerialPort` has no `DEBUG_` flag (see [debug](../Utils/README.md#debug-macros)).

## Printing

`src/XeWeCore/Serial/Serial.h` — formatted output: plain lines, boxed text, separators, headers and
tables.

Every function here writes CRLF line endings (`xewe::str::kCRLF`).

### print

```cpp
void print(std::string_view message        = {},
           std::string_view end            = xewe::str::kCRLF,
           std::string_view edge_character = {},
           const char       text_align     = 'l',
           const char       wrap_mode      = 'w',
           const uint16_t   message_width  = 0,
           const uint16_t   margin_l       = 0,
           const uint16_t   margin_r       = 0);
```

| Parameter | |
|---|---|
| `message` | the text; embedded `\n` splits it into lines, and a trailing `\r` is stripped from each |
| `end` | written after the final line only; intermediate lines always get CRLF |
| `edge_character` | drawn at both ends of every line, e.g. `"|"` |
| `text_align` | `'l'`, `'r'`, `'c'`; anything else behaves as `'l'` |
| `wrap_mode` | `'c'`/`'C'` = hard character chunks, anything else = word wrap |
| `message_width` | field width for the text. **`0` disables wrapping and alignment entirely** |
| `margin_l`, `margin_r` | spaces between the edge and the field |

`print()` with no arguments prints an empty line.

**Wrapping only happens when `message_width > 0`.** With the default `0`, the text is printed
as-is between the margins, and `text_align` and `wrap_mode` have no effect.

```cpp
serial.print("Saved.");
serial.print("A long sentence that should be wrapped inside a box.",
             xewe::str::kCRLF, "|", 'l', 'w', 46, 1, 1);
```

### printf

```cpp
void printf(const char* fmt, ...);
```

Formats with [`xewe::str::vformat`](../Utils/README.md#xewestr) and prints with all of `print`'s defaults,
so it **appends CRLF**. `vformat` sizes the result exactly (two passes of `vsnprintf`), so long
output is not truncated. `printf(nullptr)` prints an empty line.

There is no `__attribute__((format))`, so a format/argument mismatch is not caught at compile
time.

### printf_fmt

```cpp
void printf_fmt(std::string_view end,
                std::string_view edge_character,
                const char       text_align,
                const char       wrap_mode,
                const uint16_t   message_width,
                const uint16_t   margin_l,
                const uint16_t   margin_r,
                const char*      fmt,
                ...);
```

`printf` with `print`'s layout parameters. **None of them have defaults**, so all seven come
first, in order, before the format string:

```cpp
serial.printf_fmt(xewe::str::kCRLF, "|", 'c', 'w', 46, 1, 1,
                  "Uptime %lu s", millis() / 1000);
```

### print_separator

```cpp
void print_separator(const uint16_t   total_width    = 50,
                     std::string_view fill           = "-",
                     std::string_view edge_character = "+");
```

Draws `+------...------+` at `total_width` characters. `fill` is cycled, so `"-="` and other
multi-character patterns work. `total_width == 0` prints an empty line; a width no larger than the
two edges degrades to a truncated edge string.

### print_spacer

```cpp
void print_spacer(const uint16_t   total_width    = 50,
                  std::string_view edge_character = {});
```

The same shape filled with spaces: a blank row inside a box. With the default empty edge it is a
run of spaces.

### print_header

```cpp
void print_header(std::string_view message,
                  const uint16_t   total_width          = 50,
                  std::string_view edge_character       = "|",
                  std::string_view cross_edge_character = "+",
                  std::string_view sep_fill             = "-");
```

Prints a separator, then the message centred with a one-character margin on each side, then
another separator.

**A `\sep` token inside the message draws a separator line.** The message is split on the literal
four characters `\sep`, and each part is printed centred and followed by a separator:

```cpp
serial.print_header("blink-device\sepVersion 0.1.0");
```

```
+------------------------------------------------+
|                  blink-device                  |
+------------------------------------------------+
|                 Version 0.1.0                  |
+------------------------------------------------+
```

The content width is `total_width - (2 * edge_character.size() + 2)` when an edge is set and the
width allows it, otherwise `total_width`.

### print_table and render_table

```cpp
void print_table(const std::vector<std::vector<std::string_view>>& table,
                 std::string_view header_content       = {},
                 const uint16_t   max_col_width        = 30,
                 std::string_view edge_character       = "|",
                 std::string_view cross_edge_character = "+",
                 std::string_view sep_fill             = "-");

std::string render_table(const std::vector<std::vector<std::string_view>>& table,
                         std::string_view header_content       = {},
                         const uint16_t   max_col_width        = 30,
                         std::string_view edge_character       = "|",
                         std::string_view cross_edge_character = "+",
                         std::string_view sep_fill             = "-") const;
```

`render_table` is `const` and returns the whole table as one CRLF-separated string.
`print_table` writes exactly that string. Use `render_table` when the table also goes elsewhere,
such as a log or a web response.

Layout rules:

* Column count is the longest row; short rows are padded with empty cells.
* Column width is the longest single line in any cell of that column, **plus 2**, clamped to
  `max_col_width`. The 2 is one space on each side of the text.
* Cells may contain `'\n'`; each segment is word-wrapped to `width - 2`. Row height is the tallest
  cell in the row.
* Keep `max_col_width` at 3 or more. Below that, cells wrap at one character but the column is
  narrower, so the edges no longer line up.
* A `+---+---+` divider is drawn before the first row and after every row.
* A non-empty `header_content` adds a full-width separator and a centred title above the table.
* An empty `table` renders an empty string.

```cpp
std::string age_str = std::to_string(age);           // must outlive the call
serial.print_table({
    {"Field", "Value"},
    {"Name",  name},
    {"Age",   age_str},
}, "Summary");
```

**The cells are `std::string_view`s.** What they point at must outlive the call, so build
temporaries into named variables first, as above. A `std::to_string(...)` written inline in the
table is destroyed before the table is rendered.

## Reading lines

`src/XeWeCore/Serial/Serial.h` — the non-blocking input path.

```cpp
void loop() {
    serial.loop();                                   // assemble lines, never blocks
    if (serial.has_line()) {
        std::string line = serial.read_line();
        serial.print("> " + line);
    }
}
```

### loop

```cpp
void loop();
```

Drains everything currently in the RX buffer and assembles it into lines. Call it every iteration
of the sketch's `loop()`. It never blocks: it reads only what is already available, calling
`yield()` between characters.

Per character: `'\r'` is discarded, `'\n'` ends the line, anything else is appended. When `echo` is
on, the character is written back first. Each completed line is pushed onto a FIFO of up to four
lines (`INPUT_QUEUE_LINES`, from `XEWE_CORE_INPUT_QUEUE`), so several lines arriving in one pass
are all kept, in order.

### has_line

```cpp
bool has_line() const;
```

Whether at least one complete line is waiting in the queue. It does not poll the port: `loop()`
must have run.

### read_line

```cpp
std::string read_line();
```

Removes and returns the oldest queued line. Returns `{}` when no line is ready. The returned
string does not include the terminating newline. A partially typed line is not affected.

### clear_input

```cpp
void clear_input();
```

Drains the hardware RX buffer and discards every queued line, any partially typed line and the
overflow mark. Every `get_*` prompt calls it first, so a keystroke typed before the question does
not answer it.

### Notes

* **A line holds 255 bytes** (`INPUT_BUFFER_SIZE`, from the compile-time constant
  `XEWE_CORE_INPUT_BUF_SIZE`), 254 usable. From the 255th character on, the rest of the line is
  discarded up to the newline. Then the **whole line is dropped** and
  `! Input line too long (max 254 chars): dropped` is printed once (the number is the usable
  length). Nothing of it is queued or executed. Long input (a Wi-Fi password, a URL, a JSON blob)
  must fit in 254 characters.
* **Up to four completed lines are queued** (`INPUT_QUEUE_LINES`, from `XEWE_CORE_INPUT_QUEUE`). A
  line that completes while four are waiting is dropped; the queued ones are kept. Each dropped
  line prints `! Input overflow: line dropped`.
* **One burst must fit the RX buffer** (`rx_buffer_size`, 1024 bytes by default, see
  [config](#serialportconfig-and-begin)). The ESP32 USB console (HWCDC) has no flow control: bytes that arrive while
  its RX queue is full are lost before `loop()` sees them. On an S3, a command sent after 1024 other
  bytes in one host write is lost.
* **There is no line editing.** A backspace is stored as a literal `\b`; arrow keys arrive as
  escape sequences. The echo is raw.
* `read_line()` returns a copy; the queue slot is reused immediately.

## Prompts

`src/XeWeCore/Serial/Serial.h` — typed questions asked over the serial console.

**Every `get_*` function blocks** until it gets a valid answer, times out, or runs out of
attempts. It busy-waits, calling `loop()` and `yield()`. Co-operative tasks keep running; the
sketch's own `loop()` does not. Prompts belong in `setup()` and in module setup routines, not in a
running `loop()`.

**A prompt reachable from a running device must be bounded.** A command can arrive from the
scheduler, a button or the web UI with nobody at the console. An unbounded prompt
(`retry_count = 0` or `timeout_ms = 0`) then stops `Os::loop`, and with it Wi-Fi, the web server,
the scheduler and the buttons, until someone answers. The core's own confirmations are bounded:

| Prompt | Call | On timeout or invalid answer |
|---|---|---|
| `$<module> disable` → `OK?` (`Module::disable`) | `get_yn("OK?", 2, 15000, false, answered)` | after the 2nd failed attempt: `! No answer: disable cancelled`, `Aborted` |
| `$system reset` → `OK?` (`System::reset`) | `get_yn("OK?", 2, 15000, false, answered)` | after the 2nd failed attempt: `! No answer: reset cancelled`, `Aborted` |

Two attempts of 15 s each. A timeout (`! Timeout.`) or an invalid answer (`! Please answer 'y' or
'n'.`) re-prompts once; a second one cancels. `Os::loop` stalls for 30 s at most. An answer typed
after the second timeout is an ordinary command line and is rejected. Only the first-boot prompts
(the enable question, the device name) are unbounded: they run in `setup()` and must be answered.

```cpp
bool     ok;
uint32_t period = serial.get_uint32("Blink period in ms?", 50, 10000,
                                    3,      // 3 attempts, then give up
                                    30000,  // 30 s per attempt
                                    500,    // returned if it gives up
                                    ok);

if (!ok) serial.print("No answer; using 500 ms.");
```

### The shared parameters

Every prompt ends with the same four parameters, and they all behave the same way.

| Parameter | |
|---|---|
| `retry_count` | **`0` means infinite**: the call only returns on valid input. `N ≥ 1` means **N attempts in total**, after which the default is returned |
| `timeout_ms` | per attempt. **`0` means wait forever.** On expiry it prints `! Timeout.` and, if attempts remain, re-prompts |
| `default_value` | returned when the prompt gives up. Never returned while `retry_count == 0` |
| `success_sink` | `std::optional<std::reference_wrapper<bool>>`; set to `true` on a real answer and `false` when the default was returned |

Pass a `bool` variable for `success_sink`; it converts to `std::reference_wrapper<bool>`.

**`success_sink` is the only way to tell a real answer from the default.** If the user types `500`
and the default is also `500`, the return value cannot tell them apart. Code that stores the result
should check it.

Each prompt first calls [`clear_input()`](#clear_input), then prints `prompt` on its own
line (when non-empty). Before each attempt it prints a marker line: `> ` for most, `(y/n) > ` for
`get_yn`. Typed input echoes on the line below the marker.

### get_string

```cpp
std::string get_string(std::string_view prompt        = {},
                       const uint16_t   min_length    = 0,
                       const uint16_t   max_length    = 0,
                       const uint16_t   retry_count   = 0,
                       const uint32_t   timeout_ms    = 0,
                       std::string_view default_value = {},
                       std::optional<std::reference_wrapper<bool>> success_sink = std::nullopt);
```

`min_length` and `max_length` are **character counts**, inclusive. `max_length == 0` means 254, the
usable line length.

The answer is not trimmed, and an empty line is a valid answer when `min_length == 0`. Out of
bounds prints `! Length must be in [min..max] chars.`

### get_int, get_uint8, get_uint16, get_uint32

```cpp
int      get_int   (std::string_view prompt = {},
                    const int      min_value = std::numeric_limits<int>::min(),
                    const int      max_value = std::numeric_limits<int>::max(),
                    const uint16_t retry_count = 0, const uint32_t timeout_ms = 0,
                    const int      default_value = 0,
                    std::optional<std::reference_wrapper<bool>> success_sink = std::nullopt);

uint8_t  get_uint8 (/* same shape, uint8_t  bounds */);
uint16_t get_uint16(/* same shape, uint16_t bounds */);
uint32_t get_uint32(/* same shape, uint32_t bounds */);
```

Parsed with [`xewe::str::parse_int`](../Utils/README.md#number-parsing):
base 10, surrounding whitespace trimmed, **trailing characters rejected**.

Messages: `! Invalid number. Please enter a base-10 integer.` and `! Out of range [min..max].`

If `min_value > max_value`, the two are **swapped** without a message.

### get_float

```cpp
float get_float(std::string_view prompt        = {},
                const float      min_value     = -std::numeric_limits<float>::infinity(),
                const float      max_value     =  std::numeric_limits<float>::infinity(),
                const uint16_t   retry_count   = 0,
                const uint32_t   timeout_ms    = 0,
                const float      default_value = 0.0f,
                std::optional<std::reference_wrapper<bool>> success_sink = std::nullopt);
```

Parsed with `strtod`. Trailing spaces are allowed, other trailing characters and NaN are rejected.
Inverted bounds are swapped as above. Messages: `! Invalid number. Please enter a decimal value.`,
`! Invalid number.`, `! Out of range [min..max].`

### get_yn

```cpp
bool get_yn(std::string_view prompt        = {},
            const uint16_t   retry_count   = 0,
            const uint32_t   timeout_ms    = 0,
            const bool       default_value = false,
            std::optional<std::reference_wrapper<bool>> success_sink = std::nullopt);
```

Accepted, case-insensitively:

| true | false |
|---|---|
| `y`, `yes`, `1`, `true` | `n`, `no`, `0`, `false` |

Anything else prints `! Please answer 'y' or 'n'.` The iteration prompt is `(y/n) > `.

There is no `min`/`max` pair, so the shared parameters start one position earlier than in the
numeric prompts.

### get_menu_choice

```cpp
uint8_t get_menu_choice(std::string_view               prompt        = {},
                        const std::vector<std::string>& options      = {},
                        const uint8_t                  min_value     = std::numeric_limits<uint8_t>::min(),
                        const uint8_t                  max_value     = std::numeric_limits<uint8_t>::max(),
                        const uint16_t                 retry_count   = 0,
                        const uint32_t                 timeout_ms    = 0,
                        const uint8_t                  default_value = 0,
                        std::optional<std::reference_wrapper<bool>> success_sink = std::nullopt);
```

Prints the prompt and the numbered options, then calls `get_uint8`.

```cpp
uint8_t mode = serial.get_menu_choice("Pick a mode:", {"Solid", "Fade", "Rainbow"});
```

```
Pick a mode:
  1) Solid
  2) Fade
  3) Rainbow
Choice
>
```

**Bounds are derived when they are left at their defaults and `options` is non-empty:**
`min_value` of `0` becomes `1` (menus are 1-based), and `max_value` of `255` becomes
`min + options.size() - 1`, clamped to 255. Pass explicit bounds to override either.

The returned value is the printed number, so subtract `min_value` for a zero-based index.

Retry, timeout, default and `success_sink` behave as in `get_uint8`, with `Choice` as its prompt.
**The option list is not reprinted on a retry.** When `options` is empty and `prompt` is set, the
`Choice` line is left out.
