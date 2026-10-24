# Adding or changing a core feature

One change carries all four of these:

1. The code in `src/XeWeCore/`, inside the include direction of `CODE_RULES.md`.
2. A host test in `tests/unit/test/`. When the case also runs through `$test` on a board, add it
   to the board table too (`TESTS.md`).
3. The component README, `src/XeWeCore/<Component>/README.md` or the page in `doc/`, for every
   public function, lifecycle step, command, prompt, NVS key or build define it adds or changes.
4. An example, when users see the change.

Then run the host tests, compile the examples and lint (`COMMANDS.md`). A version bump moves
`library.properties`, `library.json` and `XEWE_CORE_VERSION*` together, and
`scripts/release.sh --prepare` does it (`RELEASE.md`).

## Examples

`examples/01_Hello` and `examples/02_MyModule` teach levels 1 and 2. `11_Utils` to `15_Os` are
reference demos of one part each. All of them are teaching code, so their comments stay verbose.

`examples/02_MyModule` shows every module hook with the current signatures. Module authors copy
it, so update it with every new hook or changed signature. `01_Hello` and `02_MyModule` never
include `<XeWeBuildInfo.h>`, because a plain IDE build has none.
