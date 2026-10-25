#!/usr/bin/env bash
#
# Initializes the Unity Package project by replacing placeholders (macOS and Linux;
# on Windows use init.ps1).
#
# Replaces placeholders in file content, filenames, and directory names:
#   YOUR_PACKAGE_ID, YOUR_PACKAGE_ID_LOWERCASE, YOUR_PACKAGE_NAME, YOUR_PACKAGE_NAME_PASCAL,
#   YOUR_PACKAGE_NAME_INSTALLER, YOUR_PACKAGE_NAME_INSTALLER_FILE, YOUR_ROOT_NAMESPACE,
#   YOUR_GITHUB_USERNAME_REPOSITORY
# Afterwards it enables the sample workflows and replaces the template README with the
# package README. Run it once, on a fresh copy of the template.
#
# Usage:
#   ./commands/init.sh --package-id com.company.cool-package --package-name "Cool Package" \
#     --github-repository User/cool-package [--root-namespace Company.CoolPackage] \
#     [--installer-extra-path Editor]
#
# Options:
#   --package-id            Lowercase reverse-domain package name, e.g. com.company.cool-package.
#   --package-name          Display name, e.g. "Cool Package".
#   --github-repository     "Username/Repository-Name".
#   --root-namespace        Optional C# root namespace. Package ids may contain characters that
#                           are not valid in a namespace, so by default it is derived from them:
#                           "com.mycompany.cool-package" + "Cool Package" -> "Mycompany.CoolPackage".
#   --installer-extra-path  Optional folder between Assets/ and the installer folder, e.g. "Editor".
#                           Prompted when omitted (press Enter to skip).
#
# Run in a terminal, the script asks for every option that was not passed, with defaults
# taken from the git remote, so "./commands/init.sh" alone is enough.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

PACKAGE_ID=""
PACKAGE_NAME=""
GITHUB_REPOSITORY=""
ROOT_NAMESPACE=""
INSTALLER_EXTRA_PATH=""
HAS_EXTRA_PATH=false
ASKED=false

while [ $# -gt 0 ]; do
  case "$1" in
    --package-id) PACKAGE_ID="${2:-}"; shift 2 ;;
    --package-name) PACKAGE_NAME="${2:-}"; shift 2 ;;
    --github-repository) GITHUB_REPOSITORY="${2:-}"; shift 2 ;;
    --root-namespace) ROOT_NAMESPACE="${2:-}"; shift 2 ;;
    --installer-extra-path) INSTALLER_EXTRA_PATH="${2:-}"; HAS_EXTRA_PATH=true; shift 2 ;;
    -h | --help) usage 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage 1 ;;
  esac
done

PACKAGE_ID_RE='^[a-z0-9_-]+(\.[a-z0-9_-]+){2,}$'
GITHUB_REPOSITORY_RE='^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$'
NAMESPACE_RE='^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$'

# Refuse to run twice: the second run would find no placeholders and only overwrite README.md.
PACKAGE_JSON="$REPO_ROOT/Unity-Package/Assets/root/package.json"
grep -qF "YOUR_PACKAGE_ID" "$PACKAGE_JSON" ||
  die "The template is already initialized: $PACKAGE_JSON has no placeholders left."

# "Cool Package" -> "CoolPackage", "cool-package" -> "CoolPackage"
pascal_case() {
  printf '%s' "$1" | perl -pe 's/[^A-Za-z0-9]*([A-Za-z0-9]+)/\u$1/g; s/[^A-Za-z0-9]//g'
}

# Skip the reverse-domain prefix ("com", "org", ...) and use the company segment:
# "com.mycompany.cool-package" + "Cool Package" -> "Mycompany.CoolPackage".
default_root_namespace() {
  local company name
  company="$(pascal_case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | cut -d. -f2)")"
  name="$(pascal_case "$2")"
  if [ -n "$name" ]; then
    printf '%s\n' "${company:+$company.}$name"
  else
    printf '%s\n' "$company"
  fi
}

