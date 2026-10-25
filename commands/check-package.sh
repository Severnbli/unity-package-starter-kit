#!/usr/bin/env bash
# Fast consistency checks that need no Unity license. CI runs them before the
# Unity test matrix; run them locally from anywhere inside the repository:
#   bash commands/check-package.sh
set -euo pipefail
# sort and comm must agree on the collation order.
export LC_ALL=C

cd "$(git rev-parse --show-toplevel)"

package_dir="Unity-Package/Assets/root"
installer_cs="Installer/Assets/YOUR_PACKAGE_NAME_INSTALLER/Installer.cs"
status=0

fail() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::$*"
  else
    echo "error: $*" >&2
  fi
  status=1
}

# 1. Every tracked JSON-based file must parse (manifests, asmdefs, fixtures).
#    VS Code settings are JSONC and allow comments, so they are skipped.
while IFS= read -r -d '' file; do
  jq empty "$file" 2>/dev/null || fail "Invalid JSON: $file"
done < <(git ls-files -z -- '*.json' '*.asmdef' ':!:**/.vscode/**')

# 2. The installer, changelog and package must agree on the version.
version="$(jq -r .version "$package_dir/package.json")"
installer_version="$(sed -n 's/.*public const string Version = "\([^"]*\)".*/\1/p' "$installer_cs")"
[ "$version" = "$installer_version" ] ||
  fail "Installer.Version is '$installer_version' but package.json is '$version' (run commands/bump-version.ps1)"
for changelog in CHANGELOG.md "$package_dir/CHANGELOG.md"; do
  grep -q "^## \[$version\]" "$changelog" || fail "$changelog has no '## [$version]' entry"
done

# 3. The package ships its own copies of the README and changelog (Package
#    Manager shows them); they must not drift from the repository root.
for doc in README.md CHANGELOG.md; do
  cmp -s "$doc" "$package_dir/$doc" || fail "$package_dir/$doc differs from $doc (copy the root file over it)"
done

# 4. Every package asset needs a committed .meta file and every .meta file needs
#    its asset. A missing .meta silently drops the file from the .unitypackage
#    and gives it a new GUID on every import. Unity ignores hidden entries and
#    folders ending with '~', so they are skipped.
tracked="$(git ls-files -- "$package_dir")"
assets="$(
  while IFS= read -r path; do
    rel="${path#"$package_dir"/}"
    # The asset itself and each of its parent folders.
    while [ -n "$rel" ] && [ "$rel" != "." ]; do
      echo "$rel"
      rel="$(dirname "$rel")"
    done
  done <<<"$tracked" | grep -v -E '(^|/)\.|~(/|$)|\.meta$' | sort -u
)"
metas="$({ grep -E '\.meta$' <<<"$tracked" || true; } | sed "s|^$package_dir/||; s|\.meta\$||" | sort -u)"

while IFS= read -r missing; do
  [ -n "$missing" ] && fail "Missing .meta for $package_dir/$missing"
done < <(comm -23 <(echo "$assets") <(echo "$metas"))
while IFS= read -r orphan; do
  [ -n "$orphan" ] && fail "Orphaned .meta without an asset: $package_dir/$orphan.meta"
done < <(comm -13 <(echo "$assets") <(echo "$metas"))

# 5. GUIDs must be unique, or Unity reassigns one of them on import.
duplicates="$(git ls-files -z -- "$package_dir/*.meta" |
  xargs -0 sed -n 's/^guid: *\([0-9a-f]\{32\}\).*/\1/p' | sort | uniq -d)"
[ -z "$duplicates" ] || fail "Duplicate GUIDs in $package_dir: $duplicates"

if [ "$status" -eq 0 ]; then
  echo "All package checks passed (version $version)."
fi
exit "$status"
