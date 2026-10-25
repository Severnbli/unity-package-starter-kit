#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Fast consistency checks that need no Unity license.

.DESCRIPTION
    CI runs them before the Unity test matrix. Checks that:
    - every JSON, manifest and .asmdef file parses,
    - package.json, Installer.cs and both changelogs agree on the version,
    - the package copies of README.md and CHANGELOG.md match the root files,
    - every package asset has a .meta file, no .meta file is orphaned, GUIDs are unique,
    - the test workflow matrix lists exactly the projects in Unity-Tests/.

    Files are taken from git: tracked files plus untracked files that are not ignored.

.EXAMPLE
    ./commands/check-package.ps1

.NOTES
    Windows script; requires PowerShell 7+ (pwsh) and git. On macOS and Linux use
    the .sh script of the same name.
#>

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/Common.ps1")
# Report failures as one line, like the .sh scripts, instead of a PowerShell stack trace.
trap { Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

$PackageDir = "Unity-Package/Assets/root"
$script:Failed = $false

function Fail {
    param([string]$Message)
    if ($env:GITHUB_ACTIONS) {
        Write-Host "::error::$Message"
    }
    else {
        Write-Host "error: $Message" -ForegroundColor Red
    }
    $script:Failed = $true
}

function Get-RepoPath {
    param([string]$Relative)
    return Join-Path $RepoRoot $Relative
}

$Files = @(Get-RepositoryFiles | Where-Object { Test-Path -LiteralPath (Get-RepoPath $_) })

# 1. Every JSON-based file must parse (manifests, asmdefs, fixtures). System.Text.Json is
#    strict: no comments, no trailing commas. VS Code settings are JSONC, so they are skipped.
foreach ($File in $Files | Where-Object { $_ -match '\.(json|asmdef|asmref)$' -and $_ -notmatch '(^|/)\.vscode/' }) {
    try {
        $Document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText((Get-RepoPath $File)))
        $Document.Dispose()
    }
    catch {
        Fail "Invalid JSON: $File ($($_.Exception.InnerException.Message ?? $_.Exception.Message))"
    }
}

# 2. The installer, changelog and package must agree on the version.
$Version = (Get-Content -Path (Get-RepoPath "$PackageDir/package.json") -Raw | ConvertFrom-Json).version
$InstallerFiles = @($Files | Where-Object { $_ -like "Installer/Assets/*" -and (Split-Path $_ -Leaf) -eq "Installer.cs" })
if ($InstallerFiles.Count -ne 1) {
    Fail "Expected one Installer.cs under Installer/Assets, found $($InstallerFiles.Count)"
}
else {
    $InstallerText = Get-Content -Path (Get-RepoPath $InstallerFiles[0]) -Raw
    $InstallerVersion = if ($InstallerText -match 'public const string Version = "([^"]*)"') { $Matches[1] } else { "" }
    if ($InstallerVersion -cne $Version) {
        Fail "Installer.Version is '$InstallerVersion' but package.json is '$Version' (run commands/bump-version.ps1)"
    }
}
foreach ($Changelog in @("CHANGELOG.md", "$PackageDir/CHANGELOG.md")) {
    $Heading = '(?m)^## \[' + [regex]::Escape($Version) + '\]'
    if ((Get-Content -Path (Get-RepoPath $Changelog) -Raw) -cnotmatch $Heading) {
        Fail "$Changelog has no '## [$Version]' entry"
    }
}

# 3. The package ships its own copies of the README and changelog (Package Manager shows
#    them); they must not drift from the repository root.
foreach ($Doc in @("README.md", "CHANGELOG.md")) {
    $Root = [System.IO.File]::ReadAllBytes((Get-RepoPath $Doc))
    $Copy = [System.IO.File]::ReadAllBytes((Get-RepoPath "$PackageDir/$Doc"))
    if (-not [System.Linq.Enumerable]::SequenceEqual($Root, $Copy)) {
        Fail "$PackageDir/$Doc differs from $Doc (copy the root file over it)"
    }
}

# 4. Every package asset needs a .meta file and every .meta file needs its asset. A missing
#    .meta silently drops the file from the .unitypackage and gives it a new GUID on every
#    import. Unity ignores hidden entries and folders ending with '~', so they are skipped.
$PackageFiles = @($Files | Where-Object { $_.StartsWith("$PackageDir/", [StringComparison]::Ordinal) } |
    ForEach-Object { $_.Substring($PackageDir.Length + 1) })
$Assets = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
$Metas = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
foreach ($Relative in $PackageFiles) {
    if ($Relative.EndsWith(".meta", [StringComparison]::Ordinal)) {
        $null = $Metas.Add($Relative.Substring(0, $Relative.Length - 5))
        continue
    }
    # The asset itself and each of its parent folders.
    $Parts = $Relative -split '/'
    for ($i = 1; $i -le $Parts.Count; $i++) {
        $Segment = $Parts[$i - 1]
        if ($Segment.StartsWith('.') -or $Segment.EndsWith('~')) {
            break
        }
        $null = $Assets.Add(($Parts[0..($i - 1)] -join '/'))
    }
}
foreach ($Missing in $Assets | Where-Object { -not $Metas.Contains($_) }) {
    Fail "Missing .meta for $PackageDir/$Missing"
}
foreach ($Orphan in $Metas | Where-Object { -not $Assets.Contains($_) }) {
    Fail "Orphaned .meta without an asset: $PackageDir/$Orphan.meta"
}

# 5. GUIDs must be unique, or Unity reassigns one of them on import.
$Guids = @{}
foreach ($Meta in $Metas) {
    $MetaPath = "$PackageDir/$Meta.meta"
    $Text = Get-Content -Path (Get-RepoPath $MetaPath) -Raw
    if ($Text -notmatch '(?m)^guid:\s*([0-9a-f]{32})') {
        Fail "No GUID in $MetaPath"
        continue
    }
    $Guid = $Matches[1]
    if ($Guids.ContainsKey($Guid)) {
        Fail "Duplicate GUID $Guid in $($Guids[$Guid]) and $MetaPath"
    }
    else {
        $Guids[$Guid] = $MetaPath
    }
}

# 6. The test matrix must cover exactly the test projects (commands/test-project.ps1 keeps them in sync).
$Workflow = Get-TestWorkflowPath
if ($Workflow) {
    $Projects = Get-UnityTestProjects
    $Matrix = Get-WorkflowUnityVersions $Workflow
    if (($Projects -join ',') -cne ($Matrix -join ',')) {
        $WorkflowName = [System.IO.Path]::GetRelativePath($RepoRoot, $Workflow)
        Fail "$WorkflowName tests [$($Matrix -join ', ')] but Unity-Tests/ has [$($Projects -join ', ')] (run commands/test-project.ps1 -Sync)"
    }
}

if ($script:Failed) {
    exit 1
}
Write-Host "All package checks passed (version $Version)." -ForegroundColor Green