# Ask for everything that was not passed. Defaults come from the git remote:
# github.com/User/cool-package -> "User/cool-package", "Cool Package", "com.user.cool-package".
if ui_enabled && { [ -z "$PACKAGE_ID" ] || [ -z "$PACKAGE_NAME" ] || [ -z "$GITHUB_REPOSITORY" ]; }; then
  ASK_ALL=false
  [ -z "$PACKAGE_ID$PACKAGE_NAME$GITHUB_REPOSITORY$ROOT_NAMESPACE" ] && [ "$HAS_EXTRA_PATH" = false ] && ASK_ALL=true
  ui_header "Initialize the package"
  ASKED=true

  REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  REMOTE_SLUG="$(printf '%s' "$REMOTE_URL" | sed -nE 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed -E 's#\.git$##')"
  [[ "$REMOTE_SLUG" =~ $GITHUB_REPOSITORY_RE ]] || REMOTE_SLUG=""
  if [ -z "$GITHUB_REPOSITORY" ]; then
    ui_input GITHUB_REPOSITORY "GitHub repository" "$REMOTE_SLUG" "$GITHUB_REPOSITORY_RE" "Use 'Username/Repository-Name'."
  fi

  REPO_NAME="${GITHUB_REPOSITORY#*/}"
  OWNER="${GITHUB_REPOSITORY%%/*}"
  if [ -z "$PACKAGE_NAME" ]; then
    DEFAULT_NAME="$(printf '%s' "$REPO_NAME" | perl -pe 's/[-_.]+/ /g; s/\b(\w)/\u$1/g')"
    ui_input PACKAGE_NAME "Package display name" "$DEFAULT_NAME" '[^[:space:]]' "Enter a name."
  fi
  if [ -z "$PACKAGE_ID" ]; then
    id_part() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'; }
    DEFAULT_ID="com.$(id_part "$OWNER").$(id_part "$PACKAGE_NAME")"
    ui_input PACKAGE_ID "Package id" "$DEFAULT_ID" "$PACKAGE_ID_RE" "Use a lowercase reverse-domain name such as 'com.company.cool-package'."
  fi
  if [ "$ASK_ALL" = true ]; then
    ui_input ROOT_NAMESPACE "C# root namespace" "$(default_root_namespace "$PACKAGE_ID" "$PACKAGE_NAME")" "$NAMESPACE_RE" "Use a C# namespace such as 'Company.CoolPackage'."
  fi
fi

[ -n "$PACKAGE_ID" ] || die "--package-id is required (see --help)."
[ -n "$PACKAGE_NAME" ] || die "--package-name is required (see --help)."
[ -n "$GITHUB_REPOSITORY" ] || die "--github-repository is required (see --help)."

# Package Manager accepts lowercase reverse-domain names only.
[[ "$PACKAGE_ID" =~ $PACKAGE_ID_RE ]] ||
  die "Invalid package id '$PACKAGE_ID'. Use a lowercase reverse-domain name such as 'com.company.cool-package'."
[[ "$GITHUB_REPOSITORY" =~ $GITHUB_REPOSITORY_RE ]] ||
  die "Invalid GitHub repository '$GITHUB_REPOSITORY'. Use 'Username/Repository-Name'."

# Ask for the installer extra path if not provided
if [ "$HAS_EXTRA_PATH" = false ]; then
  if ui_enabled; then
    ASKED=true
    ui_select CHOICE "Installer location" 0 \
      "Installer/Assets/Editor/$PACKAGE_NAME Installer" \
      "Installer/Assets/$PACKAGE_NAME Installer" \
      "Another folder..."
    case "$CHOICE" in
      0) INSTALLER_EXTRA_PATH="Editor" ;;
      1) INSTALLER_EXTRA_PATH="" ;;
      2) ui_input INSTALLER_EXTRA_PATH "Folder between Assets/ and the installer folder" "" '^[^\\/].*$|^$' "Use a relative path such as 'Editor/Tools'." ;;
    esac
  else
    say "Optional: Enter an extra path for the Installer (e.g., 'Editor')." "$C_CYAN"
    say "Press Enter to skip." "$C_GRAY"
    read -r -p "Installer Extra Path: " INSTALLER_EXTRA_PATH || true
  fi
fi

# Normalize: forward slashes, no leading or trailing slash, no surrounding spaces.
INSTALLER_EXTRA_PATH="$(printf '%s' "$INSTALLER_EXTRA_PATH" | tr '\\' '/' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#^/+##; s#/+$##')"

