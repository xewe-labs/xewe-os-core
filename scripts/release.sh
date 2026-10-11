#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
# SPDX-License-Identifier: GPL-3.0-only
# xewe-os-core/scripts/release.sh
#
# release.sh: release XeWeCore <version>, start to finish, with one command.
# Usage: scripts/release.sh <version> [--dry-run] [--ci-timeout <min>] [--skip-ci]   (e.g. scripts/release.sh 3.0.0)
# Each release has a folder releases/<version>/ with notes.txt (the GitHub Release text) and
# testcard.md (what was tested, attached to the release). Commit that folder before releasing: the
# clean-tree check covers it, and the release commit holds only the version bump.
# Stages:
#   1 preflight: version X.Y.Z without `v` and above library.properties, releases/<version>/ files
#     committed, clean tree, main level with origin/main after a fetch, tag free locally and on
#     origin, gh installed and logged in;
#   2 CI gate on HEAD: the newest run of workflow `tests` for HEAD on main must succeed (waits for
#     it to appear and finish; --ci-timeout minutes, default 30);
#   3 local checks: tests/unit/run.sh and `xewe format --check` (when xewe is on PATH);
#   4 set the version in library.properties, library.json and XEWE_CORE_VERSION*
#     (src/XeWeCore/XeWeOs.h), commit "release <version>", push main;
#   5 CI gate on the release commit, as in 2;
#   6 annotated tag <version> on the release commit, push it, create the GitHub Release;
#   7 print where to check the Arduino Library Manager (it picks the tag up by itself).
# A tag is only made after stage 5 passed. Re-running resumes: HEAD "release <version>" with the
# files at <version> and no tag resumes at stage 5; a tag without a GitHub Release resumes at
# stage 6. --skip-ci skips both CI gates (emergencies only).
# --dry-run prints every command and changes nothing; it reports every failed preflight check, not
# only the first, shows HEAD's CI state (read-only), never waits, and exits 1 if a check failed.
set -euo pipefail

LIBRARY_MANAGER_URL="https://docs.arduino.cc/libraries/xewecore/"
REGISTRY_URL="https://github.com/arduino/library-registry"
ARDUINOJSON_REPO="https://github.com/bblanchon/ArduinoJson"
ARDUINOJSON_REF="v7.4.3"
HEADER="src/XeWeCore/XeWeOs.h"
CI_WORKFLOW="tests"
CI_POLL="${RELEASE_CI_POLL:-15}" # seconds between CI polls

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
stage() { echo "== $1/7 $2"; }

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

