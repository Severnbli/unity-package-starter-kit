#!/usr/bin/env bash
#
# Updates the package version in every file that contains it (macOS and Linux; on
# Windows use bump-version.ps1). The package id and the installer location are read
# from the repository, so the script needs no edits after init.
#
# Usage:
#   ./commands/bump-version.sh 1.2.3
#   ./commands/bump-version.sh 1.2.3-preview.1 --what-if    # preview only
#   ./commands/bump-version.sh 1.2.3 --sync-docs to-package
#
# Options:
#   --what-if            Preview changes without applying them.
#   --sync-docs <dir>    Copy README.md and CHANGELOG.md before bumping, so the root and
#                        package copies are identical:
#                          to-package  from the repository root to Unity-Package/Assets/root
#                          to-root     from Unity-Package/Assets/root to the repository root
#
# Run in a terminal without a version, the script offers the next patch, minor, major or
# preview version and asks about --sync-docs and --what-if.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

NEW_VERSION=""
WHAT_IF=false
SYNC_DOCS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --what-if | -n) WHAT_IF=true; shift ;;
    --sync-docs)
      SYNC_DOCS="${2:-}"; shift 2
      case "$SYNC_DOCS" in to-package | to-root) ;; *) die "--sync-docs expects 'to-package' or 'to-root'." ;; esac
      ;;
    -h | --help) usage 0 ;;
    -*) printf 'Unknown option: %s\n\n' "$1" >&2; usage 1 ;;
    *) [ -z "$NEW_VERSION" ] || usage 1; NEW_VERSION="$1"; shift ;;
  esac
done
[ -n "$NEW_VERSION" ] || ui_enabled || usage 1

cd "$REPO_ROOT"

# A version as written in the files: 1.2.3, 1.2.3-preview.1, 1.2.3+build.5
export VERSION_VALUE='\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?'

say "🚀 Package Version Bump Script" "$C_CYAN"
say "=================================" "$C_CYAN"

PACKAGE_JSON="Unity-Package/Assets/root/package.json"
[ -f "$PACKAGE_JSON" ] || die "Could not find package.json at: $PACKAGE_JSON"
CURRENT_VERSION="$(perl -ne 'if (/"version":\s*"($ENV{VERSION_VALUE})"/) { print $1; exit }' "$PACKAGE_JSON")"
[ -n "$CURRENT_VERSION" ] || die "Could not extract current version from package.json"
export PACKAGE_NAME
PACKAGE_NAME="$(perl -ne 'if (/^\s*"name":\s*"([^"]+)"/) { print $1; exit }' "$PACKAGE_JSON")"

# Without a version, offer the next ones: 1.2.3 -> 1.2.4, 1.3.0, 2.0.0, 1.2.4-preview.1;
# a prerelease 1.3.0-preview.1 -> 1.3.0, 1.3.0-preview.2.
if [ -z "$NEW_VERSION" ]; then
  ui_header "Bump the package version (current: $CURRENT_VERSION)"
  read -r MAJOR MINOR PATCH PRERELEASE <<<"$(printf '%s' "$CURRENT_VERSION" | perl -ne '/^(\d+)\.(\d+)\.(\d+)(?:-([^+]+))?/ and print "$1 $2 $3 $4"')"
  if [ -n "$PRERELEASE" ]; then
    NEXT_PRERELEASE="$(printf '%s' "$PRERELEASE" | perl -pe 's/(\d+)$/$1 + 1/e or $_ .= ".1"')"
    VERSIONS=("$MAJOR.$MINOR.$PATCH" "$MAJOR.$MINOR.$PATCH-$NEXT_PRERELEASE")
    LABELS=("${VERSIONS[0]}  ${C_GRAY}release${C_RESET}" "${VERSIONS[1]}  ${C_GRAY}next preview${C_RESET}")
  else
    VERSIONS=("$MAJOR.$MINOR.$((PATCH + 1))" "$MAJOR.$((MINOR + 1)).0" "$((MAJOR + 1)).0.0" "$MAJOR.$MINOR.$((PATCH + 1))-preview.1")
    LABELS=("${VERSIONS[0]}  ${C_GRAY}patch${C_RESET}" "${VERSIONS[1]}  ${C_GRAY}minor${C_RESET}" "${VERSIONS[2]}  ${C_GRAY}major${C_RESET}" "${VERSIONS[3]}  ${C_GRAY}preview${C_RESET}")
  fi
  ui_select CHOICE "New version" 0 "${LABELS[@]}" "Other..."
  if [ "$CHOICE" -lt "${#VERSIONS[@]}" ]; then
    NEW_VERSION="${VERSIONS[$CHOICE]}"
  else
    ui_input NEW_VERSION "New version" "" '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' "Use major.minor.patch, e.g. 1.2.3 or 1.2.3-preview.1."
  fi
  if [ -z "$SYNC_DOCS" ]; then
    ui_select CHOICE "Copy README.md and CHANGELOG.md first?" 0 \
      "No" \
      "Root -> package  ${C_GRAY}to-package${C_RESET}" \
      "Package -> root  ${C_GRAY}to-root${C_RESET}"
    case "$CHOICE" in 1) SYNC_DOCS="to-package" ;; 2) SYNC_DOCS="to-root" ;; esac
  fi
  if [ "$WHAT_IF" = false ]; then
    ui_select CHOICE "Apply the changes?" 0 "Apply" "Preview only  ${C_GRAY}--what-if${C_RESET}"
    [ "$CHOICE" -eq 0 ] || WHAT_IF=true
  fi
  echo ""
