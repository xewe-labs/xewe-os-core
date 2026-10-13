# xewe::color

`src/XeWeCore/Utils/Color.h` — HSV ⇄ RGB conversion for 8-bit channels, and hex colour strings.

**Host-includable:** the header uses the standard library only (no `<Arduino.h>`), so pure code
such as effect math can include it and build in host tests. `tests/unit/run.sh` compiles it
without the Arduino shim to keep it that way.

**All six HSV/RGB channels are `0-255`,** including hue and saturation. Hue is *not* 0-360 and saturation
and value are *not* 0-100 — this is the most common mistake with these two functions.

## hsv_to_rgb

```cpp
inline std::array<uint8_t, 3> hsv_to_rgb(const std::array<uint8_t, 3>& hsv);
```

`{hue, saturation, value}` → `{red, green, blue}`.

```cpp
auto rgb = xewe::color::hsv_to_rgb({0, 255, 255});      // full-saturation red
analogWrite(pin_r, rgb[0]);
```

## rgb_to_hsv

```cpp
inline std::array<uint8_t, 3> rgb_to_hsv(const std::array<uint8_t, 3>& rgb);
```

`{red, green, blue}` → `{hue, saturation, value}`. Returns hue `0` for any greyscale input
(`r == g == b`), since hue is undefined there.

## Hex colours

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

## Notes

* **Conversion is lossy.** Both functions work in `float` internally and truncate with
  `static_cast<uint8_t>` on the way out, so a round trip does not always return the original
  triplet — expect drift of a unit or so, most visibly at hue boundaries.
* No clamping is needed or performed: `uint8_t` inputs are already in range.
* Everything here is `inline` and header-only; there is nothing to link.
* **`hsv_to_rgb` is pinned bit for bit** by `tests/unit` (`color_hsv_to_rgb_pinned`: spot values
  and a checksum over a 256 × 256 × 16 grid). Effect code, such as an LED strip's colour modes,
  calls it and depends on its exact output, so the arithmetic does not change (operation order
  included: an FMA-contracted build already gives different bytes).
