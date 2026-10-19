#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
# SPDX-License-Identifier: GPL-3.0-only
# xewe-os-core/scripts/release.sh
#
# release.sh: test, card, tag and publish XeWeCore <version>.
# Usage: scripts/release.sh --prepare <version> [--hardware c3,c6,s3] [--harness <dir>] [--resume] [--dry-run] | <version> [--dry-run] [--ci-timeout <min>] [--skip-ci]
# A release is two runs with a commit in between.
# `scripts/release.sh --prepare <version>` (9 stages) makes no git change:
#   1 preflight: refuses a detached HEAD, a merge/rebase/cherry-pick/revert in progress, unmerged
#     paths, any change outside the version lines of VERSION_LOCATIONS and releases/<version>/, a
#     releases/<version>/testcard.md, and a .gitignore that does not ignore releases/*/logs/; finds
#     the tools ref (tests.yml's xewe-core-tests.yml@<ref>), Python >= 3.11, g++, curl and the
#     harness project (an xewe project: --harness, else XEWE_RELEASE_HARNESS, else ../xewe-os);
#   2 versions: sets library.properties, library.json and XEWE_CORE_VERSION* to <version>;
#   3 release notes: releases/<version>/notes.txt; when it is missing a skeleton is written, and
#     while the skeleton marker is in it the run stops with exit 2 (fill it, run again);
#   4 card run: a venv with the tools (build/release-venv/card), then `xewe release-card init` on
#     releases/<version>/logs/ (gitignored);
#   5 setup (recorded): the checkers' venv (tools + ruff + clang-format, as CI's format job),
#     ArduinoJson at the CI tag, and the harness: a copy of the harness project in
#     build/release-harness/project with this tree's tests/board as its tests/, set up with
#     XEWE_CORE_SOURCE=<this tree, exported to build/release-venv/XeWeCore> and the modules the
#     board tests drive;
#   6 checks (recorded): tests/unit/run.sh (unit, core-host rows: c++17 and gnu++2b),
#     arduino-lint --compliance strict --library-manager update on the export (validate; the
#     official binary is installed into build/release-venv/bin when missing), `xewe format
#     --check`, `xewe brand-lint .`;
#   7 examples (recorded, per chip): every examples/*/*.ino compiled as CI does (`arduino-cli
#     compile --fqbn <tools FQBN> --warnings default --library .`), with the harness toolchain;
#   8 board (recorded, per chip): the 19 tests/board files through `xewe test` in the harness. A
#     chip without --hardware is built with XEWE_NO_BOARD=1: its board tests are "compiled, not
#     run". A --hardware chip is built, flashed (a flash step) and tested with --require-board;
#   9 card: `xewe release-card render` writes releases/<version>/release_card.md (or refuses: the
#     draft is in the logs folder); prints the commit command.
# A failing step does not stop the others; the card refuses it. --resume (after a failed step):
# keeps the run when commit and tree are unchanged and re-runs only the steps that are not green.
# Commit the listed files as "prepare <version>" and push; the tests workflow's card job then checks
# the card against its own host test run. The board steps build with XEWE_TESTING=1 (the $test
# hooks); XEWE_ENV, else the harness's .env, else the tools checkout's .env is the dotenv the board
# run uses (Wi-Fi, test pins, defines): the script never reads it, the tools do.
# `scripts/release.sh <version>` (5 stages), the tag run:
#   1 preflight: version X.Y.Z without `v`; on main, clean, level with origin/main after a fetch;
#     tag free locally and on origin; notes.txt (no skeleton marker) and release_card.md committed
#     in releases/<version>/; no testcard.md; every version location says <version>; gh logged in;
#   2 release card: `xewe release-card verify` (the card is as rendered, its tested tree is HEAD's
#     clean tree, the local logs it lists are present with their sha256);
#   3 CI gate on HEAD: the newest `tests` run for HEAD on main must succeed, with the card job's
#     verify step run and green (waits; --ci-timeout minutes, default 30);
#   4 annotated tag <version> on HEAD, push it, `gh release create` (--verify-tag, notes from
#     notes.txt, release_card.md the only asset);
#   5 print where to check the Arduino Library Manager (it picks the tag up by itself).
# Re-running the tag run resumes: a tag without a GitHub Release only creates the release (pushing
# the tag first if origin lacks it) from the tagged commit's notes.txt and release_card.md, provided
# its files say <version>. Tag and release both present: already released. --skip-ci skips the CI
# gate (emergencies only). --dry-run prints every command and changes nothing: only read-only git,
# gh and tool lookups and `release-card verify` run; it reports every failed check, never waits,
# and exits 1 if a check failed.
# Exit codes: 0 done, 1 a refusal or a failed check, 2 releases/<version>/notes.txt to fill.
set -euo pipefail

REPO="xewe-labs/xewe-os-core"
TITLE="XeWeCore"
TOOLS_URL="https://github.com/xewe-labs/xewe-os-tools"
CI_WORKFLOW="tests"                                  # .github/workflows/tests.yml
CI_FILE=".github/workflows/tests.yml"
CI_CARD_JOB="core / release card check"              # caller job id / xewe-core-tests.yml job name
CI_CARD_STEP="xewe release-card verify --ci"         # its step that compares the card with the run
CI_POLL="${RELEASE_CI_POLL:-15}"                     # seconds between CI polls
VENVS="build/release-venv"                           # gitignored (build/)
HARNESS="build/release-harness/project"             # the harness copy (gitignored)
EXPORT="build/release-venv/XeWeCore"                 # the tree as a commit of it would hold it
CHIPS=(c3 c6 s3)
REQUIRE="setup,validate,unit,build,board"
CHECKERS=("ruff==0.17.0" "clang-format==23.1.3")    # xewe-core-tests.yml format job pins
ARDUINOJSON_REPO="https://github.com/bblanchon/ArduinoJson"
ARDUINOJSON_REF="v7.4.3"                             # xewe-core-tests.yml arduinojson_ref default
ARDUINO_LINT_VERSION="1.3.0"
ARDUINO_LINT_URL="https://github.com/arduino/arduino-lint/releases/download"
BOARD_MODULES="buttons,pins,wifi,time,scheduler,web-interface" # what tests/board drives
BOARD_DEFINES="XEWE_TESTING=1"                       # the $test hooks of test_hooks_*.py
NOTES_MARKER="XEWE-NOTES-SKELETON"
LIBRARY_MANAGER_URL="https://docs.arduino.cc/libraries/xewecore/"
REGISTRY_URL="https://github.com/arduino/library-registry"

