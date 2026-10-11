#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
# SPDX-License-Identifier: GPL-3.0-only
# xewe-os-core/scripts/release.sh
#
# release.sh: tag and publish XeWeCore <version> from a prepared, pushed main.
# Usage: scripts/release.sh <version> [--dry-run] [--ci-timeout <min>] [--skip-ci] | --prepare <version> [--dry-run]
# A release is two steps. First `--prepare <version>` sets the version in library.properties,
# library.json and XEWE_CORE_VERSION* (src/XeWeCore/XeWeOs.h) and creates the missing skeletons
# releases/<version>/notes.txt (the GitHub Release text) and testcard.md (what was tested, attached
# to the release); no git change. Fill both, commit it all as "prepare <version>" and push. Then:
#   1 preflight: version X.Y.Z without `v`; on main, clean, level with origin/main after a fetch;
#     tag free locally and on origin; releases/<version>/ committed; every version location says
#     <version> (it lists the ones that do not); gh installed and logged in;
#   2 CI gate on HEAD: the newest run of workflow `tests` for HEAD on main must succeed (waits for
#     it to appear and finish; --ci-timeout minutes, default 30; --skip-ci for emergencies only);
#   3 local checks: tests/unit/run.sh and `xewe format --check` (when xewe is on PATH);
#   4 annotated tag <version> on HEAD (only after stage 2 passed), push it, create the Release;
#   5 print where to check the Arduino Library Manager (it picks the tag up by itself).
# Re-running resumes: a tag without a GitHub Release only gets the release (and a tag push if origin
# lacks it), provided its commit's files say <version>; tag and release both present: already
# released. --dry-run changes nothing (read-only gh and git queries still run), reports every failed
# preflight check, shows HEAD's CI state, never waits, and exits 1 if a check failed.
set -euo pipefail

LIBRARY_MANAGER_URL="https://docs.arduino.cc/libraries/xewecore/"
REGISTRY_URL="https://github.com/arduino/library-registry"
ARDUINOJSON_REPO="https://github.com/bblanchon/ArduinoJson"
ARDUINOJSON_REF="v7.4.3"
HEADER="src/XeWeCore/XeWeOs.h"
VERSION_FILES=(library.properties library.json "${HEADER}")
CI_WORKFLOW="tests"
CI_POLL="${RELEASE_CI_POLL:-15}" # seconds between CI polls

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
stage() { echo "== $1/5 $2"; }

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

# sub FILE PATTERN REPLACEMENT: sed -E "s/PATTERN/REPLACEMENT/" on FILE in place (portable, keeps
# the mode). Exactly one line must match: library.json's ArduinoJson ">=7.0.0" stays untouched.
sub() {
  local file="$1" pattern="$2" repl="$3"
  [[ "$(grep -Ec "${pattern}" "${file}")" == 1 ]] || die "${file}: expected one line matching ${pattern}"
  sed -E "s/${pattern}/${repl}/" "${file}" > "${file}.tmp"
  cat "${file}.tmp" > "${file}"
  rm -f "${file}.tmp"
}

# set_version VERSION: set VERSION in every version location, keeping each file's layout.
set_version() {
  local v="$1" major minor patch
  IFS=. read -r major minor patch <<< "${v}"
  sub library.properties '^version=.*$' "version=${v}"
  sub library.json '^(  "version": )"[^"]*"' "\\1\"${v}\""
  sub "${HEADER}" '^(#define XEWE_CORE_VERSION[[:space:]]+)"[^"]*"' "\\1\"${v}\""
  sub "${HEADER}" '^(#define XEWE_CORE_VERSION_MAJOR[[:space:]]+)[0-9]+' "\\1${major}"
  sub "${HEADER}" '^(#define XEWE_CORE_VERSION_MINOR[[:space:]]+)[0-9]+' "\\1${minor}"
  sub "${HEADER}" '^(#define XEWE_CORE_VERSION_PATCH[[:space:]]+)[0-9]+' "\\1${patch}"
}

