# shellcheck shell=bash
# Terminal UI for the .sh scripts in commands/: text prompts with defaults, arrow-key
# menus and checkbox lists. Sourced by common.sh.
#
# Scripts ask for missing parameters only when ui_enabled: stdin and stderr are a
# terminal and CI is not set. Everything is drawn on stderr, so stdout stays clean.
# Works with the bash 3.2 that ships with macOS.

if [ -t 2 ]; then
  C_BOLD=$'\033[1m'
else
  C_BOLD=''
fi

ui_enabled() {
  [ -t 0 ] && [ -t 2 ] && [ -z "${CI:-}" ] && [ "${TERM:-dumb}" != "dumb" ]
}

ui_header() {
  printf '\n%s%s◆ %s%s\n\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET" >&2
}

# The answer line that replaces a finished prompt: "✔ Question  answer".
ui_answered() {
  printf '%s✔%s %s  %s%s%s\n' "$C_GREEN" "$C_RESET" "$1" "$C_CYAN" "$2" "$C_RESET" >&2
}

# Moves the cursor up $1 lines and clears from there to the end of the screen.
ui_erase_lines() {
  [ "$1" -gt 0 ] && printf '\033[%dA' "$1" >&2
  printf '\r\033[J' >&2
}

# ui_input VAR "Question" [default] [regex] [hint]
# Reads one line into VAR. Enter keeps the default. With a regex, asks again until the
# answer matches it; the hint describes the expected format. Without a default and a
# regex, an empty answer is allowed.
ui_input() {
  local __var="$1" question="$2" default="${3:-}" regex="${4:-}" hint="${5:-}"
  local answer lines=2
  while :; do
    if [ -n "$default" ]; then
      printf '%s?%s %s%s%s %s(Enter: %s)%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" "$C_GRAY" "$default" "$C_RESET" >&2
    else
      printf '%s?%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" >&2
    fi
    IFS= read -r -e -p "  > " answer || { printf '\n' >&2; exit 130; }
    [ -n "$answer" ] || answer="$default"
    if [ -z "$regex" ] || [[ "$answer" =~ $regex ]]; then
      break
    fi
    # Replace the prompt (and an earlier error) with the error, then ask again below it.
    ui_erase_lines "$lines"
    printf '%s✖ "%s" is not valid. %s%s\n' "$C_RED" "$answer" "$hint" "$C_RESET" >&2
    lines=3
  done
  ui_erase_lines "$lines"
  ui_answered "$question" "${answer:-(none)}"
  printf -v "$__var" '%s' "$answer"
}

# Draws the menu lines of ui_select / ui_multiselect.
# $1: cursor index, $2: "multi" or "single", $3: space-separated checked indices, rest: options.
ui_draw_options() {
  local cursor="$1" mode="$2" checked=" $3 "; shift 3
  local i=0 option mark pointer
  for option in "$@"; do
    pointer="  "
    [ "$i" -eq "$cursor" ] && pointer="${C_CYAN}❯${C_RESET} "
    if [ "$mode" = "multi" ]; then
      case "$checked" in
        *" $i "*) mark="${C_GREEN}◉${C_RESET} " ;;
        *) mark="${C_GRAY}◯${C_RESET} " ;;
      esac
    else
      mark=""
    fi
    if [ "$i" -eq "$cursor" ]; then
      printf '\r\033[2K  %s%s%s%s%s\n' "$pointer" "$mark" "$C_CYAN" "$option" "$C_RESET" >&2
    else
      printf '\r\033[2K  %s%s%s\n' "$pointer" "$mark" "$option" >&2
    fi
    i=$((i + 1))
  done
}

# Reads one key press and prints up, down, space, enter, all or a digit.
ui_read_key() {
  local key rest
  IFS= read -rsn1 key || { printf 'quit'; return; }
  case "$key" in
    $'\033')
      IFS= read -rsn2 rest || true
      case "$rest" in
        '[A' | 'OA') printf 'up' ;;
        '[B' | 'OB') printf 'down' ;;
        *) printf 'other' ;;
      esac
      ;;
    '') printf 'enter' ;;
    ' ') printf 'space' ;;
    k | K) printf 'up' ;;
    j | J) printf 'down' ;;
    a | A) printf 'all' ;;
    [1-9]) printf '%s' "$key" ;;
    *) printf 'other' ;;
  esac
}

