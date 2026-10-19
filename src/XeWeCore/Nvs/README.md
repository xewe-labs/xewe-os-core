# Nvs

- [xewe::Nvs](#xewenvs)
- [xewe::FlexData\<T\>](#xeweflexdatat)
- [Blob format and versioning](#blob-format-and-versioning)

## xewe::Nvs

`src/XeWeCore/Nvs/Nvs.h` — typed key-value storage on the ESP32 NVS partition.

Every value lives under a **namespace** and a **key**, both limited to 15 characters. NVS is
initialised lazily on first use; there is nothing to call in `setup()`.

```cpp
xewe::Nvs nvs;

nvs.write<uint32_t>("app", "boots", 5);
uint32_t boots = nvs.read<uint32_t>("app", "boots", 0);    // 0 if missing
```

### set_error_handler

```cpp
using error_handler_t = std::function<void(std::string_view message)>;

void set_error_handler(error_handler_t handler);
```

Where error messages go. The default writes to the ESP log with tag `XeWeNvs`
(`ESP_LOGE`). Assigning an empty `std::function` restores the default, since the handler is only
used when it is non-empty.

```cpp
nvs.set_error_handler([&](std::string_view m) { serial.print(m); });
```

**What reaches the handler:** an invalid name (longer than 15 characters, or containing an
embedded NUL; an empty name is rejected silently), a failed `nvs_flash_init()` (reported once until init succeeds again), the automatic
partition erase (see Notes), a failed partition erase in `erase_all`, a failed namespace open (except a read-only open of a namespace that
was never written, which is the normal "missing" case), a failed `nvs_set_*`/erase, and a failed
commit. Read failures (missing key, wrong type) stay **silent**: `read` returns the default.

Messages, verbatim (`<ESP_ERR>` is `esp_err_to_name()` of the code):

```
Nvs: ERROR name '<name>' too long (<n> chars > 15 max); rejected
Nvs: ERROR name contains an embedded NUL; rejected
Nvs: ERROR nvs_flash_init failed; all reads return defaults, writes fail (<ESP_ERR>)
Nvs: ERROR partition unusable, erased all NVS data (<ESP_ERR>)
Nvs: ERROR partition erase failed (<ESP_ERR>)
Nvs: ERROR open namespace failed '<ns>' (<ESP_ERR>)
Nvs: ERROR write failed (<ESP_ERR>)        e.g. ESP_ERR_NVS_NOT_ENOUGH_SPACE, ESP_ERR_NVS_VALUE_TOO_LONG
Nvs: ERROR commit failed (<ESP_ERR>)
```

`read<T>` cannot tell "missing" from "stored with another type" (signedness and width are part of
the type; `bool` and `uint8_t` share one) or from "NVS unavailable": all return `default_value`.

### write

```cpp
template <typename T>
bool write(std::string_view ns, std::string_view key, const T& value);
```

Returns `true` when the value was stored and committed.

| `T` | Stored as |
|---|---|
| `std::string`, Arduino `String` | NVS string |
| `std::string_view` | NVS string (copied first) |
| anything convertible to `const char*` | NVS string; a null pointer stores `""` |
| `bool` | `u8`, `1`/`0` |
| signed integral, 1/2/4/8 bytes | `i8` / `i16` / `i32` / `i64` |
| unsigned integral, 1/2/4/8 bytes | `u8` / `u16` / `u32` / `u64` |
| `float`, `double` | **a blob** of `sizeof(value)` bytes |
| anything else | compile error: `"Unsupported Nvs::write<T>() type."` |

**Floats are blobs, not NVS numbers.** NVS has no float type, so they are stored raw. They are
invisible to `nvs_get_*` and to external tools that walk typed entries, and a change of type
(`float` → `double`) makes the stored value unreadable.

Every `write` commits immediately — one flash commit per call.

### read

```cpp
template <typename T>
T read(std::string_view ns, std::string_view key, T default_value = T());
```

Returns the stored value, or `default_value` when the key is missing, the name is invalid, or the
stored size does not match.

The supported types are the same as `write` **minus `std::string_view` and `const char*`**, which
are write-only and fail to compile here (`"Unsupported Nvs::read<T>() type."`). Read them back as
`std::string` or Arduino `String`.

A `float`/`double` is only accepted when the stored blob is exactly `sizeof(T)` bytes; otherwise
the default comes back.

### write_blob and read_blob

```cpp
bool write_blob(std::string_view ns, std::string_view key, const std::vector<uint8_t>& data);
bool write_blob(std::string_view ns, std::string_view key, std::span<const uint8_t>    data);

std::vector<uint8_t> read_blob(std::string_view ns, std::string_view key);
```

Raw bytes. The `vector` overload forwards to the `span` one, which writes the bytes directly.

**`read_blob` cannot distinguish "missing" from "empty"** — both return an empty vector. Store a
separate presence flag if that matters.

### write_flex and read_flex

```cpp
template <typename T> bool write_flex(std::string_view ns, std::string_view key, const T& obj);
template <typename T> bool read_flex (std::string_view ns, std::string_view key, T&       out);
```

Persist a whole struct. `T` must derive from `xewe::FlexData<T>` — see
[xewe::FlexData\<T\>](#xeweflexdatat) — or the call fails to compile. (The `static_assert` messages say
`Nvs::save<T>()` and `Nvs::load<T>()`; they mean these two.)

`write_flex` is `write_blob(ns, key, obj.to_blob())`. `read_flex` returns `false` when the key is
missing and when the stored blob does not decode. In the second case `out` is already **partially
overwritten**: reset it on `false`, as shown in [from_blob](#from_blob).

### remove, reset_ns and erase_all

```cpp
void remove   (std::string_view ns, std::string_view key);
void reset_ns (std::string_view ns);
bool erase_all();
```

| | |
|---|---|
| `remove` | deletes one key. Returns `void`; a missing key is not an error and skips the commit |
| `reset_ns` | erases every key in a namespace. Returns `void`, so there is no success signal |
| `erase_all` | erases the **entire NVS partition** and re-initialises. Returns `false` if either step fails; a failed erase goes to the error handler as `Nvs: ERROR partition erase failed (<esp error>)` |

`reset_ns` probes the namespace read-only first, so erasing one that was never written does not
create it.

**`erase_all()` wipes every namespace on the device**, including those belonging to other
libraries and to the ESP-IDF itself (Wi-Fi calibration data, for example). In XeWe OS it is what
`$system reset` calls for a factory reset.

### Notes

* **Lazy init with an automatic erase.** The first operation calls `nvs_flash_init()`. If that
  returns `ESP_ERR_NVS_NO_FREE_PAGES` or `ESP_ERR_NVS_NEW_VERSION_FOUND`, the library
  **deinitialises and erases the whole NVS partition**, then initialises again. That recovers a
  full or format-changed partition automatically, at the cost of every stored value — a device
  that fills NVS loses its settings on the next boot; the erase is reported to the error handler.
* **The 15-character limit applies to namespaces as well as keys.** An over-long or empty name is rejected
  before any flash access: `write` returns `false`, `read` returns the default, `read_blob`
  returns empty, and `remove`/`reset_ns` do nothing.
* `Nvs` is default-constructible and copyable, but the readiness flag is per-instance while
  `nvs_flash_init()` is global. One instance is the intended use; XeWe OS exposes it as
  `os.nvs`.
* Handles are closed by an internal RAII wrapper on every path, including error returns.

## xewe::FlexData\<T\>

`src/XeWeCore/Nvs/FlexData.h` — declare a struct's fields once and get both a compact binary form for
flash and a JSON form for APIs.

```cpp
struct Settings : xewe::FlexData<Settings> {
    uint8_t     brightness = 128;
    std::string name;

    static constexpr auto fields() {
        return std::make_tuple(fld("brightness", &Settings::brightness),
                               fld("name",       &Settings::name));
    }
};
```

`FlexData` is CRTP: the struct passes **itself** as the template argument. Everything below is
inherited; the only thing a struct supplies is `fields()`.

### fields and fld

```cpp
template <typename C, typename M>
struct Field { const char* name; M C::* ptr; };

template <typename C, typename M>
constexpr Field<C, M> fld(const char* n, M C::* p);
```

`fields()` must be `static constexpr` and return a `std::make_tuple` of `fld` entries. The names
are the JSON keys; the order is the binary field order.

`fld` is found by ADL from inside a `FlexData`-derived struct, so it needs no `xewe::` prefix
there.

### Supported field types

| Supported | |
|---|---|
| any arithmetic type | `bool`, `char`, all `intN_t`/`uintN_t`, `float`, `double` |
| `std::string` | length-prefixed |
| a nested `FlexData` struct | inlined, field by field |
| `std::vector<T>` | where `T` is any of the above, including nested structs and further vectors |

**Not supported** — a hard compile error, `"no blob_write overload for this type"`: Arduino
`String`, enums and enum classes, `std::array`, pointers, `std::optional`, `std::map`. Use
`std::string` instead of `String`, and store an enum as its underlying integer.

### JSON

```cpp
void         to_json_object  (JsonObject o)      const;
bool         from_json_object(JsonVariantConst v);
JsonDocument as_json_doc     ()                  const;
std::string  as_json_str     ()                  const;
bool         update          (std::string_view json);
static Derived from_json     (std::string_view json);
```

| | |
|---|---|
| `to_json_object` | writes every field into an existing object |
| `from_json_object` | assigns **only the keys present and non-null** in the source, each only if its JSON type matches (see Type rules); `false` if any was rejected |
| `as_json_doc` | a `JsonDocument` by value (ArduinoJson 7 elastic document) |
| `as_json_str` | the serialized object |
| `update` | parse and merge — a partial update, leaving unmentioned fields alone; `false` on a parse error or a rejected field |
| `from_json` | static factory: default-construct, then merge |

```cpp
s.update(R"({"brightness": 200})");     // name is untouched
std::string json = s.as_json_str();
```

**Malformed JSON is not reported.** `update` returns `false` and the object is unchanged, but
nothing is printed. Type mismatches are reported (below).

#### Type rules

Assignment is type-matched (`is<M>()` before `as<M>()`). A
present value of the wrong JSON type is **rejected**: that field keeps its previous value, the
other fields are still applied, the call returns `false`, and `xewe::flex_error_handler` gets
`! <Struct>.<field>: expected <type>, got <json type>`, e.g. `! Settings.name: expected string,
got integer`.

| Field type | Accepted JSON | Rejected (examples) |
|---|---|---|
| `bool` | `true` / `false` | `"false"`, `"yes"`, `""`, `0`, `1` |
| integers | an integer within the field's range | `1.5`, `"7"`, `-1` into unsigned, `300` into `uint8_t` |
| `float` / `double` | any number (integer or float) | `"1.5"`, `true` |
| `std::string` | a string | `5`, `true`, objects, arrays |
| nested struct | an object (its own fields follow these rules and report as `<Inner>.<field>`) | anything else |
| `std::vector<T>` | an array (elements converted with `as<T>()`, not type-checked) | anything else |

`xewe::flex_error_handler` is a `std::function<void(std::string_view)>`; `Os::begin` points it at
the console. Unset, rejections are silent but still happen. A rejection inside a nested struct is
reported but does not make the outer call return `false`.

#### Field presence

```cpp
uint32_t present() const;
bool     has    (std::string_view field) const;
```

`from_json_object` (and so `update` and `from_json`) records which fields it assigned, so a loader
can tell a field that was **missing** from one that holds its **default**:

```cpp
Settings s;
s.update(json);
if (!s.has("schema")) { /* no schema key: not "version 1" */ }
```

| After loading | `has("schema")` | `schema` |
|---|---|---|
| `{"name":"x"}` (missing) | `false` | default, `1` |
| `{"schema":null}` (null) | `false` | default |
| `{"schema":"2"}` (wrong type, rejected) | `false` | unchanged |
| `{"schema":1}` (present, equal to the default) | `true` | `1` |
| `{"schema":3}` (present) | `true` | `3` |

* `present()` is the bitmask: bit *i* is the *i*-th entry of `fields()`. `has` of an unknown name
  is `false`.
* Each load **replaces** the mask: after two `update` calls it describes the second one only.
* A blob always holds every field, so a successful `from_blob` (and so `Nvs::read_flex`) marks
  **every** field present, and a failed one (wrong blob version, too short) marks none. A loader can
  therefore write `read_flex(...) && s.has("schema") && s.schema == SCHEMA` for blobs and JSON
  alike.
* `set_field` does not change it.
* Nested structs (and the elements of a `std::vector` of structs) track their own presence:
  `s.inner.has("a")`.
* **At most 32 fields:** `present()` and `has()` do not compile (`static_assert`) on a struct with
  more; such a struct still loads JSON and blobs.
* **Cost:** one `uint32_t` in every `FlexData` struct (4 bytes per instance, including each
  element of a vector of structs). It is not stored in the blob or the JSON, so stored data is
  unaffected.

### Field access by name

```cpp
template <typename V>
bool        set_field(std::string_view name, const V& value);
std::string get_field(std::string_view name) const;
```

`set_field` round-trips the value through a `JsonDocument` and applies the same
[type rules](#type-rules): it returns `false` when no field has that name or the value's type does
not match (`set_field("enabled", "true")` on a `bool` is rejected). `get_field` returns the value
**JSON-serialized** — strings come back quoted, nested structs as `{...}` — and the literal string
`"null"` for an unknown name.

### Binary form

```cpp
static constexpr uint8_t kBlobVersion = 1;

void                 write_fields(BlobWriter& w) const;
void                 read_fields (BlobReader& r);
std::vector<uint8_t> to_blob     () const;
bool                 from_blob   (const std::vector<uint8_t>& bytes);
```

`to_blob`/`from_blob` are what
[`Nvs::write_flex`/`read_flex`](#write_flex-and-read_flex) call. `kBlobVersion` is the
library's format version, not a per-struct one. The wire format, the version byte and how to
version your own struct are in [Blob format and versioning](#blob-format-and-versioning).

### Codec types

```cpp
struct BlobWriter { std::vector<uint8_t> bytes; void raw(const void* p, size_t n); };
struct BlobReader { const uint8_t* p; const uint8_t* end; bool ok = true; bool take(void* out, size_t n); };

template <typename T> void blob_write(BlobWriter&, const T&);                 // arithmetic or nested FlexData
inline                void blob_write(BlobWriter&, const std::string&);
template <typename T> void blob_write(BlobWriter&, const std::vector<T>&);
template <typename T> void blob_read (BlobReader&, T&);
inline                void blob_read (BlobReader&, std::string&);
template <typename T> void blob_read (BlobReader&, std::vector<T>&);
```

Public, and the extension point: adding an overload pair for your own type makes it usable as a
field.

### ArduinoJson converters

This header injects two specializations into `ArduinoJson`:

* `Converter<std::vector<T>>` — arrays of scalars, strings or nested `FlexData` structs.
* `Converter<T>` for any `T` deriving from `xewe::FlexData<T>` — which is what makes a nested
  struct work as an object *and* as a vector element.

They are global to the translation unit. If you serialize `std::vector<T>` with ArduinoJson
elsewhere in a sketch that includes `<XeWeCore.h>`, these are the converters that will be used.

## Blob format and versioning

`src/XeWeCore/Nvs/FlexData.h` — what `to_blob()` writes, and what happens when a struct changes.

### Layout

```
byte 0        : version    (kBlobVersion, currently 1)
bytes 1..n    : fields, in fields() tuple order
```

| Field type | Encoding |
|---|---|
| arithmetic | raw little-endian, `sizeof(T)` bytes |
| `std::string` | `uint32` byte length, then the bytes, no terminator |
| `std::vector<T>` | `uint32` element count, then each element |
| nested `FlexData` | its fields inline, **with no version byte of its own** |

Nesting therefore costs nothing, and the single leading byte is the only version marker in the
whole blob.

There are no field names, no type tags and no lengths except the two above. The reader relies
entirely on `fields()` matching what was written.

### from_blob

```cpp
bool from_blob(const std::vector<uint8_t>& bytes);
```

Returns `false` when the first byte is not `kBlobVersion`, and otherwise when the input ran out
mid-decode.

**A failed decode leaves the object partially overwritten.** Fields decoded before the failure
keep their new values; the rest keep whatever they had. `from_blob` does not work on a copy.

That is exactly the "I added a field and the old blob is still in flash" case:

```cpp
Settings s;                                  // constructed with defaults
if (!nvs.read_flex("app", "settings", s)) {
    s = Settings{};                          // discard the half-decoded object
}
```

Always reset on `false`. Treating the object as usable after a failed read is the most likely bug
in code using this library.

### Changing a struct

Any of these changes the binary layout and invalidates every stored blob:

* adding, removing or reordering a `fld` entry,
* changing a field's type, including `uint8_t` → `uint16_t`,
* changing a nested struct's fields.

Renaming a `fld` name changes only the JSON key, not the layout — the binary form does not store
names.

Because there is no schema in the blob, a layout change **is not detected**: the old bytes are
read against the new field list and produce plausible garbage, or run short and return `false`
after a partial write. Leftover bytes at the end are ignored, so removing the last field also goes
unnoticed. The version byte only catches a change you make deliberately.

#### kBlobVersion is not a per-struct version

`kBlobVersion` is a single constant on `xewe::FlexData` — the **library's** wire-format version,
shared by every struct. Two things follow, and both are easy to get wrong:

* **Shadowing it in your struct does nothing.** `to_blob()` resolves `kBlobVersion` in the base
  class scope, so a `static constexpr uint8_t kBlobVersion = 2;` in your own struct is silently
  ignored and version `1` is still written. It does not fail to compile; it just has no effect.
* **Raising it in the library invalidates every stored struct on every device**, not just the one
  you changed.

So version your own schema with a **field**, as the first entry in `fields()`, and check it after
reading:

```cpp
struct Settings : xewe::FlexData<Settings> {
    uint8_t     schema = 2;          // first field: bump when the layout changes
    uint8_t     brightness = 128;
    std::string label;

    static constexpr auto fields() {
        return std::make_tuple(fld("schema",     &Settings::schema),
                               fld("brightness", &Settings::brightness),
                               fld("label",      &Settings::label));
    }
};

Settings s;
if (!nvs.read_flex("app", "settings", s) || s.schema != Settings{}.schema) {
    s = Settings{};                  // missing, corrupt, or an older schema
}
```

Because `schema` is the first field it is the first thing decoded, so it is readable even when the
rest of the layout has moved underneath it.

There is no migration built in — a device with old data comes up with defaults. If the values have
to survive, read the blob with the old struct definition, copy the fields across, and write the
new one.

### Sizing

Fixed overhead is one byte for the version, plus four bytes per string and per vector. A struct of
two `uint8_t`s and a 10-character name is `1 + 1 + 1 + 4 + 10 = 17` bytes.

A blob is written as a single NVS entry, so its size is bounded by the NVS partition and by
ESP-IDF's per-blob limit. A settings struct stays far below both. For something large (a table, a
log), check the limits in the ESP-IDF NVS documentation. A write that does not fit fails with
`ESP_ERR_NVS_NOT_ENOUGH_SPACE` or `ESP_ERR_NVS_VALUE_TOO_LONG` (see
[set_error_handler](#set_error_handler)).