fi

if ! printf '%s' "$NEW_VERSION" | perl -ne 'exit(/\A\d+\.\d+\.\d+(-[a-zA-Z0-9\-\.]+)?(\+[a-zA-Z0-9\-\.]+)?\z/ ? 0 : 1)'; then
  say "❌ Invalid semantic version format: $NEW_VERSION" "$C_RED"
  say "Expected format: major.minor.patch (e.g., '1.2.3')" "$C_YELLOW"
  exit 1
fi

# The installer folder moves and is renamed by init, so find it instead of hard-coding it.
INSTALLER_FILES="$(grep -rlF --include=Installer.cs "public const string Version" Installer/Assets || true)"
INSTALLER_COUNT="$(printf '%s' "$INSTALLER_FILES" | grep -c . || true)"
[ "$INSTALLER_COUNT" = "1" ] ||
  die "Expected one Installer.cs with a Version constant under Installer/Assets, found $INSTALLER_COUNT."

say "📋 Current version: $CURRENT_VERSION" ""
say "📋 New version: $NEW_VERSION" ""

# Copy the docs first: the version replacement below then updates both copies alike.
if [ -n "$SYNC_DOCS" ]; then
  package_dir="Unity-Package/Assets/root"
  say "" ""
  if [ "$SYNC_DOCS" = "to-package" ]; then
    say "📄 Copying README.md and CHANGELOG.md to $package_dir..." "$C_CYAN"
  else
    say "📄 Copying README.md and CHANGELOG.md to the repository root..." "$C_CYAN"
  fi
  for doc in README.md CHANGELOG.md; do
    if [ "$SYNC_DOCS" = "to-package" ]; then
      source="$doc"; destination="$package_dir/$doc"
    else
      source="$package_dir/$doc"; destination="$doc"
    fi
    [ -f "$source" ] || die "File not found: $source"
    say "   $source → $destination" "$C_GRAY"
    [ "$WHAT_IF" = true ] || cp "$source" "$destination"
  done
fi

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
  say "⚠️  New version is the same as current version" "$C_YELLOW"
  exit 0
fi