# ui_select VAR "Question" default-index option...
# Arrow-key menu. Sets VAR to the chosen index (0-based) and UI_CHOICE to its text.
# Text after two spaces in an option is a description, left out of the answer line.
ui_select() {
  local __var="$1" question="$2" cursor="$3"; shift 3
  local count=$# key
  local options=("$@")
  printf '%s?%s %s%s%s %s(↑/↓, Enter)%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" "$C_GRAY" "$C_RESET" >&2
  printf '\033[?25l' >&2
  trap 'printf "\033[?25h\n" >&2; exit 130' INT
  ui_draw_options "$cursor" single "" "${options[@]}"
  while :; do
    key="$(ui_read_key)"
    case "$key" in
      up) cursor=$(((cursor + count - 1) % count)) ;;
      down) cursor=$(((cursor + 1) % count)) ;;
      enter | space) break ;;
      quit) printf '\033[?25h\n' >&2; exit 130 ;;
      [1-9]) [ "$key" -le "$count" ] && cursor=$((key - 1)) ;;
    esac
    printf '\033[%dA' "$count" >&2
    ui_draw_options "$cursor" single "" "${options[@]}"
  done
  trap - INT
  printf '\033[?25h' >&2
  ui_erase_lines $((count + 1))
  UI_CHOICE="${options[$cursor]}"
  ui_answered "$question" "${UI_CHOICE%%  *}"
  printf -v "$__var" '%s' "$cursor"
}

# ui_multiselect "Question" "checked indices" option...
# Checkbox list: Space toggles, a toggles all, Enter confirms. Sets UI_SELECTED to the
# checked indices (0-based, in order). Descriptions work as in ui_select.
ui_multiselect() {
  local question="$1" checked="$2"; shift 2
  local count=$# cursor=0 key i next summary=""
  local options=("$@")
  printf '%s?%s %s%s%s %s(↑/↓, Space: toggle, a: all, Enter)%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" "$C_GRAY" "$C_RESET" >&2
  printf '\033[?25l' >&2
  trap 'printf "\033[?25h\n" >&2; exit 130' INT
  ui_draw_options "$cursor" multi "$checked" "${options[@]}"
  while :; do
    key="$(ui_read_key)"
    case "$key" in
      up) cursor=$(((cursor + count - 1) % count)) ;;
      down) cursor=$(((cursor + 1) % count)) ;;
      space)
        case " $checked " in
          *" $cursor "*) next=""; for i in $checked; do [ "$i" -eq "$cursor" ] || next="$next $i"; done; checked="$next" ;;
          *) checked="$checked $cursor" ;;
        esac
        ;;
      all)
        if [ "$(printf '%s\n' $checked | grep -c .)" -eq "$count" ]; then
          checked=""
        else
          checked="$(seq 0 $((count - 1)) | tr '\n' ' ')"
        fi
        ;;
      enter) break ;;
      quit) printf '\033[?25h\n' >&2; exit 130 ;;
    esac
    printf '\033[%dA' "$count" >&2
    ui_draw_options "$cursor" multi "$checked" "${options[@]}"
  done
  trap - INT
  printf '\033[?25h' >&2
  ui_erase_lines $((count + 1))
  UI_SELECTED=()
  i=0
  while [ "$i" -lt "$count" ]; do
    case " $checked " in
      *" $i "*) UI_SELECTED+=("$i"); summary="${summary:+$summary, }${options[$i]%%  *}" ;;
    esac
    i=$((i + 1))
  done
  ui_answered "$question" "${summary:-(none)}"
}

# ui_confirm "Question" [yes|no]: returns 0 for Yes. The second argument is the default.
ui_confirm() {
  local answer default=0
  [ "${2:-yes}" = "no" ] && default=1
  ui_select answer "$1" "$default" "Yes" "No"
  [ "$answer" -eq 0 ]
}
