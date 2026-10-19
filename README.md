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

Maintainers only. A release is two runs with a commit in between. First prepare it, on the branch
to release from (no git change is made):

```sh
scripts/release.sh --prepare X.Y.Z --dry-run            # prints every step, changes nothing
scripts/release.sh --prepare X.Y.Z                      # no board: the board tests are compiled, not run
scripts/release.sh --prepare X.Y.Z --hardware c3,c6,s3  # with the boards attached: flashed and run
```

It refuses a detached HEAD, a merge or rebase in progress, any change outside the version lines and
`releases/X.Y.Z/`, a `testcard.md` there, and a `.gitignore` that does not ignore `releases/*/logs/`.
It sets the version in `library.properties`, `library.json` and `XEWE_CORE_VERSION*`
(`src/XeWeCore/Os/XeWeOs.h`). When `releases/X.Y.Z/notes.txt` (the GitHub Release text) is missing it
writes a skeleton and stops with exit 2; fill it, delete its marker line and run again. Then it runs
every check through `xewe release-card record` (redacted logs in `releases/X.Y.Z/logs/`, never
committed) and renders `releases/X.Y.Z/release_card.md`:

| Kind | Steps |
|---|---|
| setup | the checkers' venv (the tools of `tests.yml`'s `xewe-core-tests.yml@<tag>`, ruff, clang-format), ArduinoJson at the CI tag, the board-test harness |
| unit | `tests/unit/run.sh`: one row per test and C++ standard (`c++17`, `gnu++2b`) |
| validate | `arduino-lint --compliance strict --library-manager update` (the official binary, installed into `build/release-venv/bin` when missing) |
| check | `xewe format --check`, `xewe brand-lint .` |
| build | every `examples/*/*.ino` for c3, c6 and s3, as CI's `examples` job compiles them |
| board, flash | the `tests/board` files through `xewe test` per chip; a `--hardware` chip is flashed first and needs its board |

The board tests run in a harness: a copy of an xewe project (`--harness <dir>`, else
`XEWE_RELEASE_HARNESS`, else `../xewe-os`) in `build/release-harness/project`, with this tree's
`tests/board` as its tests, this tree as the core (`XEWE_CORE_SOURCE`), the modules the tests drive
and `XEWE_TESTING=1`. `XEWE_TOOLS_SOURCE` (a local tools checkout) replaces the tools tag; the board
run reads its dotenv file as the tools do (`XEWE_ENV`, else the harness's, else the tools checkout's).
A failed step does not stop the others; the card then refuses (exit 1) and leaves a draft in the
logs folder. Fix the cause and run `--prepare X.Y.Z --resume`, which re-runs only the steps that are
not green while commit and tree are unchanged. Commit the files it lists as one `prepare X.Y.Z`
commit and push it; the `tests` workflow's card job compares the card with CI's own host test run.
Then, from that clean `main`, level with `origin/main`:

```sh
scripts/release.sh X.Y.Z --dry-run   # prints every step and HEAD's CI state, changes nothing
scripts/release.sh X.Y.Z
```

It runs five numbered stages: 1 preflight (version, branch, clean tree, level with origin, tag free,
`notes.txt` and `release_card.md` committed, no `testcard.md`, every version location already at
X.Y.Z, `gh`); 2 `xewe release-card verify` (the card is as rendered, its tested tree is HEAD's and
the local logs it lists are present); 3 waits for the `tests` workflow on HEAD to pass with its card
check run; 4 tags HEAD `X.Y.Z` (no `v`), pushes the tag and creates the GitHub Release with the card
as its only asset; 5 prints where to check the Arduino Library Manager, which picks the tag up by
itself, usually within a day. A tag is only made once CI on HEAD is green.

Options: `--dry-run` (no writes; read-only `gh` queries only); `--ci-timeout <min>` (default 30)
bounds the CI wait; `--skip-ci` skips the CI gate, for emergencies only, with a loud warning; `-h`
prints the usage. Exit codes: 0 done, 1 a refusal or a failed check, 2 `notes.txt` to fill. If a run
stops before the tag (CI red or timed out), fix the cause with a new commit and prepare again. If the
tag exists but the GitHub Release does not, the same command only creates the release from the
tagged commit's notes and card, provided its files say the version; with tag and release both
present it reports the version as already released. What keeps the library valid for the Library
Manager (layout, `library.properties`, names) is in [doc/library-rules.md](doc/library-rules.md).

## License

GPL-3.0-only. See [LICENSE.txt](LICENSE.txt).
