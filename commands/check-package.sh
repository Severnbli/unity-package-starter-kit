#!/usr/bin/env bash
#
# Fast consistency checks that need no Unity license (macOS and Linux; on Windows use
# check-package.ps1). CI runs them before the Unity test matrix. Checks that:
#   - every JSON, manifest and .asmdef file parses,
#   - package.json, Installer.cs and both changelogs agree on the version,
#   - the package copies of README.md and CHANGELOG.md match the root files,
#   - every package asset has a .meta file, no .meta file is orphaned, GUIDs are unique,
#   - the test workflow matrix lists exactly the projects in Unity-Tests/.
# Files are taken from git: tracked files plus untracked files that are not ignored.
# JSON is validated with the first of jq, python3 or node that is installed.
#
# Usage:
#   ./commands/check-package.sh

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

cd "$REPO_ROOT"

package_dir="Unity-Package/Assets/root"
status=0

fail() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::$*"
  else
    printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2
  fi
  status=1
}

files="$(repository_files | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done || true)"

# 1. Every JSON-based file must parse (manifests, asmdefs, fixtures).
#    VS Code settings are JSONC and allow comments, so they are skipped.
if command -v jq >/dev/null 2>&1; then
  json_valid() { jq empty "$1" >/dev/null 2>&1; }
elif command -v python3 >/dev/null 2>&1; then
  json_valid() { python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$1" >/dev/null 2>&1; }
elif command -v node >/dev/null 2>&1; then
  json_valid() { node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$1" >/dev/null 2>&1; }
else
  die "Install jq, python3 or node to validate JSON files."
fi
while IFS= read -r file; do
  [ -n "$file" ] || continue
  json_valid "$file" || fail "Invalid JSON: $file"
done < <(printf '%s\n' "$files" | grep -E '\.(json|asmdef|asmref)$' | grep -vE '(^|/)\.vscode/' || true)

# 2. The installer, changelog and package must agree on the version.
version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$package_dir/package.json" | head -n 1)"
installer_files="$(printf '%s\n' "$files" | grep -E '^Installer/Assets/(.*/)?Installer\.cs$' || true)"
installer_count="$(printf '%s' "$installer_files" | grep -c . || true)"
if [ "$installer_count" != "1" ]; then
  fail "Expected one Installer.cs under Installer/Assets, found $installer_count"
else
  installer_version="$(sed -n 's/.*public const string Version = "\([^"]*\)".*/\1/p' "$installer_files")"
  [ "$version" = "$installer_version" ] ||
    fail "Installer.Version is '$installer_version' but package.json is '$version' (run commands/bump-version.sh)"
fi
for changelog in CHANGELOG.md "$package_dir/CHANGELOG.md"; do
  grep -qF "## [$version]" "$changelog" || fail "$changelog has no '## [$version]' entry"
done

# 3. The package ships its own copies of the README and changelog (Package
#    Manager shows them); they must not drift from the repository root.
for doc in README.md CHANGELOG.md; do
  cmp -s "$doc" "$package_dir/$doc" || fail "$package_dir/$doc differs from $doc (copy the root file over it)"
done

# 4. Every package asset needs a .meta file and every .meta file needs its asset.
#    A missing .meta silently drops the file from the .unitypackage and gives it a
#    new GUID on every import. Unity ignores hidden entries and folders ending with
#    '~', so they are skipped.
package_files="$(printf '%s\n' "$files" | grep "^$package_dir/" | sed "s|^$package_dir/||" || true)"
assets="$(
  printf '%s\n' "$package_files" | grep -v '\.meta$' | while IFS= read -r rel; do
    # The asset itself and each of its parent folders.
    while [ -n "$rel" ] && [ "$rel" != "." ]; do
      echo "$rel"
      rel="$(dirname "$rel")"
    done
  done | grep -v -E '(^|/)\.|~(/|$)' | sort -u || true
)"
metas="$(printf '%s\n' "$package_files" | grep '\.meta$' | sed 's|\.meta$||' | sort -u || true)"

while IFS= read -r missing; do
  [ -n "$missing" ] && fail "Missing .meta for $package_dir/$missing"
done < <(comm -23 <(printf '%s\n' "$assets") <(printf '%s\n' "$metas"))
while IFS= read -r orphan; do
  [ -n "$orphan" ] && fail "Orphaned .meta without an asset: $package_dir/$orphan.meta"
done < <(comm -13 <(printf '%s\n' "$assets") <(printf '%s\n' "$metas"))

# 5. GUIDs must be unique, or Unity reassigns one of them on import.
duplicates="$(printf '%s\n' "$metas" | while IFS= read -r meta; do
  [ -n "$meta" ] && sed -n 's/^guid: *\([0-9a-f]\{32\}\).*/\1/p' "$package_dir/$meta.meta"
done | sort | uniq -d || true)"
[ -z "$duplicates" ] || fail "Duplicate GUIDs in $package_dir: $(printf '%s' "$duplicates" | tr '\n' ' ')"

# 6. The test matrix must cover exactly the test projects (commands/test-project.sh keeps them in sync).
workflow="$(test_workflow_path)"
if [ -n "$workflow" ]; then
  projects="$(unity_test_projects | tr '\n' ',' | sed 's/,$//')"
  matrix="$(workflow_unity_versions "$workflow" | tr '\n' ',' | sed 's/,$//')"
  [ "$projects" = "$matrix" ] ||
    fail "$(relative_path "$workflow") tests [${matrix//,/, }] but Unity-Tests/ has [${projects//,/, }] (run commands/test-project.sh --sync)"
fi

if [ "$status" -eq 0 ]; then
  say "All package checks passed (version $version)." "$C_GREEN"
fi
exit "$status"