# Every place that states the core's version: "file|ERE|replacement"; {V} is the version, {MAJOR},
# {MINOR}, {PATCH} its parts. Each pattern must match exactly one line; --prepare rewrites it and
# the preflight fails when that rewrite would change anything else. ERE is portable (GNU and BSD
# sed -E); no `|` inside. library.json's ArduinoJson ">=7.0.0" is indented deeper and never matches.
VERSION_LOCATIONS=(
  'library.properties|^version=.*$|version={V}'
  'library.json|^(  "version": )"[^"]*"|\1"{V}"'
  'src/XeWeCore/Os/XeWeOs.h|^(#define XEWE_CORE_VERSION[[:space:]]+)"[^"]*"|\1"{V}"'
  'src/XeWeCore/Os/XeWeOs.h|^(#define XEWE_CORE_VERSION_MAJOR[[:space:]]+)[0-9]+|\1{MAJOR}'
  'src/XeWeCore/Os/XeWeOs.h|^(#define XEWE_CORE_VERSION_MINOR[[:space:]]+)[0-9]+|\1{MINOR}'
  'src/XeWeCore/Os/XeWeOs.h|^(#define XEWE_CORE_VERSION_PATCH[[:space:]]+)[0-9]+|\1{PATCH}'
)

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
STAGES=5
stage() { echo "== $1/${STAGES} $2"; }

# A failed preflight check: fatal in a real run; a dry run notes it and goes on.
FAILED=0
fail() {
  [[ "${DRY_RUN}" == 1 ]] || die "$*"
  echo "error: $*" >&2
  FAILED=$((FAILED + 1))
}

# Runs a command, or only prints it with --dry-run.
run() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    printf '+'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# file_at REF FILE: FILE's content at commit REF, or in the working tree when REF is empty.
file_at() {
  if [[ -z "$1" ]]; then cat -- "$2"; else git show "$1:$2"; fi
}

# replacement LOCATION VERSION: the replacement of LOCATION with {V}/{MAJOR}/{MINOR}/{PATCH} filled.
replacement() {
  local repl="${1##*|}" major minor patch
  IFS=. read -r major minor patch <<< "$2"
  repl="${repl//\{V\}/$2}"
  repl="${repl//\{MAJOR\}/${major}}"
  repl="${repl//\{MINOR\}/${minor}}"
  echo "${repl//\{PATCH\}/${patch}}"
}

# set_location LOCATION VERSION REF: print the file of LOCATION (at REF, see file_at) with the
# location set to VERSION; exit 1 unless the pattern matches exactly one line.
set_location() {
  local file pattern rest
  file="${1%%|*}"; rest="${1#*|}"; pattern="${rest%%|*}"
  # grep reads all input (no -q): an early exit would SIGPIPE git show and fail the pipeline.
  [[ "$(file_at "$3" "${file}" 2>/dev/null | grep -Ec -- "${pattern}" || true)" == 1 ]] || return 1
  file_at "$3" "${file}" | sed -E "s|${pattern}|$(replacement "$1" "$2")|"
}

# versioned FILE VERSION REF: FILE at REF with every one of its locations set to VERSION.
versioned() {
  local loc rest pattern args=()
  for loc in "${VERSION_LOCATIONS[@]}"; do
    [[ "${loc%%|*}" == "$1" ]] || continue
    rest="${loc#*|}"; pattern="${rest%%|*}"
    args+=(-e "s|${pattern}|$(replacement "${loc}" "$2")|")
  done
  file_at "$3" "$1" | sed -E "${args[@]}"
}

# version_files: every file named in VERSION_LOCATIONS, once.
version_files() {
  local loc
  for loc in "${VERSION_LOCATIONS[@]}"; do echo "${loc%%|*}"; done | awk '!seen[$0]++'
}

# stale_locations VERSION REF: print "file: line" for every location (at REF) that does not say
# VERSION yet, or whose pattern does not match exactly one line.
stale_locations() {
  local loc file pattern
  for loc in "${VERSION_LOCATIONS[@]}"; do
    file="${loc%%|*}"; pattern="$(cut -d'|' -f2 <<< "${loc}")"
    if ! set_location "${loc}" "$1" "$2" >/dev/null; then
      echo "${file}: not exactly one line matches ${pattern}"
    elif ! cmp -s <(file_at "$2" "${file}") <(set_location "${loc}" "$1" "$2"); then
      echo "${file}: $(file_at "$2" "${file}" | grep -Em1 -- "${pattern}")"
    fi
  done
}

# allowed_change PATH VERSION: true for a path --prepare may find changed: anything under
# releases/VERSION/, or a version file whose only change from HEAD is its version lines.
allowed_change() {
  [[ "$1" == "releases/$2/"* ]] && return 0
  version_files | grep -xF -- "$1" >/dev/null || return 1 # no -q: an early exit would SIGPIPE awk
  [[ -f "$1" ]] && git cat-file -e "HEAD:$1" 2>/dev/null && cmp -s "$1" <(versioned "$1" "$2" HEAD)
}

# tree_problems VERSION: one line per reason the work tree cannot be prepared; none when it can.
tree_problems() {
  local v="$1" p path entry code unmerged dirty=()
  git symbolic-ref -q HEAD >/dev/null || echo "HEAD is detached: check out the branch to release from"
  for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD REBASE_HEAD rebase-merge rebase-apply; do
    path="$(git rev-parse --git-path "${p}")"
    [[ -e "${path}" ]] && echo "a merge, rebase, cherry-pick or revert is in progress (${path} exists): finish or abort it first"
  done
  unmerged="$(git diff --name-only --diff-filter=U)"
  [[ -z "${unmerged}" ]] || echo "unmerged (conflicted) paths: $(tr '\n' ' ' <<< "${unmerged}")"
  # porcelain v1 -z: "XY path", a rename or copy followed by its original path as its own field
  while IFS= read -r -d '' entry; do
    code="${entry:0:2}"; path="${entry:3}"
    allowed_change "${path}" "${v}" || dirty+=("${path}")
    if [[ "${code}" == *[RC]* ]]; then
      IFS= read -r -d '' path || true
      allowed_change "${path}" "${v}" || dirty+=("${path}")
    fi
  done < <(git status --porcelain=v1 -z --untracked-files=all)
  if [[ "${#dirty[@]}" -gt 0 ]]; then
    echo "changes outside the version lines and releases/${v}/ (commit or stash them first): ${dirty[*]}"
  fi
  git check-ignore -q "releases/${v}/logs/run.json" \
    || echo ".gitignore does not ignore releases/*/logs/ (the run folder must never be committed)"
  [[ ! -e "releases/${v}/testcard.md" ]] \
    || echo "releases/${v}/testcard.md exists: the generated release_card.md replaces it; delete it"
}