# Each entry: path, perl pattern with the text before and after the version as groups 1 and 2, description.
# PKGNAME stands for the package name, VERSION for the version; both are inserted by perl.
TARGETS=(
  "$PACKAGE_JSON" '("version":\s*")VERSION(")' "Unity package version"
  "$INSTALLER_FILES" '(public const string Version = ")VERSION(";)' "Installer C# version constant"
  "Unity-Package/Assets/root/README.md" '("PKGNAME":\s*")VERSION(")' "Package README manual install version"
  "README.md" '("PKGNAME":\s*")VERSION(")' "Repository README manual install version"
)

say "" ""
say "🔍 Scanning for version references..." "$C_CYAN"
export NEW_VERSION
CHANGED_FILES=()
TOTAL=0
i=0
while [ "$i" -lt "${#TARGETS[@]}" ]; do
  path="${TARGETS[$i]}"
  export PATTERN="${TARGETS[$((i + 1))]}"
  description="${TARGETS[$((i + 2))]}"
  i=$((i + 3))

  if [ ! -f "$path" ]; then
    say "⚠️  File not found: $path" "$C_YELLOW"
    continue
  fi

  # Print "old → new" for every match, then the count on the last line.
  report="$(perl -ne '
    BEGIN { ($p = $ENV{PATTERN}) =~ s/VERSION/(?:$ENV{VERSION_VALUE})/; $p =~ s/PKGNAME/\Q$ENV{PACKAGE_NAME}\E/; $re = qr/$p/ }
    while (/$re/g) { $old = $&; ($new = $old) =~ s/$re/$1$ENV{NEW_VERSION}$2/; print "   $old → $new\n"; $c++ }
    END { print $c + 0 }' "$path")"
  count="$(printf '%s\n' "$report" | tail -n 1)"
  if [ "$count" -eq 0 ]; then
    say "⚠️  No matches found in: $path" "$C_YELLOW"
    say "   Pattern: $PATTERN" "$C_GRAY"
    continue
  fi
  say "📝 $description: $count occurrence(s)" "$C_GREEN"
  printf '%s\n' "$report" | sed '$d' | while IFS= read -r line; do say "$line" "$C_GRAY"; done
  TOTAL=$((TOTAL + count))
  CHANGED_FILES+=("$path" "$PATTERN")
done

if [ "$TOTAL" -eq 0 ]; then
  say "❌ No version references found to update!" "$C_RED"
  exit 1
fi

if [ "$WHAT_IF" = true ]; then
  say "" ""
  say "📋 Preview Summary:" "$C_CYAN"
  echo "Files to be modified: $((${#CHANGED_FILES[@]} / 2))"
  echo "Total replacements: $TOTAL"
  say "" ""
  say "✅ Preview completed. Run without --what-if to apply changes." "$C_GREEN"
  exit 0
fi

# Apply changes, keeping each file's bytes, line endings and permissions.
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT
i=0
while [ "$i" -lt "${#CHANGED_FILES[@]}" ]; do
  path="${CHANGED_FILES[$i]}"
  export PATTERN="${CHANGED_FILES[$((i + 1))]}"
  i=$((i + 2))
  perl -pe 'BEGIN { ($p = $ENV{PATTERN}) =~ s/VERSION/(?:$ENV{VERSION_VALUE})/; $p =~ s/PKGNAME/\Q$ENV{PACKAGE_NAME}\E/; $re = qr/$p/ }
    s/$re/$1$ENV{NEW_VERSION}$2/g' "$path" >"$TMP_FILE"
  cat "$TMP_FILE" >"$path"
done

say "" ""
say "🎉 Version bump completed successfully!" "$C_GREEN"
echo "   Updated $((${#CHANGED_FILES[@]} / 2)) files"
echo "   Total replacements: $TOTAL"
echo "   Version: $CURRENT_VERSION → $NEW_VERSION"
say "" ""
say "💡 Add a '## [$NEW_VERSION]' entry to CHANGELOG.md, copy it to Unity-Package/Assets/root/CHANGELOG.md," "$C_CYAN"
say "   run ./commands/check-package.sh and commit." "$C_CYAN"
