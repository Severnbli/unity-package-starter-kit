#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Automated version bumping script for Unity Package project

.DESCRIPTION
    Updates version numbers across all project files automatically to prevent human errors.
    Supports preview mode for safe testing.

.PARAMETER NewVersion
    The new version number in semver format (e.g., "0.18.0")

.PARAMETER WhatIf
    Preview changes without applying them

.PARAMETER SyncDocs
    Optional. Copy README.md and CHANGELOG.md before bumping, so the root and package
    copies are identical:
    - ToPackage: from the repository root to Unity-Package/Assets/root
    - ToRoot: from Unity-Package/Assets/root to the repository root

.EXAMPLE
    ./commands/bump-version.ps1 -NewVersion "0.18.0"

.EXAMPLE
    ./commands/bump-version.ps1 -NewVersion "0.18.0" -WhatIf

.EXAMPLE
    ./commands/bump-version.ps1 -NewVersion "0.18.0" -SyncDocs ToPackage

.NOTES
    Windows script; requires PowerShell 7+ (pwsh). On macOS and Linux use
    the .sh script of the same name. The package id and the
    installer location are read from the repository, so the script needs no edits
    after init.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$NewVersion,

    [switch]$WhatIf,

    [ValidateSet("ToPackage", "ToRoot")]
    [string]$SyncDocs
)