# tools_ref: the ref of tests.yml's `uses: …/xewe-core-tests.yml@<ref>` (the tools CI runs with).
tools_ref() {
  sed -nE 's|^ *uses: *xewe-labs/xewe-os-tools/[.]github/workflows/xewe-core-tests[.]yml@([^ ]+) *$|\1|p' "${CI_FILE}" | head -n 1
}

# find_python: python3.12 (CI's card and format jobs), else the first python3 >= 3.11 on PATH.
find_python() {
  local cand p
  for cand in python3.12 python3 python3.13 python3.14 python3.11; do
    p="$(command -v "${cand}" 2>/dev/null)" || continue
    if "${p}" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
      echo "${p}"
      return 0
    fi
  done
  return 0
}

# short_secrets: names of environment variables the card's redactor treats as secrets whose value
# is 4-7 characters. It replaces such a value anywhere in a log, so it can rewrite the core host
# test ids parsed from run.sh's log (tools REREVIEW L1); CI then sees other ids and blocks.
short_secrets() {
  local key value
  while IFS= read -r key; do
    value="${!key-}"
    case "$(tr '[:upper:]' '[:lower:]' <<< "${value}")" in true|false|none|null|yes) continue ;; esac
    if [[ "${#value}" -ge 4 && "${#value}" -lt 8 ]]; then echo "${key}"; fi
  done < <(env | sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' | grep -Ei 'PSW|PASS|PASSWORD|SECRET|TOKEN|KEY|SSID' || true)
}

tag_local() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }
tag_remote() { git ls-remote --exit-code --tags origin "refs/tags/$1" >/dev/null 2>&1; }

# tag_commit VERSION: the commit the tag points at (local tag first, else origin's peeled tag).
tag_commit() {
  if tag_local "$1"; then
    git rev-parse "refs/tags/$1^{commit}"
  else
    git ls-remote --tags origin \
      | awk -v t="refs/tags/$1" '$2 == t { c = $1 } $2 == t "^{}" { p = $1 } END { print (p != "" ? p : c) }'
  fi
}

# ci_run SHA: the newest run of CI_WORKFLOW for SHA on main, as "id status url conclusion" (empty
# when there is none yet; conclusion is empty while the run is not completed).
ci_run() {
  gh run list --commit "$1" --workflow "${CI_WORKFLOW}" --branch main --limit 20 \
    --json databaseId,status,url,conclusion \
    --jq '.[0] | select(. != null) | "\(.databaseId) \(.status) \(.url) \(.conclusion)"'
}

# card_step_result RUN_ID: the conclusion of the card job's verify step in that run (skipped when
# the job found no card for the commit).
card_step_result() {
  gh run view "$1" --json jobs \
    --jq ".jobs[] | select(.name == \"${CI_CARD_JOB}\") | .steps[] | select(.name == \"${CI_CARD_STEP}\") | .conclusion"
}

# ci_gate SHA: wait for CI_WORKFLOW on SHA and fail unless it succeeds with the card compared,
# within CI_TIMEOUT minutes.
ci_gate() {
  local sha="$1" deadline=$((SECONDS + CI_TIMEOUT * 60)) line id status url conclusion pid card
  if [[ "${SKIP_CI}" == 1 ]]; then
    warn "!!!!!!!! --skip-ci: CI on ${sha:0:12} is NOT checked; this release may ship a red build !!!!!!!!"
    return 0
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ gh run list --commit ${sha} --workflow ${CI_WORKFLOW} --branch main ... (poll every ${CI_POLL}s until a run appears, up to ${CI_TIMEOUT} min)"
    echo "+ gh run watch <run id> --exit-status (if not completed; fail unless success)"
    echo "+ gh run view <run id> --json jobs (job '${CI_CARD_JOB}', step '${CI_CARD_STEP}' must be success, not skipped)"
    if [[ "${GH_OK}" == 1 && "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
      line="$(ci_run "${sha}" 2>/dev/null)" || line="(gh run list failed)"
      echo "   current CI state of ${sha:0:12}: ${line:-no ${CI_WORKFLOW} run yet}"
      read -r id status url conclusion <<< "${line:-x x x x}"
      if [[ "${status}" == completed ]]; then
        card="$(card_step_result "${id}" 2>/dev/null)" || card="(gh run view failed)"
        echo "   card check of that run: ${card:-no \"${CI_CARD_STEP}\" step}"
      fi
    fi
    return 0
  fi
  echo "   waiting for a ${CI_WORKFLOW} run on ${sha:0:12} (timeout ${CI_TIMEOUT} min)"
  while :; do
    line="$(ci_run "${sha}")" || die "gh run list failed"
    [[ -n "${line}" ]] && break
    (( SECONDS < deadline )) || die "timed out after ${CI_TIMEOUT} min: no ${CI_WORKFLOW} run for ${sha:0:12} on main"
    sleep "${CI_POLL}"
  done
  read -r id status url conclusion <<< "${line}"
  echo "   run ${url} (${status})"
  if [[ "${status}" != completed ]]; then
    gh run watch "${id}" --exit-status --interval "${CI_POLL}" &
    pid=$!
    while kill -0 "${pid}" 2>/dev/null; do
      if (( SECONDS >= deadline )); then
        kill "${pid}" 2>/dev/null || true
        die "timed out after ${CI_TIMEOUT} min, CI still running: ${url}"
      fi
      sleep 2
    done
    wait "${pid}" || die "CI failed: ${url}"
    conclusion=success
  fi
  [[ "${conclusion}" == success ]] || die "CI ${conclusion:-did not succeed}: ${url}"
  card="$(card_step_result "${id}")" || die "gh run view ${id} failed"
  [[ "${card}" == success ]] \
    || die "CI ${url}: the '${CI_CARD_JOB}' job compared no card with this commit (step '${CI_CARD_STEP}': ${card:-not found}); is releases/${VERSION}/release_card.md the card of this tree?"
  echo "   CI passed, card compared: ${url}"
}

# tools_spec: what pip installs as the tools: XEWE_TOOLS_SOURCE (a local checkout), else the tools
# repo at TOOLS_REF (the tag CI runs with).
tools_spec() {
  if [[ -n "${XEWE_TOOLS_SOURCE:-}" ]]; then echo "${XEWE_TOOLS_SOURCE}"; else echo "git+${TOOLS_URL}@${TOOLS_REF}"; fi
}

# card_tools PYTHON: the venv whose tools run `xewe release-card` (not recorded: it makes the card).
# XEWE is the command prefix.
card_tools() {
  local commit
  XEWE=("${VENVS}/card/bin/python" -m xewe)
  run "$1" -m venv --clear "${VENVS}/card"
  run "${VENVS}/card/bin/python" -m pip install -q --disable-pip-version-check --progress-bar off "$(tools_spec)"
  # the tools commit the card header names (the venv is not an editable install)
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ (tools commit) > ${VENVS}/card/xewe-tools-commit"
    return 0
  fi
  if [[ -n "${XEWE_TOOLS_SOURCE:-}" ]]; then
    commit="$(git -C "${XEWE_TOOLS_SOURCE}" rev-parse HEAD 2>/dev/null || echo -)"
  else
    commit="$(git ls-remote "${TOOLS_URL}" "refs/tags/${TOOLS_REF}^{}" "refs/tags/${TOOLS_REF}" "refs/heads/${TOOLS_REF}" \
      | awk '{ c[NR] = $1 } END { print (NR ? c[1] : "-") }')"
  fi
  echo "${commit:--}" > "${VENVS}/card/xewe-tools-commit"
}

# step LABEL RECORD_ARGS...: one recorded step; a failed command is noted and the run goes on (the
# card refuses it), a usage error stops.
FAILED_STEPS=()
step() {
  local label="$1" rc=0
  shift
  if [[ "${DRY_RUN}" == 1 ]]; then
    run "${XEWE[@]}" release-card record --dir "${LOGS}" ${RESUME_ARGS[@]+"${RESUME_ARGS[@]}"} "$@"
    return 0
  fi
  "${XEWE[@]}" release-card record --dir "${LOGS}" ${RESUME_ARGS[@]+"${RESUME_ARGS[@]}"} "$@" || rc=$?
  case "${rc}" in
    0) ;;
    1|3) FAILED_STEPS+=("${label}"); warn "${label} failed (exit ${rc}; the log is in ${LOGS}); going on" ;;
    *) die "xewe release-card record exited ${rc} on ${label}" ;;
  esac
}

