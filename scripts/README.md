# scripts

`release.sh` tests, cards, tags and publishes a XeWeCore version. Only maintainers run it. A
release is two runs with a commit in between, and `scripts/release.sh -h` prints the usage.

```sh
scripts/release.sh --prepare X.Y.Z --dry-run            # prints every step, changes nothing
scripts/release.sh --prepare X.Y.Z                      # no board: the board tests are compiled, not run
scripts/release.sh --prepare X.Y.Z --hardware c3,c6,s3  # with the boards attached: flashed and run
scripts/release.sh X.Y.Z --dry-run                      # prints every step and HEAD's CI state
scripts/release.sh X.Y.Z
```

## The prepare run

`--prepare X.Y.Z` runs on the branch you release from and makes no git change. It has 9 stages.

1. Preflight. It refuses a detached HEAD, a merge, rebase, cherry-pick or revert in progress,
   unmerged paths, any change outside the version lines and `releases/X.Y.Z/`, a
   `releases/X.Y.Z/testcard.md`, and a `.gitignore` that does not ignore `releases/*/logs/`. It
   finds the tools ref (the `xewe-core-tests.yml@<ref>` line of `tests.yml`), Python 3.11 or
   newer, g++, curl and the harness project.
2. Versions. It sets `library.properties`, `library.json` and `XEWE_CORE_VERSION*` in
   `src/XeWeCore/Os/XeWeOs.h` to X.Y.Z.
3. Release notes. When `releases/X.Y.Z/notes.txt`, the GitHub Release text, is missing, it
   writes a skeleton and stops with exit 2. Fill it, delete its marker line and run again.
4. Card run. It installs the tools into `build/release-venv/card` and runs
   `xewe release-card init` on `releases/X.Y.Z/logs/`, which is gitignored.
5. Setup, recorded. It builds the checkers' venv (the tools, ruff and clang-format, as CI's format
   job pins them), fetches ArduinoJson at the CI tag and sets up the harness.
6. Checks, recorded. It runs `tests/unit/run.sh` (one row per test and C++ standard),
   `arduino-lint --compliance strict --library-manager update` on an export of the tree (the
   official binary goes into `build/release-venv/bin` when missing), `xewe format --check` and
   `xewe brand-lint .`.
7. Examples, recorded per chip. Every `examples/*/*.ino` compiles for c3, c6 and s3 as CI's
   `examples` job compiles them, with the harness toolchain.
8. Board, recorded per chip. The `tests/board` files run through `xewe test` in the harness. A
   chip without `--hardware` builds with `XEWE_NO_BOARD=1`, so its board tests are compiled, not
   run. A `--hardware` chip is built, flashed and tested with `--require-board`, so its board must
   be attached.
9. Card. `xewe release-card render` writes `releases/X.Y.Z/release_card.md`, or refuses and leaves
   a draft in the logs folder. The run prints the commit command.

The run logs in `releases/X.Y.Z/logs/` are redacted and never committed. A failed step does not
stop the others, and the card then refuses with exit 1. Fix the cause and run
`--prepare X.Y.Z --resume`, which keeps the run while commit and tree are unchanged and re-runs
only the steps that are not green.

Commit the files it lists as one `prepare X.Y.Z` commit and push it. The `tests` workflow's card
job then compares the card with CI's own host test run.

### The harness

The board tests run in a copy of an xewe project, taken from `--harness <dir>`, else
`XEWE_RELEASE_HARNESS`, else `../xewe-os`. The copy lives in `build/release-harness/project`. It
uses this tree's `tests/board` as its tests and this tree as the core (`XEWE_CORE_SOURCE`, exported
to `build/release-venv/XeWeCore`). It enables the modules the tests drive (buttons, pins, wifi,
time, scheduler and web-interface) and builds with `XEWE_TESTING=1` for the `$test` hooks.

`XEWE_TOOLS_SOURCE`, a local tools checkout, replaces the tools tag. The board run reads its
dotenv file the way the tools do: `XEWE_ENV`, else the harness's `.env`, else the tools checkout's
`.env`. The script itself never reads it.

## The tag run

`release.sh X.Y.Z` runs from a clean `main` that is level with `origin/main`. It has 5 stages.

1. Preflight. The version is X.Y.Z without a `v`. HEAD is on `main`, clean and level with
   `origin/main` after a fetch. The tag is free locally and on origin. `notes.txt`, with no
   skeleton marker, and `release_card.md` are committed in `releases/X.Y.Z/`. There is no
   `testcard.md`. Every version location says X.Y.Z, and `gh` is logged in.
2. Card. `xewe release-card verify` checks that the card is as rendered, that its tested tree is
   HEAD's clean tree and that the local logs it lists are present with their sha256.
3. CI gate. The newest `tests` run for HEAD on `main` must pass, with the card job's verify step
   run and green. The script waits up to `--ci-timeout` minutes.
4. Tag. It makes an annotated tag X.Y.Z on HEAD, pushes it and runs `gh release create` with
   `--verify-tag`, the notes from `notes.txt` and `release_card.md` as the only asset.
5. It prints where to check the Arduino Library Manager, which picks up the tag by itself, usually
   within a day.

A tag is made only once CI on HEAD is green. If a run stops before the tag because CI was red or
timed out, fix the cause with a new commit and prepare again. A rerun resumes. A tag without a
GitHub Release only creates the release (pushing the tag first if origin lacks it) from the tagged
commit's notes and card, provided its files say the version. With tag and release both present it
reports the version as already released.

## Options and exit codes

| Option | Effect |
|---|---|
| `--dry-run` | prints every command and changes nothing. Only read-only git, `gh` and tool lookups and `release-card verify` run. It reports every failed check, never waits, and exits 1 if a check failed |
| `--ci-timeout <min>` | bounds the CI wait, 30 minutes by default |
| `--skip-ci` | skips the CI gate, with a loud warning. Use it in emergencies only |
| `-h` | prints the usage |

The script exits 0 when done, 1 on a refusal or a failed check, and 2 when
`releases/X.Y.Z/notes.txt` needs filling.

What keeps the library valid for the Library Manager is in
[doc/LIBRARY_RULES.md](../doc/LIBRARY_RULES.md).
