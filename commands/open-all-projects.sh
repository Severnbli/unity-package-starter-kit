#!/usr/bin/env bash
#
# Opens all Unity projects in the repository using Unity Editor (macOS and Linux; on
# Windows use open-all-projects.ps1).
#
# Launches the Unity Editor of each project, reading the required version from
# ProjectSettings/ProjectVersion.txt:
#   - Installer
#   - Unity-Package
#   - with --with-tests, also every project in Unity-Tests/
# Editors are looked up in the Unity Hub install folders of the current platform,
# including a custom install location configured in Unity Hub.
#
# Usage:
#   ./commands/open-all-projects.sh
#   ./commands/open-all-projects.sh --with-tests
#   ./commands/open-all-projects.sh --editors-path /custom/path/to/editors
#   ./commands/open-all-projects.sh --what-if Unity-Package    # print, do not open
#
# Run in a terminal without options, the script lists every project with its editor
# version and lets you tick the ones to open.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

EDITORS_PATH=""
WHAT_IF=false
WITH_TESTS=false
PROJECTS=()
ASK=false
[ $# -eq 0 ] && ui_enabled && ASK=true
while [ $# -gt 0 ]; do
  case "$1" in
    --editors-path) EDITORS_PATH="${2:-}"; shift 2 ;;
    --what-if | -n) WHAT_IF=true; shift ;;
    --with-tests | -t) WITH_TESTS=true; shift ;;
    -h | --help) usage 0 ;;
    -*) printf 'Unknown option: %s\n\n' "$1" >&2; usage 1 ;;
    *) PROJECTS+=("$1"); shift ;;
  esac
done

IS_MACOS=false
[ "$(uname -s)" = "Darwin" ] && IS_MACOS=true

# Unity Hub stores a custom install location in secondaryInstallPath.json (a JSON string).
hub_custom_path() {
  local config
  if [ "$IS_MACOS" = true ]; then
    config="$HOME/Library/Application Support/UnityHub/secondaryInstallPath.json"
  else
    config="${XDG_CONFIG_HOME:-$HOME/.config}/UnityHub/secondaryInstallPath.json"
  fi
  [ -f "$config" ] || return 0
  sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' -e 's#\\/#/#g' "$config" | head -n 1
}

editor_roots() {
  local roots=() root custom
  [ -z "$EDITORS_PATH" ] || roots+=("$EDITORS_PATH")
  custom="$(hub_custom_path)"
  [ -z "$custom" ] || roots+=("$custom")
  if [ "$IS_MACOS" = true ]; then
    roots+=("/Applications/Unity/Hub/Editor" "$HOME/Applications/Unity/Hub/Editor")
  else
    roots+=("$HOME/Unity/Hub/Editor" "/opt/Unity/Hub/Editor" "/usr/local/Unity/Hub/Editor")
  fi
  for root in "${roots[@]}"; do
    if [ -d "$root" ]; then printf '%s\n' "$root"; fi
  done | awk '!seen[$0]++'
}

unity_executable() {
  local version="$1" root candidate
  while IFS= read -r root; do
    if [ "$IS_MACOS" = true ]; then
      candidate="$root/$version/Unity.app/Contents/MacOS/Unity"
    else
      candidate="$root/$version/Editor/Unity"
    fi
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done <<<"$ROOTS"
}

ROOTS="$(editor_roots)"
[ -n "$ROOTS" ] || die "No Unity editors folder found. Install editors with Unity Hub or pass --editors-path."

if [ "$ASK" = true ]; then
  ui_header "Open Unity projects"
  CANDIDATES=("Installer" "Unity-Package")
  while IFS= read -r project; do
    CANDIDATES+=("Unity-Tests/$project")
  done < <(unity_test_projects)
  LABELS=()
  for project in "${CANDIDATES[@]}"; do
    unity_version="$(project_unity_version "$REPO_ROOT/$project")"
    if [ -z "$unity_version" ]; then
      LABELS+=("$project  ${C_GRAY}(no editor version)${C_RESET}")
    elif [ -n "$(unity_executable "$unity_version")" ]; then
      LABELS+=("$project  ${C_GRAY}Unity $unity_version${C_RESET}")
    else
      LABELS+=("$project  ${C_YELLOW}Unity $unity_version is not installed${C_RESET}")
    fi
  done
  ui_multiselect "Projects to open" "0 1" "${LABELS[@]}"
  [ "${#UI_SELECTED[@]}" -gt 0 ] || { say "Nothing selected." "$C_YELLOW"; exit 0; }
  for i in "${UI_SELECTED[@]}"; do
    PROJECTS+=("${CANDIDATES[$i]}")
  done
  echo ""
fi

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  PROJECTS=("Installer" "Unity-Package")
  if [ "$WITH_TESTS" = true ]; then
    while IFS= read -r project; do
      PROJECTS+=("Unity-Tests/$project")
    done < <(unity_test_projects)
  fi
fi

say "Opening Unity projects..." "$C_CYAN"
say "Editors folders: $(printf '%s' "$ROOTS" | tr '\n' ' ')" "$C_GRAY"
echo ""

opened=0
for project in "${PROJECTS[@]}"; do
  project_path="$REPO_ROOT/$project"
  if [ ! -d "$project_path" ]; then
    warn "Project not found: $project"
    continue
  fi

  unity_version="$(project_unity_version "$project_path")"
  if [ -z "$unity_version" ]; then
    warn "No editor version in $project/ProjectSettings/ProjectVersion.txt. Skipping."
    continue
  fi

  unity_exe="$(unity_executable "$unity_version")"
  if [ -z "$unity_exe" ]; then
    warn "Unity $unity_version is not installed. Skipping: $project"
    continue
  fi

  if [ "$WHAT_IF" = true ]; then
    echo "What if: Open $project with $unity_exe"
    continue
  fi

  say "Opening: $project (Unity $unity_version)" "$C_YELLOW"
  # Launch Unity Editor with the project path (in background)
  "$unity_exe" -projectPath "$project_path" >/dev/null 2>&1 &
  opened=$((opened + 1))
  # Delay between launches to avoid overwhelming the system
  sleep 2
done

echo ""
say "Done! Opened $opened project(s)." "$C_GREEN"