PACKAGE_ID_LOWERCASE="$(printf '%s' "$PACKAGE_ID" | tr '[:upper:]' '[:lower:]')"
PACKAGE_NAME_PASCAL="$(pascal_case "$PACKAGE_NAME")"
[ -n "$ROOT_NAMESPACE" ] || ROOT_NAMESPACE="$(default_root_namespace "$PACKAGE_ID" "$PACKAGE_NAME")"
[[ "$ROOT_NAMESPACE" =~ $NAMESPACE_RE ]] ||
  die "Invalid root namespace '$ROOT_NAMESPACE'. Pass a valid C# namespace with --root-namespace."

PACKAGE_NAME_INSTALLER_BASE="$PACKAGE_NAME Installer"
PACKAGE_NAME_INSTALLER_FILE="${PACKAGE_NAME_INSTALLER_BASE// /-}"
if [ -z "$INSTALLER_EXTRA_PATH" ]; then
  PACKAGE_NAME_INSTALLER="$PACKAGE_NAME_INSTALLER_BASE"
else
  PACKAGE_NAME_INSTALLER="$INSTALLER_EXTRA_PATH/$PACKAGE_NAME_INSTALLER_BASE"
fi

# Placeholders, longest first so YOUR_PACKAGE_ID does not eat YOUR_PACKAGE_ID_LOWERCASE.
# The values are passed to perl through the environment and inserted literally.
export PH_YOUR_PACKAGE_NAME_INSTALLER_FILE="$PACKAGE_NAME_INSTALLER_FILE"
export PH_YOUR_GITHUB_USERNAME_REPOSITORY="$GITHUB_REPOSITORY"
export PH_YOUR_PACKAGE_NAME_INSTALLER="$PACKAGE_NAME_INSTALLER"
export PH_YOUR_PACKAGE_ID_LOWERCASE="$PACKAGE_ID_LOWERCASE"
export PH_YOUR_PACKAGE_NAME_PASCAL="$PACKAGE_NAME_PASCAL"
export PH_YOUR_ROOT_NAMESPACE="$ROOT_NAMESPACE"
export PH_YOUR_PACKAGE_NAME="$PACKAGE_NAME"
export PH_YOUR_PACKAGE_ID="$PACKAGE_ID"
export PH_KEYS="YOUR_PACKAGE_NAME_INSTALLER_FILE YOUR_GITHUB_USERNAME_REPOSITORY YOUR_PACKAGE_NAME_INSTALLER YOUR_PACKAGE_ID_LOWERCASE YOUR_PACKAGE_NAME_PASCAL YOUR_ROOT_NAMESPACE YOUR_PACKAGE_NAME YOUR_PACKAGE_ID"
REPLACE_PROGRAM='BEGIN { @keys = split / /, $ENV{PH_KEYS} } for my $k (@keys) { my $v = $ENV{"PH_$k"}; s/\Q$k\E/$v/g }'

say "Initializing package with:" "$C_CYAN"
echo "  ID: $PACKAGE_ID"
echo "  Name: $PACKAGE_NAME"
echo "  Root Namespace: $ROOT_NAMESPACE"
echo "  Installer: $PACKAGE_NAME_INSTALLER"
echo "  Installer File: $PACKAGE_NAME_INSTALLER_FILE"
echo "  GitHub Repository: $GITHUB_REPOSITORY"
[ -n "$INSTALLER_EXTRA_PATH" ] && echo "  Installer Extra Path: $INSTALLER_EXTRA_PATH"
echo ""
if [ "$ASKED" = true ] && ! ui_confirm "Initialize with these values?"; then
  say "Cancelled, nothing was changed." "$C_YELLOW"
  exit 0
fi