# arduino_lint: build/release-venv/bin/arduino-lint, the official release binary (checksum-checked),
# installed when missing.
arduino_lint() {
  local bin="${VENVS}/bin/arduino-lint" os arch name dir
  [[ -x "${bin}" ]] && return 0
  case "$(uname -s)" in Linux) os=Linux ;; Darwin) os=macOS ;; *) die "arduino-lint: no release binary for $(uname -s)" ;; esac
  case "$(uname -m)" in
    x86_64|amd64) arch=64bit ;;
    arm64|aarch64) arch=ARM64 ;;
    *) die "arduino-lint: no release binary for $(uname -m)" ;;
  esac
  name="arduino-lint_${ARDUINO_LINT_VERSION}_${os}_${arch}.tar.gz"
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ (install) ${ARDUINO_LINT_URL}/${ARDUINO_LINT_VERSION}/${name}, sha256 from ${ARDUINO_LINT_VERSION}-checksums.txt -> ${bin}"
    return 0
  fi
  echo "   installing arduino-lint ${ARDUINO_LINT_VERSION} (${name}) into ${VENVS}/bin"
  dir="${VENVS}/arduino-lint-download"
  rm -rf "${dir}"
  mkdir -p "${dir}" "${VENVS}/bin"
  curl -fsSL -o "${dir}/${name}" "${ARDUINO_LINT_URL}/${ARDUINO_LINT_VERSION}/${name}" || die "cannot download ${name}"
  curl -fsSL -o "${dir}/checksums.txt" "${ARDUINO_LINT_URL}/${ARDUINO_LINT_VERSION}/${ARDUINO_LINT_VERSION}-checksums.txt" \
    || die "cannot download the arduino-lint checksums"
  (cd "${dir}" && grep -E " [*]?${name}\$" checksums.txt | sed 's/ [*]/  /' > want.txt \
    && [[ -s want.txt ]] && { sha256sum -c want.txt 2>/dev/null || shasum -a 256 -c want.txt; }) >/dev/null \
    || die "arduino-lint: ${name} does not match its published sha256"
  tar -xzf "${dir}/${name}" -C "${dir}" arduino-lint || die "arduino-lint: cannot unpack ${name}"
  mv "${dir}/arduino-lint" "${bin}"
  rm -rf "${dir}"
}

# tree_export: EXPORT = the files a commit of this work tree would hold (tracked, plus untracked
# files that are not ignored; deleted ones left out), so nothing of build/ or other ignored files:
# arduino-lint checks it (it scans every file: venv symlinks and the harness sketches under build/
# would fail LS005/LS007/LD003) and the harness installs it as the core (XEWE_CORE_SOURCE copies a
# whole folder, build/ included). The folder is named XeWeCore, so LS003 (folder name) holds.
tree_export() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ (export) git ls-files --cached --others --exclude-standard -> ${EXPORT}"
    return 0
  fi
  rm -rf "${EXPORT}"
  mkdir -p "${EXPORT}"
  git ls-files -z --cached --others --exclude-standard \
    | while IFS= read -r -d '' f; do if [[ -e "${f}" || -L "${f}" ]]; then printf '%s\0' "${f}"; fi; done \
    | tar --null -T - -cf - | tar -C "${EXPORT}" -xf -
}

