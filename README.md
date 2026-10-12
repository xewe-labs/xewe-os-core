# XeWeCore

Modular firmware core for ESP32, as one Arduino library: a serial console, a `$group command`
command line, typed NVS storage, small helpers and a module framework. You write modules; the core
gives each one its commands, its stored settings and its place in the boot order.

* **Boards:** ESP32 family (arduino-esp32 3.x). The examples compile for ESP32-C3, C6 and S3.
* **Depends on:** [ArduinoJson](https://arduinojson.org/) 7, installed with it.

## Install

Arduino IDE: **Library Manager → search `XeWeCore` → Install**. With arduino-cli:
`arduino-cli lib install XeWeCore`.

```cpp
#include <XeWeCore.h>

XeWeOs os({.project_name = "my-device", .version = "0.1.0"});

void setup() { os.begin(); }
void loop()  { os.loop();  }
```

Upload, open the Serial Monitor at 115200 baud and type `$help`.

## Three levels

| Level | You need | Start with |
|---|---|---|
| 1. Use the console | Arduino IDE + XeWeCore | [`examples/01_Hello`](examples/01_Hello/01_Hello.ino): `$help`, `$system status`, a device name kept in NVS |
| 2. Write a module | the same, plus one module in your sketch folder | [`examples/02_MyModule`](examples/02_MyModule/02_MyModule.ino): your own `$my …` commands, a settings table, enable/disable |
| 3. Build a product | the [xewe-os](https://github.com/xewe-labs/xewe-os) project template and its tools | ready-made modules (Wi-Fi, web interface, scheduler, …), multi-chip builds, board tests, releases |

Levels 1 and 2 need nothing but the IDE. The other examples (`11_Utils` … `15_Os`) show one part
each; see [doc/examples.md](doc/examples.md).

## Documentation

[`doc/`](doc/README.md) explains what the core is and why it is built this way, then documents
every public type, command and stored key. Building and testing the library itself:
[doc/tests.md](doc/tests.md).

## Releasing

Maintainers only. A release is two steps. First prepare it:

```sh
scripts/release.sh --prepare 3.0.1   # sets the version, adds the releases/3.0.1/ skeletons
```

This sets the version in `library.properties`, `library.json` and `XEWE_CORE_VERSION*`
(`src/XeWeCore/XeWeOs.h`) and creates `releases/3.0.1/notes.txt` (the GitHub Release text) and
`testcard.md` (what was tested on which commits, attached to the release) when they are missing.
Fill both in, then commit everything as one `prepare 3.0.1` commit and push it to `main`. Then,
from that clean `main`, level with `origin/main`:

```sh
scripts/release.sh 3.0.1 --dry-run   # prints every step and HEAD's CI state, changes nothing
scripts/release.sh 3.0.1
```

It runs five numbered stages: 1 preflight (version, branch, clean tree, level with origin, tag free,
release files committed, every version location already at 3.0.1, `gh`); 2 waits for the `tests`
workflow on HEAD to pass; 3 host tests and the format check; 4 tags HEAD `3.0.1` (no `v`), pushes
the tag and creates the GitHub Release; 5 prints where to check the Arduino Library Manager, which
picks the tag up by itself, usually within a day. A tag is only made once CI on HEAD is green.

Options: `--dry-run` (no writes; read-only `gh` queries only); `--ci-timeout <min>` (default 30)
bounds the CI wait; `--skip-ci` skips the CI gate, for emergencies only, with a loud warning;
`--prepare <version>` as above; `-h` prints the usage. If a run stops before the tag (CI red or
timed out), fix the cause with a new commit and run it again. If the tag exists but the GitHub
Release does not, the same command only creates the release, provided the tagged commit's files say
the version; with tag and release both present it reports the version as already released. What
keeps the library valid for the Library Manager (layout, `library.properties`, names) is in
[doc/library-rules.md](doc/library-rules.md).

## License

GPL-3.0-only. See [LICENSE.txt](LICENSE.txt).
