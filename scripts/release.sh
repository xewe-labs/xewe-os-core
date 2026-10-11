#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
# SPDX-License-Identifier: GPL-3.0-only
# xewe-os-core/scripts/release.sh
#
# release.sh: release XeWeCore <version> from a clean, pushed main.
# Usage: scripts/release.sh <version> [--dry-run]   (e.g. scripts/release.sh 3.0.0)
# Each release has a folder releases/<version>/ with notes.txt (the GitHub Release text) and
# testcard.md (what was tested, attached to the release). Commit that folder before releasing: the
# clean-tree check covers it, and the release commit holds only the version bump.
# Preflight (version X.Y.Z without `v` and above library.properties, releases/<version>/ files,
# clean tree, main level with origin/main, tag free locally and on origin, gh logged in), then
# tests/unit/run.sh and `xewe format --check`. Then it sets the version in library.properties,
# library.json and XEWE_CORE_VERSION* (src/XeWeCore/XeWeOs.h), commits "release <version>", tags
# <version> (annotated), pushes main and the tag, and creates the GitHub Release. The Arduino
# Library Manager picks the tag up by itself.
# --dry-run prints every command and changes nothing; it reports every failed preflight check, not
# only the first, and exits 1 if there was one.
set -euo pipefail

LIBRARY_MANAGER_URL="https://docs.arduino.cc/libraries/xewecore/"
REGISTRY_URL="https://github.com/arduino/library-registry"
ARDUINOJSON_REPO="https://github.com/bblanchon/ArduinoJson"
ARDUINOJSON_REF="v7.4.3"
HEADER="src/XeWeCore/XeWeOs.h"

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }

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