# harness_copy: (re)create the harness project from HARNESS_SRC: the project without .git, build/,
# releases/, static/firmware/, its tests/ and dotenv files; tests/board of this tree as its tests/;
# [tools] ref set to TOOLS_REF when that is a tag (XEWE_TOOLS_SOURCE wins in setup.sh). --resume keeps an existing copy (its setup is green) and only
# refreshes tests/board (the tree is unchanged, or init would have refused the resume).
harness_copy() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ (copy) ${HARNESS_SRC} -> ${HARNESS} without .git build releases static/firmware tests .env*; tests/board -> ${HARNESS}/tests/board; [tools] ref = \"${TOOLS_REF}\" (a tag only)"
    return 0
  fi
  if [[ "${#RESUME_ARGS[@]}" -eq 0 || ! -f "${HARNESS}/xewe.toml" ]]; then
    rm -rf "${HARNESS}"
    mkdir -p "${HARNESS}"
    tar -C "${HARNESS_SRC}" --exclude=./.git --exclude=./build --exclude=./releases --exclude=./static/firmware \
      --exclude=./tests --exclude='./.env*' --exclude=__pycache__ -cf - . | tar -C "${HARNESS}" -xf -
    if [[ "${TOOLS_REF}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      awk -v ref="${TOOLS_REF}" '
        /^\[/ { tools = ($0 == "[tools]") }
        tools && /^ref *=/ { print "ref = \"" ref "\""; next }
        { print }' "${HARNESS}/xewe.toml" > "${HARNESS}/xewe.toml.tmp"
      mv "${HARNESS}/xewe.toml.tmp" "${HARNESS}/xewe.toml"
    fi
  fi
  rm -rf "${HARNESS}/tests"
  mkdir -p "${HARNESS}/tests"
  tar -C tests --exclude=__pycache__ -cf - board | tar -C "${HARNESS}/tests" -xf -
  # record --kind setup keeps build/config/build_config.toml of the repo root: the harness's (pins)
  mkdir -p build/config
  ln -sfn "../../${HARNESS}/build/config/build_config.toml" build/config/build_config.toml
}

# harness_path KEY: [paths] KEY of the harness's build_config.toml, absolute.
harness_path() {
  "${VENVS}/card/bin/python" - "${HARNESS}/build" "$1" <<'PY'
import sys, tomllib
from pathlib import Path
build = Path(sys.argv[1])
value = tomllib.loads((build / "config" / "build_config.toml").read_text())["paths"][sys.argv[2]]
print((build / value).resolve() if not Path(value).is_absolute() else value)
PY
}

# fqbn CHIP: the tools' FQBN for CHIP (what CI's examples job compiles with).
fqbn() {
  "${VENVS}/card/bin/python" -c 'import sys; from xewe.build.chips import get; print(get(sys.argv[1]).fqbn)' "$1"
}

notes_skeleton() {
  cat <<EOF
${NOTES_MARKER}: fill in this file, then delete this line (--prepare stops while it is here)
${TITLE} $1

What this release brings, in two or three sentences.

NEW

- ...

FIXED

- ...

TESTING

What was tested, on which tree and with which result: release_card.md, generated by
scripts/release.sh --prepare $1 and attached to this release.
EOF
}

# prepare VERSION: the 9 stages of --prepare (see the header).
prepare() {
  local v="$1" dir="releases/$1" notes="releases/$1/notes.txt" card="releases/$1/release_card.md"
  local problems loc file changed=() x py chip hw lint cli data out bin aj rc keys
  LOGS="${dir}/logs"
  STAGES=9

  stage 1 preflight
  problems="$(tree_problems "${v}")"
  if [[ -n "${problems}" ]]; then
    if [[ "${DRY_RUN}" == 1 ]]; then
      while IFS= read -r x; do fail "${x}"; done <<< "${problems}"
    else
      die "the work tree cannot be prepared:"$'\n'"${problems}"
    fi
  fi
  TOOLS_REF="$(tools_ref)"
  if [[ -z "${TOOLS_REF}" ]]; then
    fail "${CI_FILE} does not call xewe-os-tools/.github/workflows/xewe-core-tests.yml@<ref>"
    TOOLS_REF="?"
  elif [[ ! "${TOOLS_REF}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if [[ -n "${XEWE_TOOLS_SOURCE:-}" ]]; then
      warn "${CI_FILE} calls xewe-core-tests.yml@${TOOLS_REF}, not a tools tag; XEWE_TOOLS_SOURCE is used here"
    else
      fail "${CI_FILE} calls xewe-core-tests.yml@${TOOLS_REF}: pin a tools tag (X.Y.Z), so the card and CI use the same tools"
    fi
  fi
  echo "   tools: $(tools_spec) (CI: xewe-core-tests.yml@${TOOLS_REF})"
  py="$(find_python)"
  [[ -n "${py}" ]] || die "Python >= 3.11 is required (python3.12 is what CI's card job uses)"
  echo "   python: ${py}"
  for x in g++ curl tar; do command -v "${x}" >/dev/null 2>&1 || fail "${x} is required"; done
  HARNESS_SRC="${HARNESS_SRC:-${XEWE_RELEASE_HARNESS:-../xewe-os}}"
  if [[ -f "${HARNESS_SRC}/xewe.toml" && -f "${HARNESS_SRC}/setup.sh" ]]; then
    HARNESS_SRC="$(cd "${HARNESS_SRC}" && pwd)"
    echo "   harness: ${HARNESS_SRC} (copied to ${HARNESS}; modules ${BOARD_MODULES})"
  else
    fail "no xewe project at ${HARNESS_SRC} (xewe.toml and setup.sh) for the board tests: --harness <dir> or XEWE_RELEASE_HARNESS"
  fi
  # the dotenv the board run uses (the tools read it; this script only checks that it exists)
  if [[ -z "${XEWE_ENV:-}" ]]; then
    if [[ -f "${HARNESS_SRC}/.env" ]]; then
      export XEWE_ENV="${HARNESS_SRC}/.env"
    elif [[ -n "${XEWE_TOOLS_SOURCE:-}" && -f "${XEWE_TOOLS_SOURCE}/.env" ]]; then
      export XEWE_ENV="${XEWE_TOOLS_SOURCE}/.env"
    fi
  fi
  echo "   dotenv: ${XEWE_ENV:-none}"
  echo "   hardware: ${HARDWARE:-none} (other chips: compiled, not run)"
  keys="$(short_secrets | tr '\n' ' ')"
  [[ -z "${keys}" ]] || warn "secret-like variables with 4-7 character values: ${keys% }. The card redacts such a value wherever it occurs in a log, which can rewrite the host test ids, and CI then blocks the card (unset them for this run)"
  [[ "${FAILED}" -eq 0 ]] && echo "   ok: $(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)') at $(git rev-parse --short=12 HEAD)"

  stage 2 versions
  for loc in "${VERSION_LOCATIONS[@]}"; do
    file="${loc%%|*}"
    set_location "${loc}" "${v}" "" >/dev/null || die "${file}: not exactly one line matches $(cut -d'|' -f2 <<< "${loc}")"
    if ! cmp -s "${file}" <(set_location "${loc}" "${v}" ""); then
      if [[ "${DRY_RUN}" != 1 ]]; then
        set_location "${loc}" "${v}" "" > "${file}.tmp"
        cat "${file}.tmp" > "${file}" # cat keeps the file's mode
        rm -f "${file}.tmp"
      fi
      [[ " ${changed[*]-} " == *" ${file} "* ]] || changed+=("${file}")
    fi
  done
  if [[ "${#changed[@]}" -gt 0 ]]; then
    echo "   version ${v}: ${changed[*]}$([[ "${DRY_RUN}" == 1 ]] && echo ' (would change)')"
  else
    echo "   version ${v}: every location already says it"
  fi

  stage 3 "release notes"
  if [[ ! -s "${notes}" ]]; then
    echo "   create ${notes} (skeleton)"
    if [[ "${DRY_RUN}" == 1 ]]; then
      echo "   a real run stops here (exit 2) until ${notes} is filled"
    else
      mkdir -p "${dir}"
      notes_skeleton "${v}" > "${notes}"
      echo "error: fill ${notes} (the GitHub Release text, embedded in the card), delete its ${NOTES_MARKER} line, then run scripts/release.sh --prepare ${v} again" >&2
      exit 2
    fi
  elif grep -q -- "${NOTES_MARKER}" "${notes}"; then
    if [[ "${DRY_RUN}" == 1 ]]; then
      echo "   ${notes} is still the skeleton: a real run stops here (exit 2)"
    else
      echo "error: ${notes} is still the skeleton (its ${NOTES_MARKER} line): fill it, delete that line, then run scripts/release.sh --prepare ${v} again" >&2
      exit 2
    fi
  else
    echo "   ${notes}: filled ($(wc -l < "${notes}" | tr -d ' ') lines)"
  fi

  stage 4 "card run"
  card_tools "${py}"
  run "${XEWE[@]}" release-card init --dir "${LOGS}" --repo "${REPO}" --version "${v}" --tag "${v}" \
    ${RESUME_ARGS[@]+"${RESUME_ARGS[@]}"}

  stage 5 setup
  lint="${VENVS}/py/bin/python"
  step venv --kind setup --name venv -- "${py}" -m venv --clear "${VENVS}/py"
  step install --kind setup --name install -- "${lint}" -m pip install --disable-pip-version-check --progress-bar off \
    "$(tools_spec)" "${CHECKERS[@]}"
  aj="${VENVS}/ArduinoJson"
  [[ "${#RESUME_ARGS[@]}" -gt 0 && -f "${aj}/src/ArduinoJson.h" ]] || run rm -rf "${aj}"
  step arduinojson --kind setup --name arduinojson -- git -c advice.detachedHead=false clone --quiet --depth 1 \
    --branch "${ARDUINOJSON_REF}" "${ARDUINOJSON_REPO}" "${aj}"
  tree_export
  harness_copy
  # setup.sh installs the tools of [tools] (or XEWE_TOOLS_SOURCE) into the harness, the shared
  # toolchain and the modules; XEWE_CORE_SOURCE makes this tree (its export) the core
  step harness --kind setup --name harness -- env -u XEWE_PROJECT "XEWE_CORE_SOURCE=${ROOT}/${EXPORT}" XEWE_NO_BOARD=1 \
    bash "${HARNESS}/setup.sh" --modules "${BOARD_MODULES}"

  stage 6 checks
  step unit --kind unit --name host --format core-host -- env "ARDUINOJSON_SRC=${aj}/src" tests/unit/run.sh
  arduino_lint
  # on the export (see tree_export): what CI's arduino-lint job sees in its checkout
  step arduino-lint --kind validate --name "arduino-lint-${ARDUINO_LINT_VERSION}" -- "${VENVS}/bin/arduino-lint" \
    --compliance strict --library-manager update "${EXPORT}"
  step format --kind check --name format -- env "XEWE_CLANG_FORMAT=${VENVS}/py/bin/clang-format" \
    "${lint}" -m xewe --project . format --check
  step brand-lint --kind check --name brand-lint -- "${lint}" -m xewe brand-lint .

  stage 7 examples
  if [[ "${DRY_RUN}" == 1 ]]; then
    cli="<harness arduino_cli>"; data="<harness arduino_data>"
  else
    cli="$(harness_path arduino_cli 2>/dev/null)" || cli=""
    data="$(harness_path arduino_data 2>/dev/null)" || data=""
    [[ -n "${cli}" && -n "${data}" ]] || warn "no arduino-cli recorded by the harness setup (${HARNESS}/build/config/build_config.toml): the example builds fail"
  fi
  run mkdir -p "${VENVS}/arduino-user"
  for chip in "${CHIPS[@]}"; do
    if [[ "${DRY_RUN}" == 1 ]]; then x="<tools fqbn ${chip}>"; else x="$(fqbn "${chip}")"; fi
    # CI's examples job: every examples/*/*.ino, --warnings default, --library . (ArduinoJson at the CI tag)
    # shellcheck disable=SC2016 # the loop is expanded by the inner bash
    step "examples-${chip}" --kind build --chip "${chip}" --name examples -- env "ARDUINO_DIRECTORIES_DATA=${data}" \
      "ARDUINO_DIRECTORIES_USER=${VENVS}/arduino-user" ARDUINO_UPDATER_ENABLE_NOTIFICATION=false \
      bash -c 'set -euo pipefail; for ino in examples/*/*.ino; do echo "== ${ino}"; "$0" compile --fqbn "$1" --warnings default --library . --library "$2" "${ino}"; done' \
      "${cli}" "${x}" "${aj}"
  done

  stage 8 board
  out="${HARNESS}/build/tools/.venv/bin/python"
  for chip in "${CHIPS[@]}"; do
    hw=0
    [[ ",${HARDWARE}," == *",${chip},"* ]] && hw=1
    if [[ "${hw}" == 1 ]]; then
      # the image the flash step writes is the one the board step tests (up to date: reused)
      run env -u XEWE_NO_BOARD "${out}" -m xewe --project "${HARNESS}" build --chip "${chip}" --define "${BOARD_DEFINES}" || true
      bin="${HARNESS}/build/builds/${chip}/out/<image>.bin"
      if [[ "${DRY_RUN}" != 1 ]]; then
        bin="$(find "${HARNESS}/build/builds/${chip}/out" -maxdepth 1 -name "*-${chip}-*.bin" ! -name '*bootloader*' ! -name '*partitions*' 2>/dev/null | head -n 1)"
        [[ -n "${bin}" ]] || bin="${HARNESS}/build/builds/${chip}/out/missing.bin"
      fi
      step "flash-${chip}" --kind flash --chip "${chip}" --firmware "${bin}" --meta "${HARNESS}/build/builds/${chip}/out/meta.json" \
        -- env -u XEWE_NO_BOARD "${out}" -m xewe --project "${HARNESS}" flash --chip "${chip}" --no-build --require-board \
        --define "${BOARD_DEFINES}"
      step "board-${chip}" --kind board --chip "${chip}" --junit "${VENVS}/junit-board-${chip}.xml" \
        -- env -u XEWE_NO_BOARD "XEWE_HWTEST_DEFINES=${BOARD_DEFINES}" "${out}" -m xewe --project "${HARNESS}" test \
        --chip "${chip}" --require-board --define "${BOARD_DEFINES}" -- --deselect=build/modules -o junit_family=xunit1 \
        "--junitxml=${ROOT}/${VENVS}/junit-board-${chip}.xml"
    else
      step "board-${chip}" --kind board --chip "${chip}" --junit "${VENVS}/junit-board-${chip}.xml" \
        -- env XEWE_NO_BOARD=1 "XEWE_HWTEST_DEFINES=${BOARD_DEFINES}" "${out}" -m xewe --project "${HARNESS}" test \
        --chip "${chip}" --define "${BOARD_DEFINES}" -- --deselect=build/modules -o junit_family=xunit1 \
        "--junitxml=${ROOT}/${VENVS}/junit-board-${chip}.xml"
    fi
  done
  if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
    warn "failed steps: ${FAILED_STEPS[*]} (the card will refuse them)"
  fi

  stage 9 card
  rc=0
  run "${XEWE[@]}" release-card render --dir "${LOGS}" --notes "${notes}" --out "${card}" --require "${REQUIRE}" \
    --chips "$(IFS=,; echo "${CHIPS[*]}")" ${HARDWARE:+--hardware "${HARDWARE}"} --title "${TITLE}" || rc=$?
  case "${rc}" in
    0) ;;
    1) die "the card was refused (reasons above; draft: ${LOGS}/release_card.draft.md). Fix the cause, then: scripts/release.sh --prepare ${v} --resume" ;;
    *) die "xewe release-card render exited ${rc}" ;;
  esac
  if [[ "${DRY_RUN}" != 1 ]]; then
    changed=()
    while IFS= read -r file; do
      [[ -n "${file}" ]] && changed+=("${file}")
    done < <(version_files | while IFS= read -r file; do git diff --quiet HEAD -- "${file}" || echo "${file}"; done)
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "   dry run: nothing was prepared; a real run ends with:"
  else
    echo "   prepared in ${SECONDS} s; no git change was made. Review ${card}, then commit and push:"
  fi
  echo "  git add ${changed[*]+${changed[*]} }${notes} ${card} && git commit -m \"prepare ${v}\" && git push origin $(git symbolic-ref --short HEAD 2>/dev/null || echo '<branch>')"
  echo "then, once on main with the ${CI_WORKFLOW} workflow green: scripts/release.sh ${v} --dry-run; scripts/release.sh ${v}"
  if [[ "${DRY_RUN}" == 1 && "${FAILED}" -gt 0 ]]; then
    echo "== dry run: ${FAILED} check(s) failed; a real run stops at the first"
    exit 1
  fi
}

usage() { sed -n 's/^# Usage: //p' "${BASH_SOURCE[0]}"; }

main() {
  VERSION=""
  DRY_RUN=0
  SKIP_CI=0
  PREPARE=0
  RESUME_ARGS=()
  HARDWARE=""
  HARNESS_SRC=""
  CI_TIMEOUT=30
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --skip-ci) SKIP_CI=1 ;;
      --prepare) PREPARE=1 ;;
      --resume) RESUME_ARGS=(--resume) ;;
      --hardware)
        [[ "${2:-}" =~ ^(c3|c6|s3)(,(c3|c6|s3))*$ ]] || die "--hardware needs a list of c3, c6, s3 ($(usage))"
        HARDWARE="$2"
        shift
        ;;
      --harness)
        [[ -n "${2:-}" ]] || die "--harness needs a directory ($(usage))"
        HARNESS_SRC="$2"
        shift
        ;;
      --ci-timeout)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--ci-timeout needs whole minutes ($(usage))"
        CI_TIMEOUT="$2"
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      -*) die "unknown option $1 ($(usage))" ;;
      *)
        [[ -z "${VERSION}" ]] || die "one version only ($(usage))"
        VERSION="$1"
        ;;
    esac
    shift
  done
  [[ -n "${VERSION}" ]] || die "no version given ($(usage))"
  [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "version must be X.Y.Z with no 'v' (the Library Manager tags are un-prefixed): ${VERSION}"

  # Repo root: the top of the git work tree this is run in.
  command -v git >/dev/null 2>&1 || die "git is required"
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git work tree"
  # a relative --harness is taken from where the script was started
  if [[ -n "${HARNESS_SRC}" && "${HARNESS_SRC}" != /* ]]; then HARNESS_SRC="${PWD}/${HARNESS_SRC}"; fi
  cd "${ROOT}"
  grep -qx 'name=XeWeCore' library.properties 2>/dev/null || die "${ROOT} is not the xewe-os-core repo"
  [[ "${DRY_RUN}" == 1 ]] && echo "== dry run: nothing is changed; commands are printed with a leading +"
  export XEWE_NO_BOARD=1 # only a --hardware chip's flash and board steps may look for a board

  if [[ "${PREPARE}" == 1 ]]; then
    [[ "${SKIP_CI}" == 0 ]] || die "--skip-ci does not apply to --prepare"
    prepare "${VERSION}"
    return
  fi
  [[ "${#RESUME_ARGS[@]}" -eq 0 ]] || die "--resume applies to --prepare only (the tag run resumes by itself)"
  [[ -z "${HARDWARE}" && -z "${HARNESS_SRC}" ]] || die "--hardware and --harness apply to --prepare only"
  [[ "${SKIP_CI}" == 1 ]] && warn "!!!!!!!! --skip-ci: the CI gate is skipped (emergencies only) !!!!!!!!"

  stage 1 preflight
  GH_OK=0
  if ! command -v gh >/dev/null 2>&1; then
    fail "gh is not installed (https://cli.github.com)"
  elif ! gh auth status >/dev/null 2>&1; then
    fail "gh is not logged in (gh auth login)"
  else
    GH_OK=1
  fi

  run git fetch --quiet origin

  local notes="releases/${VERSION}/notes.txt" card="releases/${VERSION}/release_card.md"
  # resume: the tag exists (here or on origin) but there is no GitHub Release yet.
  local resume=0 tagged="" stale
  if tag_local "${VERSION}" || tag_remote "${VERSION}"; then
    [[ "${GH_OK}" == 1 ]] || die "tag ${VERSION} exists; gh is needed to check for its GitHub Release"
    if gh release view "${VERSION}" >/dev/null 2>&1; then
      die "${VERSION} is already released (tag and GitHub Release exist)"
    fi
    resume=1
    tagged="$(tag_commit "${VERSION}")"
    git cat-file -e "${tagged}^{commit}" 2>/dev/null \
      || die "tag ${VERSION} points at ${tagged:0:12}, which is not in this clone (git fetch --tags origin)"
    stale="$(stale_locations "${VERSION}" "${tagged}")"
    [[ -z "${stale}" ]] \
      || die "tag ${VERSION} points at ${tagged:0:12}, whose files do not say ${VERSION}:"$'\n'"${stale}"
    if ! git cat-file -e "${tagged}:${notes}" 2>/dev/null || ! git cat-file -e "${tagged}:${card}" 2>/dev/null; then
      die "tag ${VERSION} points at ${tagged:0:12}, which lacks ${notes} or ${card}"
    fi
  fi

  local head
  head="$(git rev-parse HEAD)"
  # A fresh release needs a clean main at origin's head; a resume only needs the tagged commit.
  if [[ "${resume}" == 0 ]]; then
    [[ -s "${notes}" ]] || fail "${notes} is missing (the release notes; scripts/release.sh --prepare ${VERSION})"
    [[ -s "${card}" ]] || fail "${card} is missing (the release card; scripts/release.sh --prepare ${VERSION})"
    git ls-files --error-unmatch -- "${notes}" "${card}" >/dev/null 2>&1 \
      || fail "${notes} and ${card} are not both committed (the prepare commit)"
    if [[ -s "${notes}" ]] && grep -q -- "${NOTES_MARKER}" "${notes}"; then
      fail "${notes} is still the skeleton (its ${NOTES_MARKER} line)"
    fi
    [[ ! -e "releases/${VERSION}/testcard.md" ]] \
      || fail "releases/${VERSION}/testcard.md exists: the release card replaces it; delete it"
    [[ -z "$(git status --porcelain)" ]] || fail "the working tree is not clean (git status)"
    local branch remote
    branch="$(git symbolic-ref --quiet --short HEAD || echo "(detached)")"
    [[ "${branch}" == main ]] || fail "on branch ${branch}, not main"
    remote="$(git ls-remote origin refs/heads/main | cut -f1)"
    if [[ -z "${remote}" ]]; then
      fail "origin has no main branch"
    elif [[ "${head}" != "${remote}" ]]; then
      fail "main (${head:0:12}) is not level with origin/main (${remote:0:12}): pull or push first"
    fi
    stale="$(stale_locations "${VERSION}" "")"
    [[ -z "${stale}" ]] \
      || fail "these version locations do not say ${VERSION} (scripts/release.sh --prepare ${VERSION}):"$'\n'"${stale}"
  fi
  [[ "${FAILED}" -eq 0 ]] && echo "   ok: ${VERSION} on ${head:0:12}"

  local upload_notes="${notes}"
  if [[ "${resume}" == 1 ]]; then
    echo "== resuming at stage 4: tag ${VERSION} exists (${tagged:0:12}), no GitHub Release yet"
    # the release files are those of the tagged commit, whatever is checked out now
    UPLOAD_DIR="$(mktemp -d)"
    trap 'rm -rf "${UPLOAD_DIR}"' EXIT
    git show "${tagged}:${notes}" > "${UPLOAD_DIR}/notes.txt"
    git show "${tagged}:${card}" > "${UPLOAD_DIR}/release_card.md"
    upload_notes="${UPLOAD_DIR}/notes.txt"
    card="${UPLOAD_DIR}/release_card.md"
  else
    stage 2 "release card"
    # verify is read-only: it runs in a dry run too, with the card tools of --prepare
    if [[ -x "${VENVS}/card/bin/python" ]]; then
      XEWE=("${VENVS}/card/bin/python" -m xewe)
    elif [[ "${DRY_RUN}" == 1 ]]; then
      XEWE=()
    else
      local py
      py="$(find_python)"
      [[ -n "${py}" ]] || die "Python >= 3.11 is required"
      TOOLS_REF="$(tools_ref)"
      [[ -n "${TOOLS_REF}" ]] || die "${CI_FILE} does not call xewe-core-tests.yml@<ref>"
      card_tools "${py}"
    fi
    if [[ "${#XEWE[@]}" -gt 0 ]]; then
      echo "+ ${XEWE[*]} release-card verify --card ${card}"
      "${XEWE[@]}" release-card verify --card "${card}" \
        || fail "release-card verify failed on ${card} (reasons above)"
    else
      echo "+ ${VENVS}/card/bin/python -m xewe release-card verify --card ${card}"
      echo "   (not run: no card tools in ${VENVS}/card; --prepare ${VERSION} creates them, a real run too)"
    fi

    stage 3 "CI on HEAD"
    ci_gate "${head}"
  fi

  stage 4 "tag and GitHub Release"
  if [[ "${resume}" == 0 ]]; then
    run git tag -a "${VERSION}" -m "xewe-os-core ${VERSION}" "${head}"
  fi
  tag_remote "${VERSION}" || run git push origin "refs/tags/${VERSION}"
  run gh release create "${VERSION}" --verify-tag --title "${TITLE} ${VERSION}" \
    --notes-file "${upload_notes}" "${card}"

  stage 5 "Library Manager"
  echo "The Arduino Library Manager picks up tag ${VERSION} by itself, usually within a day."
  echo "Check: ${LIBRARY_MANAGER_URL} (and the indexer logs via ${REGISTRY_URL})"
  if [[ "${DRY_RUN}" == 1 && "${FAILED}" -gt 0 ]]; then
    echo "== dry run: ${FAILED} check(s) failed; a real run stops at the first"
    exit 1
  fi
}

# Sourcing the file (tests) defines the functions without running a release.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
