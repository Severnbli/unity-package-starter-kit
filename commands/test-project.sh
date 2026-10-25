#!/usr/bin/env bash
#
# Adds or removes a Unity test project and keeps the test workflow in sync (macOS and
# Linux; on Windows use test-project.ps1).
#
# Test projects live in Unity-Tests/<unity-version> and reference the package as a local,
# testable dependency. The test workflow runs the package tests on every one of them, so
# its matrix ("unityVersion: [...]" in .github/workflows/test.yml, or test.yml-sample
# before init) is rewritten to match the folders after every change.
#
# --add copies the closest existing project (preferring the same major version) and
# points it at the new editor version. Unity upgrades the project settings the first
# time the project is opened.
#
# Usage:
#   ./commands/test-project.sh --list
#   ./commands/test-project.sh --add 2023.2.22f1 [--from 2022.3.62f3]
#   ./commands/test-project.sh --remove 2022.3.62f3
#   ./commands/test-project.sh --sync      # only rewrite the workflow matrix

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

ACTION="list"
VERSION=""
FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --add) ACTION="add"; VERSION="${2:-}"; shift 2 ;;
    --remove) ACTION="remove"; VERSION="${2:-}"; shift 2 ;;
    --from) FROM="${2:-}"; shift 2 ;;
    --sync) ACTION="sync"; shift ;;
    --list) ACTION="list"; shift ;;
    -h | --help) usage 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage 1 ;;
  esac
done

show_projects() {
  say "Test projects (Unity-Tests/):" "$C_CYAN"
  unity_test_projects | sed 's/^/  /'
  local workflow
  workflow="$(test_workflow_path)"
  [ -n "$workflow" ] || return 0
  local matrix projects
  matrix="$(workflow_unity_versions "$workflow" | tr '\n' ',' | sed 's/,$//')"
  projects="$(unity_test_projects | tr '\n' ',' | sed 's/,$//')"
  say "Tested by $(relative_path "$workflow"): ${matrix//,/, }" "$C_CYAN"
  [ "$matrix" = "$projects" ] || warn "The workflow is out of sync. Run ./commands/test-project.sh --sync"
}

sync_workflow() {
  local workflow
  workflow="$(test_workflow_path)"
  if [ -z "$workflow" ]; then
    warn "No .github/workflows/test.yml or test.yml-sample found; nothing to update."
    return 0
  fi
  local projects=()
  local project
  while IFS= read -r project; do
    projects+=("$project")
  done < <(unity_test_projects)
  [ "${#projects[@]}" -gt 0 ] || die "Unity-Tests/ has no projects; the workflow matrix cannot be empty."
  if set_workflow_unity_versions "$workflow" "${projects[@]}"; then
    local list
    list="$(printf '%s, ' "${projects[@]}")"
    say "Updated $(relative_path "$workflow"): unityVersion: [${list%, }]" "$C_GREEN"
  else
    say "$(relative_path "$workflow") is already up to date." "$C_GRAY"
  fi
}

# The existing project closest to $1: same major version first, then the nearest one.
# Highest version below the new one, otherwise the lowest one above it.
closest_project() {
  local version="$1" major key candidates
  major="${version%%.*}"
  candidates="$(unity_test_projects | grep "^$major\." || true)"
  [ -n "$candidates" ] || candidates="$(unity_test_projects)"
  key="$(unity_version_key "$version")"
  local below="" first="" candidate
  while IFS= read -r candidate; do
    [ -n "$first" ] || first="$candidate"
    [[ "$(unity_version_key "$candidate")" < "$key" ]] && below="$candidate"
  done <<<"$candidates"
  printf '%s\n' "${below:-$first}"
}

case "$ACTION" in
  add)
    is_unity_version "$VERSION" || die "Invalid Unity version '$VERSION' (expected e.g. 2023.2.22f1)."
    target="$UNITY_TESTS_DIR/$VERSION"
    [ ! -e "$target" ] || die "Unity-Tests/$VERSION already exists."
    existing="$(unity_test_projects)"
    if [ -z "$FROM" ]; then
      [ -n "$existing" ] || die "Unity-Tests/ has no project to copy. Pass --from or create one in Unity Hub."
      FROM="$(closest_project "$VERSION")"
    elif ! printf '%s\n' "$existing" | grep -qxF "$FROM"; then
      die "Unity-Tests/$FROM does not exist. Existing projects: $(printf '%s' "$existing" | tr '\n' ' ')"
    fi

    # Copy only what belongs in the repository, never Library/, Temp/ or other generated folders.
    say "Creating Unity-Tests/$VERSION from Unity-Tests/$FROM..." "$C_YELLOW"
    prefix="Unity-Tests/$FROM/"
    while IFS= read -r file; do
      [ -e "$REPO_ROOT/$file" ] || continue
      relative="${file#"$prefix"}"
      # The lock file pins package versions of the source editor; Unity writes a new one.
      [ "$relative" != "Packages/packages-lock.json" ] || continue
      mkdir -p "$(dirname "$target/$relative")"
      cp -p "$REPO_ROOT/$file" "$target/$relative"
    done < <(repository_files "Unity-Tests/$FROM")

    # Point the project at the new editor. The revision is unknown here; Unity writes it on first open.
    printf 'm_EditorVersion: %s\n' "$VERSION" >"$target/ProjectSettings/ProjectVersion.txt"

    # Product name and bundle identifier are named after the version.
    settings="$target/ProjectSettings/ProjectSettings.asset"
    if [ -f "$settings" ]; then
      tmp="$(mktemp)"
      OLD="$FROM" NEW="$VERSION" perl -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$settings" >"$tmp"
      cat "$tmp" >"$settings"
      rm -f "$tmp"
    fi

    sync_workflow
    say "Done. Open Unity-Tests/$VERSION in Unity $VERSION once and commit the upgraded project." "$C_GREEN"
    if [ "${FROM%%.*}" != "${VERSION%%.*}" ]; then
      warn "Unity-Tests/$VERSION was copied from a different major version ($FROM). Check Packages/manifest.json for packages that do not exist in Unity $VERSION."
    fi
    ;;
  remove)
    [ -n "$VERSION" ] || usage 1
    target="$UNITY_TESTS_DIR/$VERSION"
    [ -d "$target" ] || die "Unity-Tests/$VERSION does not exist. Existing projects: $(unity_test_projects | tr '\n' ' ')"
    others="$(unity_test_projects | grep -vxF "$VERSION" || true)"
    [ -n "$others" ] || die "Unity-Tests/$VERSION is the last test project. Add another one first: the workflow matrix cannot be empty."
    say "Removing Unity-Tests/$VERSION..." "$C_YELLOW"
    rm -rf "$target"
    sync_workflow
    say "Done." "$C_GREEN"
    ;;
  sync)
    sync_workflow
    ;;
  list)
    show_projects
    ;;
esac
