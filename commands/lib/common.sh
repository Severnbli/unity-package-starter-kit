# shellcheck shell=bash
# Helpers shared by the .sh scripts in commands/. Source it:
#   . "$(dirname "$0")/lib/common.sh"
#
# Works with the bash 3.2 and BSD tools that ship with macOS as well as with Linux.
# Placeholder and version edits use perl, which both platforms provide.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNITY_TESTS_DIR="$REPO_ROOT/Unity-Tests"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
export LC_ALL=C

# Unity editor version, e.g. "2022.3.62f3" or "6000.3.1f1".
UNITY_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+[abfpx][0-9]+$'

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_GRAY=$'\033[90m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_GRAY=''; C_RESET=''
fi

say() { printf '%s%s%s\n' "$2" "$1" "$C_RESET"; }
warn() { printf '%sWARNING: %s%s\n' "$C_YELLOW" "$1" "$C_RESET" >&2; }
die() { printf '%serror: %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found."
}

is_unity_version() {
  [[ "$1" =~ $UNITY_VERSION_RE ]]
}

# Sort key that orders versions numerically: 2022.3.9f1 < 2022.3.62f3 < 6000.0.1a1.
unity_version_key() {
  is_unity_version "$1" || die "Not a Unity version: '$1' (expected e.g. 2022.3.62f3)"
  local major minor patch type build
  read -r major minor patch type build <<EOF
$(printf '%s' "$1" | sed -E 's/^([0-9]+)\.([0-9]+)\.([0-9]+)([a-z])([0-9]+)$/\1 \2 \3 \4 \5/')
EOF
  printf '%06d.%04d.%04d.%s.%04d\n' "$((10#$major))" "$((10#$minor))" "$((10#$patch))" "$type" "$((10#$build))"
}

# Editor version a project was saved with, or nothing.
project_unity_version() {
  local file="$1/ProjectSettings/ProjectVersion.txt"
  [ -f "$file" ] || return 0
  sed -n 's/^m_EditorVersion:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$file" | tr -d '\r' | head -n 1
}

# Test projects: every Unity-Tests/<version> folder with a ProjectVersion.txt, one per line, sorted by version.
unity_test_projects() {
  [ -d "$UNITY_TESTS_DIR" ] || return 0
  local dir name
  for dir in "$UNITY_TESTS_DIR"/*/; do
    [ -f "${dir}ProjectSettings/ProjectVersion.txt" ] || continue
    name="$(basename "$dir")"
    is_unity_version "$name" || die "Unity-Tests/$name is not named after a Unity version (e.g. 2022.3.62f3)."
    printf '%s %s\n' "$(unity_version_key "$name")" "$name"
  done | sort | cut -d' ' -f2
}

# test.yml before init is test.yml-sample; both carry the plugin test matrix.
test_workflow_path() {
  local name
  for name in test.yml test.yml-sample; do
    if [ -f "$WORKFLOWS_DIR/$name" ]; then
      printf '%s\n' "$WORKFLOWS_DIR/$name"
      return 0
    fi
  done
}

# The plugin matrix line: "unityVersion: [2022.3.62f3, 6000.3.1f1]".
MATRIX_RE='^[[:space:]]*unityVersion:[[:space:]]*\['

# Versions in the workflow matrix, one per line.
workflow_unity_versions() {
  local count
  count="$(grep -cE "$MATRIX_RE" "$1" || true)"
  [ "$count" = "1" ] || die "Expected exactly one 'unityVersion: [...]' matrix in $1, found $count."
  grep -E "$MATRIX_RE" "$1" | sed -E 's/^[^[]*\[([^]]*)\].*/\1/' | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$' || true
}

# Rewrites the matrix to the given versions (arguments). Returns 0 when the file changed.
set_workflow_unity_versions() {
  local workflow="$1"; shift
  workflow_unity_versions "$workflow" >/dev/null
  local list="" version
  for version in "$@"; do
    list="${list:+$list, }$version"
  done
  local tmp
  tmp="$(mktemp)"
  MATRIX_LIST="$list" perl -pe 's/^(\s*unityVersion:\s*)\[[^\]]*\]/$1\[$ENV{MATRIX_LIST}\]/' "$workflow" >"$tmp"
  if cmp -s "$tmp" "$workflow"; then
    rm -f "$tmp"
    return 1
  fi
  # Overwrite in place to keep the file's permissions.
  cat "$tmp" >"$workflow"
  rm -f "$tmp"
  return 0
}

# Files git would consider part of the repository: tracked plus untracked but not ignored.
# One path per line, relative to the repository root.
repository_files() {
  git -C "$REPO_ROOT" -c core.quotePath=false ls-files --cached --others --exclude-standard -- "$@" | sort -u
}

# Path relative to the repository root.
relative_path() {
  printf '%s\n' "${1#"$REPO_ROOT"/}"
}

require git
require perl