# ver_gt A B: true when version A > B (both X.Y.Z).
ver_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  a1=$((10#${a1})) a2=$((10#${a2})) a3=$((10#${a3})) b1=$((10#${b1})) b2=$((10#${b2})) b3=$((10#${b3}))
  if (( a1 != b1 )); then (( a1 > b1 )); return; fi
  if (( a2 != b2 )); then (( a2 > b2 )); return; fi
  (( a3 > b3 ))
}

# sub FILE PATTERN REPLACEMENT: sed -E "s/PATTERN/REPLACEMENT/" on FILE in place (portable: no
# sed -i; the file keeps its mode). Exactly one line must match.
sub() {
  local file="$1" pattern="$2" repl="$3"
  [[ "$(grep -Ec "${pattern}" "${file}")" == 1 ]] || die "${file}: expected one line matching ${pattern}"
  sed -E "s/${pattern}/${repl}/" "${file}" > "${file}.tmp"
  cat "${file}.tmp" > "${file}"
  rm -f "${file}.tmp"
}

# bump_version VERSION DIR: set VERSION in DIR's library.properties, library.json (the top-level
# "version", not the dependency's) and the header, keeping each file's layout.
bump_version() {
  local v="$1" dir="$2" major minor patch
  IFS=. read -r major minor patch <<< "${v}"
  sub "${dir}/library.properties" '^version=.*$' "version=${v}"
  sub "${dir}/library.json" '^(  "version": )"[^"]*"' "\\1\"${v}\""
  sub "${dir}/${HEADER}" '^(#define XEWE_CORE_VERSION[[:space:]]+)"[^"]*"' "\\1\"${v}\""
  sub "${dir}/${HEADER}" '^(#define XEWE_CORE_VERSION_MAJOR[[:space:]]+)[0-9]+' "\\1${major}"
  sub "${dir}/${HEADER}" '^(#define XEWE_CORE_VERSION_MINOR[[:space:]]+)[0-9]+' "\\1${minor}"
  sub "${dir}/${HEADER}" '^(#define XEWE_CORE_VERSION_PATCH[[:space:]]+)[0-9]+' "\\1${patch}"
}

usage() { sed -n 's/^# Usage: //p' "${BASH_SOURCE[0]}"; }

main() {
  VERSION=""
  DRY_RUN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
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
  cd "${ROOT}"
  grep -qx 'name=XeWeCore' library.properties 2>/dev/null || die "${ROOT} is not the xewe-os-core repo"
  [[ "${DRY_RUN}" == 1 ]] && echo "== dry run: nothing is changed; commands are printed with a leading +"

  echo "== preflight"
  local current
  current="$(sed -n 's/^version=//p' library.properties)"
  [[ "${current}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "library.properties has no X.Y.Z version: '${current}'"
  echo "   library.properties version: ${current}"

  if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
    fail "tag ${VERSION} already exists locally"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${VERSION}" >/dev/null 2>&1; then
    fail "tag ${VERSION} already exists on origin"
  fi
  ver_gt "${VERSION}" "${current}" || fail "${VERSION} is not above the current version ${current}"
  local notes="releases/${VERSION}/notes.txt" card="releases/${VERSION}/testcard.md"
  [[ -s "${notes}" ]] || fail "${notes} is missing (the release notes)"
  [[ -s "${card}" ]] || fail "${card} is missing (the test card)"

  [[ -z "$(git status --porcelain)" ]] || fail "the working tree is not clean (git status)"
  local branch
  branch="$(git symbolic-ref --quiet --short HEAD || echo "(detached)")"
  [[ "${branch}" == main ]] || fail "on branch ${branch}, not main"
  run git fetch --quiet origin
  local head remote
  head="$(git rev-parse HEAD)"
  remote="$(git ls-remote origin refs/heads/main | cut -f1)"
  [[ -n "${remote}" ]] || fail "origin has no main branch"
  [[ "${head}" == "${remote}" ]] || fail "main (${head:0:12}) is not level with origin/main (${remote:0:12})"

  if ! command -v gh >/dev/null 2>&1; then
    fail "gh is not installed (https://cli.github.com)"
  elif ! gh auth status >/dev/null 2>&1; then
    fail "gh is not logged in (gh auth login)"
  fi
  if [[ "${FAILED}" -gt 0 ]]; then
    echo "== dry run: ${FAILED} preflight check(s) failed; a real run stops at the first"
  else
    echo "   ok"
  fi

  echo "== checks"
  if [[ -z "${ARDUINOJSON_SRC:-}" ]]; then
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT
    run git clone --quiet --depth 1 --branch "${ARDUINOJSON_REF}" "${ARDUINOJSON_REPO}" "${TMP_DIR}/ArduinoJson"
    ARDUINOJSON_SRC="${TMP_DIR}/ArduinoJson/src"
  fi
  run env ARDUINOJSON_SRC="${ARDUINOJSON_SRC}" tests/unit/run.sh
  if command -v xewe >/dev/null 2>&1; then
    run xewe --project . format --check
  else
    warn "xewe is not on PATH: format check skipped (CI runs it)"
  fi

  echo "== release ${VERSION}"
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ set version ${current} -> ${VERSION} in library.properties, library.json and ${HEADER} (XEWE_CORE_VERSION*)"
  else
    bump_version "${VERSION}" .
  fi
  run git add library.properties library.json "${HEADER}"
  run git commit --quiet -m "release ${VERSION}"
  run git tag -a "${VERSION}" -m "xewe-os-core ${VERSION}"
  run git push origin main
  run git push origin "refs/tags/${VERSION}"
  run gh release create "${VERSION}" --verify-tag --title "XeWeCore ${VERSION}" --notes-file "${notes}" \
    "${card}#XeWeCore ${VERSION} test card"

  echo
  echo "The Arduino Library Manager picks up tag ${VERSION} by itself, usually within a day."
  echo "Check: ${LIBRARY_MANAGER_URL} (and the indexer logs via ${REGISTRY_URL})"
  if [[ "${DRY_RUN}" == 1 && "${FAILED}" -gt 0 ]]; then
    exit 1
  fi
}

# Sourcing the file (tests) defines the functions without running a release.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
