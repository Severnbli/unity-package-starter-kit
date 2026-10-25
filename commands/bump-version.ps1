#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Automated version bumping script for Unity Package project

.DESCRIPTION
    Updates version numbers across all project files automatically to prevent human errors.
    Supports preview mode for safe testing.

.PARAMETER NewVersion
    The new version number in semver format (e.g., "0.18.0"). Run in a console without
    it, the script offers the next patch, minor, major or preview version and asks
    about -SyncDocs and -WhatIf.

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
    Windows script; runs on the built-in Windows PowerShell 5.1 or on PowerShell 7. On macOS and Linux use
    the .sh script of the same name. The package id and the
    installer location are read from the repository, so the script needs no edits
    after init.
#>

param(
    [Parameter(Mandatory = $false)]
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
$PackageName = (Read-AllText $PackageJsonPath | ConvertFrom-Json).name

# The installer folder moves and is renamed by init.ps1, so find it instead of hard-coding it.
$InstallerFiles = @(Get-ChildItem -Path "Installer/Assets" -Filter "Installer.cs" -File -Recurse -Force |
    Where-Object { (Read-AllText $_.FullName) -match 'public const string Version' })
if ($InstallerFiles.Count -ne 1) {
    Pop-Location
    throw "Expected one Installer.cs with a Version constant under Installer/Assets, found $($InstallerFiles.Count)."
}
$InstallerPath = (Get-RelativePath $InstallerFiles[0].FullName)

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

    $content = Read-AllText $packageJsonPath
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
            Write-ColorText "WARNING: File not found: $($file.Path)" "Yellow"
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

            Write-ColorText "* $($file.Description): $($regexMatches.Count) occurrence(s)" "Green"

            # Show the actual changes
            foreach ($match in $regexMatches) {
                $newValue = [regex]::Replace($match.Value, $file.Pattern, $evaluator)
                Write-ColorText "   $($match.Value) -> $newValue" "Gray"
            }
        }
        else {
            Write-ColorText "WARNING: No matches found in: $($file.Path)" "Yellow"
            Write-ColorText "   Pattern: $($file.Pattern)" "Gray"
        }
    }

    if ($changes.Count -eq 0) {
        Write-ColorText "ERROR: No version references found to update!" "Red"
        Pop-Location
        exit 1
    }

    if ($PreviewOnly) {
        Write-ColorText "`nPreview Summary:" "Cyan"
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
    Write-ColorText "Package Version Bump Script" "Cyan"
    Write-ColorText "=================================" "Cyan"

    # Without a version, offer the next ones: 1.2.3 -> 1.2.4, 1.3.0, 2.0.0, 1.2.4-preview.1;
    # a prerelease 1.3.0-preview.1 -> 1.3.0, 1.3.0-preview.2.
    if (-not $NewVersion) {
        if (-not (Test-UiEnabled)) {
            throw "-NewVersion is required (see Get-Help $PSCommandPath)."
        }
        $current = Get-CurrentVersion
        Write-UiHeader "Bump the package version (current: $current)"
        $null = $current -match '^(\d+)\.(\d+)\.(\d+)(?:-([^+]+))?'
        $major, $minor, $patch = [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]
        $prerelease = $Matches[4]
        if ($prerelease) {
            $nextPrerelease = if ($prerelease -match '^(.*?)(\d+)$') { $Matches[1] + ([int]$Matches[2] + 1) } else { "$prerelease.1" }
            $versions = @("$major.$minor.$patch", "$major.$minor.$patch-$nextPrerelease")
            $labels = @("$($versions[0])  release", "$($versions[1])  next preview")
        }
        else {
            $versions = @("$major.$minor.$($patch + 1)", "$major.$($minor + 1).0", "$($major + 1).0.0", "$major.$minor.$($patch + 1)-preview.1")
            $labels = @("$($versions[0])  patch", "$($versions[1])  minor", "$($versions[2])  major", "$($versions[3])  preview")
        }
        $choice = Read-UiSelect -Question "New version" -Options ($labels + "Other...")
        if ($choice -lt $versions.Count) {
            $NewVersion = $versions[$choice]
        }
        else {
            $NewVersion = Read-UiInput -Question "New version" -Pattern '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' -Hint "Use major.minor.patch, e.g. 1.2.3 or 1.2.3-preview.1."
        }
        if (-not $SyncDocs) {
            $choice = Read-UiSelect -Question "Copy README.md and CHANGELOG.md first?" -Options @("No", "Root -> package  ToPackage", "Package -> root  ToRoot")
            if ($choice -eq 1) { $SyncDocs = "ToPackage" }
            if ($choice -eq 2) { $SyncDocs = "ToRoot" }
        }
        if (-not $WhatIf) {
            $choice = Read-UiSelect -Question "Apply the changes?" -Options @("Apply", "Preview only  -WhatIf")
            if ($choice -eq 1) { $WhatIf = $true }
        }
        Write-Host ""
    }

    # Validate semantic version format
    if (-not (Test-SemanticVersion $NewVersion)) {
        Write-ColorText "ERROR: Invalid semantic version format: $NewVersion" "Red"
        Write-ColorText "Expected format: major.minor.patch (e.g., '1.2.3')" "Yellow"
        Pop-Location
        exit 1
    }

    # Get current version
    $currentVersion = Get-CurrentVersion
    Write-ColorText "Current version: $currentVersion" "White"
    Write-ColorText "New version: $NewVersion" "White"

    # Copy the docs first: the version replacement below then updates both copies alike.
    if ($SyncDocs) {
        $packageDir = "Unity-Package/Assets/root"
        Write-ColorText "`nCopying README.md and CHANGELOG.md $(if ($SyncDocs -eq 'ToPackage') { "to $packageDir" } else { 'to the repository root' })..." "Cyan"
        foreach ($doc in @("README.md", "CHANGELOG.md")) {
            $source, $destination = if ($SyncDocs -eq "ToPackage") { $doc, "$packageDir/$doc" } else { "$packageDir/$doc", $doc }
            if (-not (Test-Path $source)) {
                Pop-Location
                throw "File not found: $source"
            }
            Write-ColorText "   $source -> $destination" "Gray"
            if (-not $WhatIf) {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
    }

    if ($currentVersion -eq $NewVersion) {
        Write-ColorText "WARNING: New version is the same as current version" "Yellow"
        Pop-Location
        exit 0
    }

    Write-ColorText "`nScanning for version references..." "Cyan"

    # Update version files
    $changes = Update-VersionFiles -OldVersion $currentVersion -NewVersion $NewVersion -PreviewOnly $WhatIf

    if ($WhatIf) {
        Write-ColorText "`nPreview completed. Use without -WhatIf to apply changes." "Green"
        Pop-Location
        exit 0
    }

    if ($changes -and $changes.Count -gt 0) {
        Write-ColorText "`nVersion bump completed successfully!" "Green"
        Write-ColorText "   Updated $($changes.Count) files" "White"
        Write-ColorText "   Total replacements: $(($changes | Measure-Object -Property Matches -Sum).Sum)" "White"
        Write-ColorText "   Version: $currentVersion -> $NewVersion" "White"
        Write-ColorText "`nAdd a '## [$NewVersion]' entry to CHANGELOG.md, copy it to Unity-Package/Assets/root/CHANGELOG.md," "Cyan"
        Write-ColorText "   run commands\check-package.cmd and commit." "Cyan"
    }

    Pop-Location
}
catch {
    Write-ColorText "`nERROR: Script failed: $($_.Exception.Message)" "Red"
    Pop-Location
    exit 1
}