# Release

Versions and releases go through `scripts/release.sh`, and only when the human asks. The owner
releases, in two runs with a commit in between. `scripts/README.md` describes every stage, option
and exit code.

Run `scripts/release.sh <version> --dry-run` freely. Run `--prepare` only on a scratch copy of the
repository unless the human asked, and never run the tag run yourself.

1. `scripts/release.sh --prepare <version> [--hardware c3,c6,s3] [--harness DIR]` makes no git
   change. It moves the version in `library.properties`, `library.json` and `XEWE_CORE_VERSION*`
   together, writes the `releases/<version>/notes.txt` skeleton and stops with exit 2 until the
   notes are filled. Then it runs every check through `xewe release-card record` and renders
   `releases/<version>/release_card.md`. The card is generated, never hand-written, and the run
   logs stay in `releases/<version>/logs/`, which is gitignored. Without `--hardware` the board
   tests are compiled, not run. The owner commits the result as one `prepare <version>` commit.
2. `scripts/release.sh <version>` checks that HEAD is a pushed, clean `main` with every version
   location at `<version>`, runs `xewe release-card verify`, and waits for the `tests` workflow on
   HEAD with its card check green. There is no separate wait-for-CI step, and the script never
   tags a commit whose CI is not green. Then it tags HEAD and creates the GitHub Release with the
   card as its only asset.

`--ci-timeout <min>` bounds the CI wait, 30 minutes by default. `--skip-ci` is for emergencies
only. A rerun with a tag but no GitHub Release only creates the release, provided the tagged
commit's files say `<version>`. With tag and release both present, the version counts as
released.

The Library Manager rules, covering the layout, `library.properties`, `library.json` and names,
are in `doc/LIBRARY_RULES.md`.
