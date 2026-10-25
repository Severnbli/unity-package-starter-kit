#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Menu for all scripts in commands/.

.DESCRIPTION
    Pick a script with the arrow keys; it then asks for its parameters the same way, so
    no parameters need to be typed. The menu comes back after each script until you quit.

.EXAMPLE
    commands\menu.cmd

.NOTES
    Windows script; runs on the built-in Windows PowerShell 5.1 or on PowerShell 7. On macOS and Linux use
    the .sh script of the same name.
#>

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/Common.ps1")
# Report failures as one line, like the .sh scripts, instead of a PowerShell stack trace.
trap { Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

if (-not (Test-UiEnabled)) {
    throw "The menu needs an interactive console. Run the scripts in commands\ with parameters instead (see Get-Help)."
}

$PackageJson = Join-Path $RepoRoot "Unity-Package/Assets/root/package.json"

# "Name  description", padded so the descriptions line up.
function Format-Entry {
    param([string]$Name, [string]$Description)
    return $Name.PadRight(24) + $Description
}

while ($true) {
    $Scripts = @()
    $Labels = @()
    if ((Read-AllText $PackageJson).Contains("YOUR_PACKAGE_ID")) {
        $Scripts += "init.ps1"
        $Labels += Format-Entry "Initialize the package" "replace the template placeholders"
    }
    $Scripts += @("open-all-projects.ps1", "check-package.ps1", "test-project.ps1", "bump-version.ps1", "")
    $Labels += @(
        (Format-Entry "Open Unity projects" "generate .meta files, edit the package"),
        (Format-Entry "Check the package" "the license-free checks CI runs first"),
        (Format-Entry "Manage test projects" "add or remove tested Unity versions"),
        (Format-Entry "Bump the version" "prepare a release"),
        "Quit"
    )

    Write-UiHeader "Unity Package Starter Kit"
    $Script = $Scripts[(Read-UiSelect -Question "What do you want to do?" -Options $Labels)]
    if (-not $Script) {
        exit 0
    }

    # Each script runs in its own process, so its exit or a failure returns to the menu.
    $PowerShell = (Get-Process -Id $PID).Path
    & $PowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Script exited with status $LASTEXITCODE."
    }
    Write-Host ""
    Write-Host "Press Enter to return to the menu..." -ForegroundColor DarkGray -NoNewline
    $null = [Console]::ReadLine()
}