# files_say VERSION DIR: true when DIR's three version files already hold VERSION.
files_say() {
  local v="$1" dir="$2"
  grep -qx "version=${v}" "${dir}/library.properties" \
    && grep -Eq "^  \"version\": \"${v}\"" "${dir}/library.json" \
    && grep -Eq "^#define XEWE_CORE_VERSION[[:space:]]+\"${v}\"" "${dir}/${HEADER}"
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

# detect_resume VERSION: prints where a release of VERSION stands, in the current repo:
#   new     - nothing done yet;
#   ci      - HEAD is "release VERSION", the files say VERSION, no tag: resume at stage 5;
#   release - the tag exists but there is no GitHub Release: resume at stage 6;
#   done    - tag and GitHub Release both exist.
detect_resume() {
  local v="$1"
  if tag_local "${v}" || tag_remote "${v}"; then
    if gh release view "${v}" >/dev/null 2>&1; then echo "done"; else echo release; fi
  elif [[ "$(git log -1 --format=%s)" == "release ${v}" ]] && files_say "${v}" .; then
    echo ci
  else
    echo new
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

usage() { sed -n 's/^# Usage: //p' "${BASH_SOURCE[0]}"; }

main() {
  VERSION=""
  DRY_RUN=0
  SKIP_CI=0
  CI_TIMEOUT=30
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --skip-ci) SKIP_CI=1 ;;
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
  [[ "${SKIP_CI}" == 1 ]] && warn "!!!!!!!! --skip-ci: both CI gates are skipped (emergencies only) !!!!!!!!"

  stage 1 preflight
  local current
  current="$(sed -n 's/^version=//p' library.properties)"
  [[ "${current}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "library.properties has no X.Y.Z version: '${current}'"
  echo "   library.properties version: ${current}"

  GH_OK=0
  if ! command -v gh >/dev/null 2>&1; then
    fail "gh is not installed (https://cli.github.com)"
  elif ! gh auth status >/dev/null 2>&1; then
    fail "gh is not logged in (gh auth login)"
  else
    GH_OK=1
  fi
  run git fetch --quiet origin

  local mode
  mode="$(detect_resume "${VERSION}")"
  case "${mode}" in
    done) die "${VERSION} is already released (tag and GitHub Release exist)" ;;
    release)
      [[ "$(git log -1 --format=%s "$(tag_commit "${VERSION}")" 2>/dev/null)" == "release ${VERSION}" ]] \
        || die "tag ${VERSION} already exists and does not point at a 'release ${VERSION}' commit"
      ;;
    new) ver_gt "${VERSION}" "${current}" || fail "${VERSION} is not above the current version ${current}" ;;
  esac

  local notes="releases/${VERSION}/notes.txt" card="releases/${VERSION}/testcard.md"
  [[ -s "${notes}" ]] || fail "${notes} is missing (the release notes)"
  [[ -s "${card}" ]] || fail "${card} is missing (the test card)"
  git ls-files --error-unmatch -- "${notes}" "${card}" >/dev/null 2>&1 \
    || fail "releases/${VERSION}/ is not committed"
  [[ -z "$(git status --porcelain)" ]] || fail "the working tree is not clean (git status)"
  local branch
  branch="$(git symbolic-ref --quiet --short HEAD || echo "(detached)")"
  [[ "${branch}" == main ]] || fail "on branch ${branch}, not main"
  local head remote push_main=0
  head="$(git rev-parse HEAD)"
  remote="$(git ls-remote origin refs/heads/main | cut -f1)"
  [[ -n "${remote}" ]] || fail "origin has no main branch"
  if [[ "${head}" != "${remote}" ]]; then
    # A release commit whose push failed is pushed again by the resume.
    if [[ "${mode}" == ci && "$(git rev-parse -q --verify HEAD^ || true)" == "${remote}" ]]; then
      push_main=1
    else
      fail "main (${head:0:12}) is not level with origin/main (${remote:0:12})"
    fi
  fi
  if [[ "${FAILED}" -gt 0 ]]; then
    echo "== dry run: ${FAILED} preflight check(s) failed; a real run stops at the first"
  else
    echo "   ok"
  fi

  local release_sha="<release commit>"
  case "${mode}" in
    ci)
      release_sha="${head}"
      echo "== resuming at stage 5: HEAD ${head:0:12} is 'release ${VERSION}', no tag yet"
      ;;
    release)
      release_sha="$(tag_commit "${VERSION}")"
      echo "== resuming at stage 6: tag ${VERSION} exists (${release_sha:0:12}), no GitHub Release yet"
      ;;
  esac

  if [[ "${mode}" == new ]]; then
    stage 2 "CI on HEAD"
    ci_gate "${head}"

    stage 3 "local checks"
    if [[ -z "${ARDUINOJSON_SRC:-}" ]]; then
      TMP_DIR="<tmp dir>"
      if [[ "${DRY_RUN}" != 1 ]]; then
        TMP_DIR="$(mktemp -d)"
        trap 'rm -rf "${TMP_DIR}"' EXIT
      fi
      run git clone --quiet --depth 1 --branch "${ARDUINOJSON_REF}" "${ARDUINOJSON_REPO}" "${TMP_DIR}/ArduinoJson"
      ARDUINOJSON_SRC="${TMP_DIR}/ArduinoJson/src"
    fi
    run env ARDUINOJSON_SRC="${ARDUINOJSON_SRC}" tests/unit/run.sh
    if command -v xewe >/dev/null 2>&1; then
      run xewe --project . format --check
    else
      warn "xewe is not on PATH: format check skipped (CI runs it)"
    fi

    stage 4 "release commit ${VERSION}"
    if [[ "${DRY_RUN}" == 1 ]]; then
      echo "+ set version ${current} -> ${VERSION} in library.properties, library.json and ${HEADER} (XEWE_CORE_VERSION*)"
    else
      bump_version "${VERSION}" .
    fi
    run git add library.properties library.json "${HEADER}"
    run git commit --quiet -m "release ${VERSION}"
    [[ "${DRY_RUN}" == 1 ]] || release_sha="$(git rev-parse HEAD)"
    run git push origin main
  fi

  if [[ "${mode}" != release ]]; then
    stage 5 "CI on the release commit"
    [[ "${push_main}" == 1 ]] && run git push origin main
    ci_gate "${release_sha}"
  fi

  stage 6 "tag and GitHub Release"
  if ! tag_local "${VERSION}" && ! tag_remote "${VERSION}"; then
    run git tag -a "${VERSION}" -m "xewe-os-core ${VERSION}" "${release_sha}"
  fi
  tag_remote "${VERSION}" || run git push origin "refs/tags/${VERSION}"
  run gh release create "${VERSION}" --verify-tag --title "XeWeCore ${VERSION}" --notes-file "${notes}" \
    "${card}#XeWeCore ${VERSION} test card"

  stage 7 "Library Manager"
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