# All files and folders that get placeholders replaced. Unity's generated folders can be
# huge and must never be rewritten, so they are pruned at the root of every Unity project.
list_targets() {
  local project
  for project in "$REPO_ROOT/Installer" "$REPO_ROOT/Unity-Package" "$REPO_ROOT"/Unity-Tests/*/; do
    project="${project%/}"
    [ -d "$project" ] || continue
    find "$project" \( -name .git -o -path "$project/Library" -o -path "$project/Temp" -o -path "$project/Logs" \
      -o -path "$project/obj" -o -path "$project/UserSettings" -o -path "$project/Build" -o -path "$project/Builds" \
      -o -path "$project/.vs" -o -path "$project/.idea" \) -prune -o -print
  done
  for path in "$REPO_ROOT/README.md" "$REPO_ROOT/CHANGELOG.md" "$REPO_ROOT/docs" "$REPO_ROOT/.github"; do
    [ -e "$path" ] || { warn "Path not found: $path"; continue; }
    find "$path" -name .git -prune -o -print
  done
}

# 1. Replace content in files (text files only; bytes, line endings and BOMs are preserved)
say "Replacing content in files..." "$C_YELLOW"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT
while IFS= read -r file; do
  [ -f "$file" ] || continue
  grep -qIF "YOUR_" "$file" || continue
  perl -pe "$REPLACE_PROGRAM" "$file" >"$TMP_FILE"
  if ! cmp -s "$TMP_FILE" "$file"; then
    # Overwrite in place to keep the file's permissions.
    cat "$TMP_FILE" >"$file"
    say "  Updated: $(relative_path "$file")" "$C_GRAY"
  fi
done < <(list_targets)

# 1.5. Create extra path folders and move installer (if extra path provided)
if [ -n "$INSTALLER_EXTRA_PATH" ]; then
  say "Creating extra path and moving installer folder..." "$C_YELLOW"
  INSTALLER_ASSETS_DIR="$REPO_ROOT/Installer/Assets"
  SOURCE_FOLDER="$INSTALLER_ASSETS_DIR/YOUR_PACKAGE_NAME_INSTALLER"
  EXTRA_PATH_DIR="$INSTALLER_ASSETS_DIR/$INSTALLER_EXTRA_PATH"
  if [ ! -d "$EXTRA_PATH_DIR" ]; then
    mkdir -p "$EXTRA_PATH_DIR"
    say "  Created: $EXTRA_PATH_DIR" "$C_GRAY"
  fi
  if [ -d "$SOURCE_FOLDER" ]; then
    mv "$SOURCE_FOLDER" "$EXTRA_PATH_DIR/YOUR_PACKAGE_NAME_INSTALLER"
    say "  Moved installer to: $INSTALLER_EXTRA_PATH/" "$C_GRAY"
  fi
fi

# 2. Rename files and directories. Folder names use the installer name without the extra path.
# Deepest paths first, so a folder is renamed only after everything inside it.
say "Renaming files and directories..." "$C_YELLOW"
export PH_YOUR_PACKAGE_NAME_INSTALLER="$PACKAGE_NAME_INSTALLER_BASE"
while IFS= read -r item; do
  [ -e "$item" ] || continue
  name="$(basename "$item")"
  case "$name" in *YOUR_*) ;; *) continue ;; esac
  new_name="$(printf '%s' "$name" | perl -pe "$REPLACE_PROGRAM")"
  if [ "$new_name" != "$name" ]; then
    mv "$item" "$(dirname "$item")/$new_name"
    say "  Renamed: $name -> $new_name" "$C_GRAY"
  fi
done < <(list_targets | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)

# 3. Enable the sample workflows
say "Enabling workflows..." "$C_YELLOW"
for sample in "$WORKFLOWS_DIR"/*.yml-sample; do
  [ -f "$sample" ] || continue
  enabled="${sample%-sample}"
  mv "$sample" "$enabled"
  say "  Enabled: $(basename "$enabled")" "$C_GRAY"
done

# 4. The template README is no longer needed: the package README replaces it.
#    Both copies must stay identical (commands/check-package.sh checks it).
say "Replacing README.md with the package README..." "$C_YELLOW"
cp "$REPO_ROOT/Unity-Package/Assets/root/README.md" "$REPO_ROOT/README.md"

say "Done!" "$C_GREEN"
echo ""
say "Next steps:" "$C_CYAN"
echo "  1. Fill in description, keywords and unity in Unity-Package/Assets/root/package.json."
echo "  2. Open every project once to generate .meta files: ./commands/open-all-projects.sh"
echo "  3. Run ./commands/check-package.sh and commit."
echo "  4. Add the CI secrets (UNITY_*, UPM_*), see docs/openupm-signing.md."