# stale_locations VERSION REF: print "file: current line" for every version location (at REF, see
# file_at) that does not say VERSION yet, or "file: no ... line" when it is missing.
stale_locations() {
  local e="${1//./\\.}" major minor patch check file key want text
  IFS=. read -r major minor patch <<< "$1"
  for check in "library.properties|^version=|${e}\$" "library.json|^  \"version\": |\"${e}\"" \
    "${HEADER}|^#define XEWE_CORE_VERSION[[:space:]]+|\"${e}\"" \
    "${HEADER}|^#define XEWE_CORE_VERSION_MAJOR[[:space:]]+|${major}\$" \
    "${HEADER}|^#define XEWE_CORE_VERSION_MINOR[[:space:]]+|${minor}\$" \
    "${HEADER}|^#define XEWE_CORE_VERSION_PATCH[[:space:]]+|${patch}\$"; do
    IFS='|' read -r file key want <<< "${check}"
    text="$(file_at "$2" "${file}" 2>/dev/null || true)"
    grep -Eq "${key}${want}" <<< "${text}" \
      || echo "${file}: $(grep -Em1 "${key}" <<< "${text}" || echo "no ${key} line")"
  done
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

# ci_gate SHA: wait for CI_WORKFLOW on SHA and fail unless it succeeds, within CI_TIMEOUT minutes.
ci_gate() {
  local sha="$1" deadline=$((SECONDS + CI_TIMEOUT * 60)) line id status url conclusion pid
  if [[ "${SKIP_CI}" == 1 ]]; then
    warn "!!!!!!!! --skip-ci: CI on ${sha:0:12} is NOT checked; this release may ship a red build !!!!!!!!"
    return 0
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "+ gh run list --commit ${sha} --workflow ${CI_WORKFLOW} --branch main ... (poll every ${CI_POLL}s until a run appears, up to ${CI_TIMEOUT} min)"
    echo "+ gh run watch <run id> --exit-status (if not completed; fail unless success)"
    if [[ "${GH_OK}" == 1 && "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
      line="$(ci_run "${sha}" 2>/dev/null)" || line="(gh run list failed)"
      echo "   current CI state of ${sha:0:12}: ${line:-no ${CI_WORKFLOW} run yet}"
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
  echo "   CI passed: ${url}"
}

# prepare VERSION: set every version location and create the releases/VERSION/ skeletons.
prepare() {
  local v="$1" dir="releases/$1" changed
  changed="$(stale_locations "${v}" "" | cut -d: -f1 | uniq | tr '\n' ' ')"
  if [[ -n "${changed}" ]]; then
    [[ "${DRY_RUN}" == 1 ]] || set_version "${v}"
    echo "version ${v}: ${changed% }"
  else
    echo "version ${v}: every location already says it"
  fi
  if [[ ! -s "${dir}/notes.txt" ]]; then
    echo "create ${dir}/notes.txt (skeleton: fill it in)"
    [[ "${DRY_RUN}" == 1 ]] || { mkdir -p "${dir}"; printf '%s\n' "XeWeCore ${v}" "" \
      "What this release brings, in two or three sentences." "" NEW "" "- ..." "" FIXED "" "- ..." > "${dir}/notes.txt"; }
  fi
  if [[ ! -s "${dir}/testcard.md" ]]; then
    echo "create ${dir}/testcard.md (skeleton: fill it in)"
    [[ "${DRY_RUN}" == 1 ]] || { mkdir -p "${dir}"; printf '%s\n' "# XeWeCore ${v} test card" "" \
      "What was tested, where, on which commits, and what was not." "" \
      "| Component (src) | Host unit tests | Board tests | Not covered |" "|---|---|---|---|" > "${dir}/testcard.md"; }
  fi
  echo "no git change was made. Review, fill releases/${v}/, then commit and push:"
  echo "  git add ${VERSION_FILES[*]} ${dir} && git commit -m \"prepare ${v}\" && git push origin main"
  echo "then: scripts/release.sh ${v} --dry-run; scripts/release.sh ${v}"
}

usage() { sed -n 's/^# Usage: //p' "${BASH_SOURCE[0]}"; }

main() {
  VERSION=""
  DRY_RUN=0
  SKIP_CI=0
  PREPARE=0
  CI_TIMEOUT=30
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --skip-ci) SKIP_CI=1 ;;
      --prepare) PREPARE=1 ;;
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
  cd "${ROOT}"
  grep -qx 'name=XeWeCore' library.properties 2>/dev/null || die "${ROOT} is not the xewe-os-core repo"
  [[ "${DRY_RUN}" == 1 ]] && echo "== dry run: nothing is changed; commands are printed with a leading +"

  if [[ "${PREPARE}" == 1 ]]; then
    [[ "${SKIP_CI}" == 0 ]] || die "--skip-ci does not apply to --prepare"
    prepare "${VERSION}"
    return
  fi
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
  fi

  local notes="releases/${VERSION}/notes.txt" card="releases/${VERSION}/testcard.md"
  [[ -s "${notes}" ]] || fail "${notes} is missing (the release notes; scripts/release.sh --prepare ${VERSION})"
  [[ -s "${card}" ]] || fail "${card} is missing (the test card; scripts/release.sh --prepare ${VERSION})"
  git ls-files --error-unmatch -- "${notes}" "${card}" >/dev/null 2>&1 \
    || fail "releases/${VERSION}/ is not committed"
  local head
  head="$(git rev-parse HEAD)"
  # A fresh release needs a clean main at origin's head; a resume only needs the tagged commit.
  if [[ "${resume}" == 0 ]]; then
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
  if [[ "${FAILED}" -gt 0 ]]; then
    echo "== dry run: ${FAILED} preflight check(s) failed; a real run stops at the first"
  else
    echo "   ok: ${VERSION} on ${head:0:12}"
  fi

  if [[ "${resume}" == 1 ]]; then
    echo "== resuming at stage 4: tag ${VERSION} exists (${tagged:0:12}), no GitHub Release yet"
  else
    stage 2 "CI on HEAD"
    ci_gate "${head}"

    stage 3 "local checks"
    if [[ -z "${ARDUINOJSON_SRC:-}" ]]; then
      TMP_DIR="<tmp dir>"
      [[ "${DRY_RUN}" == 1 ]] || { TMP_DIR="$(mktemp -d)"; trap 'rm -rf "${TMP_DIR}"' EXIT; }
      run git clone --quiet --depth 1 --branch "${ARDUINOJSON_REF}" "${ARDUINOJSON_REPO}" "${TMP_DIR}/ArduinoJson"
      ARDUINOJSON_SRC="${TMP_DIR}/ArduinoJson/src"
    fi
    run env ARDUINOJSON_SRC="${ARDUINOJSON_SRC}" tests/unit/run.sh
    if command -v xewe >/dev/null 2>&1; then
      run xewe --project . format --check
    else
      warn "xewe is not on PATH: format check skipped (CI runs it)"
    fi
  fi

  stage 4 "tag and GitHub Release"
  if [[ "${resume}" == 0 ]]; then
    run git tag -a "${VERSION}" -m "xewe-os-core ${VERSION}" "${head}"
  fi
  tag_remote "${VERSION}" || run git push origin "refs/tags/${VERSION}"
  run gh release create "${VERSION}" --verify-tag --title "XeWeCore ${VERSION}" --notes-file "${notes}" \
    "${card}#XeWeCore ${VERSION} test card"

  stage 5 "Library Manager"
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
