#!/usr/bin/env bash
#
# Menu for all scripts in commands/ (macOS and Linux; on Windows use menu.cmd).
#
# Pick a script with the arrow keys; it then asks for its options the same way, so no
# parameters need to be typed. The menu comes back after each script until you quit.
#
# Usage:
#   ./commands/menu.sh

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

case "${1:-}" in
  "") ;;
  -h | --help) usage 0 ;;
  *) printf 'Unknown option: %s\n\n' "$1" >&2; usage 1 ;;
esac

ui_enabled || die "The menu needs an interactive terminal. Run the scripts in commands/ with options instead (see --help)."

COMMANDS_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_JSON="$REPO_ROOT/Unity-Package/Assets/root/package.json"

# "Name  description", padded so the descriptions line up.
entry() {
  printf '%-24s%s%s%s' "$1" "$C_GRAY" "$2" "$C_RESET"
}

while :; do
  SCRIPTS=()
  LABELS=()
  if grep -qF "YOUR_PACKAGE_ID" "$PACKAGE_JSON"; then
    SCRIPTS+=("init.sh")
    LABELS+=("$(entry "Initialize the package" "replace the template placeholders")")
  fi
  SCRIPTS+=("open-all-projects.sh" "check-package.sh" "test-project.sh" "bump-version.sh" "")
  LABELS+=(
    "$(entry "Open Unity projects" "generate .meta files, edit the package")"
    "$(entry "Check the package" "the license-free checks CI runs first")"
    "$(entry "Manage test projects" "add or remove tested Unity versions")"
    "$(entry "Bump the version" "prepare a release")"
    "Quit"
  )

  ui_header "Unity Package Starter Kit"
  ui_select CHOICE "What do you want to do?" 0 "${LABELS[@]}"
  SCRIPT="${SCRIPTS[$CHOICE]}"
  [ -n "$SCRIPT" ] || exit 0

  # A failing or interrupted (Ctrl+C) script returns to the menu instead of closing it.
  trap ':' INT
  bash "$COMMANDS_DIR/$SCRIPT" || warn "$SCRIPT exited with status $?."
  trap - INT
  echo ""
  read -r -s -p "${C_GRAY}Press Enter to return to the menu...${C_RESET}" _ || exit 0
  printf '\r\033[2K' >&2
done