# Script configuration
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/Common.ps1")
# Report failures as one line, like the .sh scripts, instead of a PowerShell stack trace.
trap { Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
Push-Location $RepoRoot

# A version as written in the files: 1.2.3, 1.2.3-preview.1, 1.2.3+build.5
$VersionValue = '\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?'

$PackageJsonPath = "Unity-Package/Assets/root/package.json"
$PackageName = (Get-Content -Path $PackageJsonPath -Raw | ConvertFrom-Json).name

# The installer folder moves and is renamed by init.ps1, so find it instead of hard-coding it.
$InstallerFiles = @(Get-ChildItem -Path "Installer/Assets" -Filter "Installer.cs" -File -Recurse -Force |
    Where-Object { (Get-Content -Path $_.FullName -Raw) -match 'public const string Version' })
if ($InstallerFiles.Count -ne 1) {
    Pop-Location
    throw "Expected one Installer.cs with a Version constant under Installer/Assets, found $($InstallerFiles.Count)."
}
$InstallerPath = [System.IO.Path]::GetRelativePath($RepoRoot, $InstallerFiles[0].FullName)

# Version file locations (relative to the repository root)
$EscapedName = [regex]::Escape($PackageName)
$VersionFiles = @(
    @{
        Path        = $PackageJsonPath
        Pattern     = "(""version"":\s*"")$VersionValue("")"
        Description = "Unity package version"
    },
    @{
        Path        = $InstallerPath
        Pattern     = "(public const string Version = "")$VersionValue("";)"
        Description = "Installer C# version constant"
    },
    @{
        Path        = "Unity-Package/Assets/root/README.md"
        Pattern     = "(""$EscapedName"":\s*"")$VersionValue("")"
        Description = "Package README manual install version"
    },
    @{
        Path        = "README.md"
        Pattern     = "(""$EscapedName"":\s*"")$VersionValue("")"
        Description = "Repository README manual install version"
    }
)

function Write-ColorText {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Test-SemanticVersion {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $false
    }

    # Basic semver pattern: major.minor.patch (with optional prerelease/build)
    $pattern = '^\d+\.\d+\.\d+(-[a-zA-Z0-9\-\.]+)?(\+[a-zA-Z0-9\-\.]+)?$'
    return $Version -match $pattern
}

function Get-CurrentVersion {
    # Extract current version from package.json
    $packageJsonPath = "Unity-Package/Assets/root/package.json"
    if (-not (Test-Path $packageJsonPath)) {
        throw "Could not find package.json at: $packageJsonPath"
    }

    $content = Get-Content $packageJsonPath -Raw
    if ($content -match """version"":\s*""($VersionValue)""") {
        return $Matches[1]
    }

    throw "Could not extract current version from package.json"
}

function Update-VersionFiles {
    param([string]$OldVersion, [string]$NewVersion, [bool]$PreviewOnly = $false)

    $changes = @()

    foreach ($file in $VersionFiles) {
        $fullPath = $file.Path

        if (-not (Test-Path $fullPath)) {
            Write-ColorText "⚠️  File not found: $($file.Path)" "Yellow"
            continue
        }

        $file.Text = Read-TextFile $fullPath
        $content = $file.Text.Text
        $originalContent = $content

        # Keep the text around the version (groups 1 and 2), swap only the version.
        $evaluator = { param($m) $m.Groups[1].Value + $NewVersion + $m.Groups[2].Value }
        $newContent = [regex]::Replace($content, $file.Pattern, $evaluator)

        # Check if any changes were made
        if ($originalContent -ne $newContent) {
            # Count matches for reporting
            $regexMatches = [regex]::Matches($originalContent, $file.Pattern)

            $changes += @{
                Path            = $file.Path
                Description     = $file.Description
                Matches         = $regexMatches.Count
                Content         = $newContent
                HasBom          = $file.Text.HasBom
                OriginalContent = $originalContent
            }

            Write-ColorText "📝 $($file.Description): $($regexMatches.Count) occurrence(s)" "Green"

            # Show the actual changes
            foreach ($match in $regexMatches) {
                $newValue = [regex]::Replace($match.Value, $file.Pattern, $evaluator)
                Write-ColorText "   $($match.Value) → $newValue" "Gray"
            }
        }
        else {
            Write-ColorText "⚠️  No matches found in: $($file.Path)" "Yellow"
            Write-ColorText "   Pattern: $($file.Pattern)" "Gray"
        }
    }

    if ($changes.Count -eq 0) {
        Write-ColorText "❌ No version references found to update!" "Red"
        Pop-Location
        exit 1
    }

    if ($PreviewOnly) {
        Write-ColorText "`n📋 Preview Summary:" "Cyan"
        Write-ColorText "Files to be modified: $($changes.Count)" "White"
        Write-ColorText "Total replacements: $(($changes | Measure-Object -Property Matches -Sum).Sum)" "White"
        return $null
    }

    # Apply changes
    foreach ($change in $changes) {
        $fullPath = $change.Path
        Write-TextFile -Path $fullPath -Text $change.Content -HasBom $change.HasBom
    }

    return $changes
}

# Main execution
try {
    Write-ColorText "🚀 Package Version Bump Script" "Cyan"
    Write-ColorText "=================================" "Cyan"

    # Validate semantic version format
    if (-not (Test-SemanticVersion $NewVersion)) {
        Write-ColorText "❌ Invalid semantic version format: $NewVersion" "Red"
        Write-ColorText "Expected format: major.minor.patch (e.g., '1.2.3')" "Yellow"
        Pop-Location
        exit 1
    }

    # Get current version
    $currentVersion = Get-CurrentVersion
    Write-ColorText "📋 Current version: $currentVersion" "White"
    Write-ColorText "📋 New version: $NewVersion" "White"

    # Copy the docs first: the version replacement below then updates both copies alike.
    if ($SyncDocs) {
        $packageDir = "Unity-Package/Assets/root"
        Write-ColorText "`n📄 Copying README.md and CHANGELOG.md $(if ($SyncDocs -eq 'ToPackage') { "to $packageDir" } else { 'to the repository root' })..." "Cyan"
        foreach ($doc in @("README.md", "CHANGELOG.md")) {
            $source, $destination = if ($SyncDocs -eq "ToPackage") { $doc, "$packageDir/$doc" } else { "$packageDir/$doc", $doc }
            if (-not (Test-Path $source)) {
                Pop-Location
                throw "File not found: $source"
            }
            Write-ColorText "   $source → $destination" "Gray"
            if (-not $WhatIf) {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
    }

    if ($currentVersion -eq $NewVersion) {
        Write-ColorText "⚠️  New version is the same as current version" "Yellow"
        Pop-Location
        exit 0
    }

    Write-ColorText "`n🔍 Scanning for version references..." "Cyan"

    # Update version files
    $changes = Update-VersionFiles -OldVersion $currentVersion -NewVersion $NewVersion -PreviewOnly $WhatIf

    if ($WhatIf) {
        Write-ColorText "`n✅ Preview completed. Use without -WhatIf to apply changes." "Green"
        Pop-Location
        exit 0
    }

    if ($changes -and $changes.Count -gt 0) {
        Write-ColorText "`n🎉 Version bump completed successfully!" "Green"
        Write-ColorText "   Updated $($changes.Count) files" "White"
        Write-ColorText "   Total replacements: $(($changes | Measure-Object -Property Matches -Sum).Sum)" "White"
        Write-ColorText "   Version: $currentVersion → $NewVersion" "White"
        Write-ColorText "`n💡 Add a '## [$NewVersion]' entry to CHANGELOG.md, copy it to Unity-Package/Assets/root/CHANGELOG.md," "Cyan"
        Write-ColorText "   run ./commands/check-package.ps1 and commit." "Cyan"
    }

    Pop-Location
}
catch {
    Write-ColorText "`n❌ Script failed: $($_.Exception.Message)" "Red"
    Pop-Location
    exit 1
}