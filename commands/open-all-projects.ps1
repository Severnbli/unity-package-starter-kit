#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Opens all Unity projects in the repository using Unity Editor.

.DESCRIPTION
    Launches the Unity Editor of each project, reading the required version from
    ProjectSettings/ProjectVersion.txt:
    - Installer
    - Unity-Package
    - with -WithTests, also every project in Unity-Tests/

    Editors are looked up in the Unity Hub install folders of the current platform,
    including a custom install location configured in Unity Hub.

.PARAMETER EditorsPath
    Optional. Additional folder that contains editors as <version>/..., checked first.

.PARAMETER WithTests
    Optional. Also open the test projects in Unity-Tests/.

.PARAMETER Projects
    Optional. Projects to open, relative to the repository root. Defaults to all of them.

.EXAMPLE
    ./commands/open-all-projects.ps1

.EXAMPLE
    ./commands/open-all-projects.ps1 -WithTests

.EXAMPLE
    ./commands/open-all-projects.ps1 -EditorsPath "D:\Unity\Hub\Editor"

.EXAMPLE
    ./commands/open-all-projects.ps1 -Projects Unity-Package -WhatIf

.NOTES
    Windows script; runs on the built-in Windows PowerShell 5.1 or on PowerShell 7. On macOS and Linux use
    the .sh script of the same name.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$EditorsPath,

    [Parameter(Mandatory = $false)]
    [switch]$WithTests,

    [Parameter(Mandatory = $false)]
    [string[]]$Projects
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/Common.ps1")
# Report failures as one line, like the .sh scripts, instead of a PowerShell stack trace.
trap { Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

# Unity Hub stores a custom install location in secondaryInstallPath.json.
function Get-HubConfigDirectory {
    if ($OnWindows) { return Join-Path $env:APPDATA "UnityHub" }
    if ($OnMacOS) { return Join-Path $HOME "Library/Application Support/UnityHub" }
    return Join-Path $HOME ".config/UnityHub"
}

function Get-EditorRoots {
    $Roots = @()
    if ($EditorsPath) {
        $Roots += $EditorsPath
    }
    $HubConfig = Join-Path (Get-HubConfigDirectory) "secondaryInstallPath.json"
    if (Test-Path $HubConfig) {
        $Custom = Read-AllText $HubConfig | ConvertFrom-Json
        if ($Custom) {
            $Roots += [string]$Custom
        }
    }
    if ($OnWindows) {
        $Roots += @(
            (Join-Path $env:ProgramFiles "Unity/Hub/Editor"),
            "D:/Program Files/Unity/Hub/Editor",
            "D:/Unity/Hub/Editor",
            "C:/Unity/Hub/Editor"
        )
    }
    elseif ($OnMacOS) {
        $Roots += @("/Applications/Unity/Hub/Editor", (Join-Path $HOME "Applications/Unity/Hub/Editor"))
    }
    else {
        $Roots += @((Join-Path $HOME "Unity/Hub/Editor"), "/opt/Unity/Hub/Editor", "/usr/local/Unity/Hub/Editor")
    }
    return @($Roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

function Get-UnityExecutable {
    param([string[]]$Roots, [string]$Version)
    $Relative = if ($OnWindows) { "Editor/Unity.exe" }
    elseif ($OnMacOS) { "Unity.app/Contents/MacOS/Unity" }
    else { "Editor/Unity" }
    foreach ($Root in $Roots) {
        $Candidate = Join-Path (Join-Path $Root $Version) $Relative
        if (Test-Path $Candidate) {
            return $Candidate
        }
    }
    return $null
}

if (-not $Projects) {
    $Projects = @("Installer", "Unity-Package")
    if ($WithTests) {
        $Projects += @(Get-UnityTestProjects | ForEach-Object { "Unity-Tests/$_" })
    }
}

$Roots = Get-EditorRoots
if ($Roots.Count -eq 0) {
    Write-Error "No Unity editors folder found. Install editors with Unity Hub or pass -EditorsPath."
}

Write-Host "Opening Unity projects..." -ForegroundColor Cyan
Write-Host "Editors folders: $($Roots -join ', ')" -ForegroundColor Gray
Write-Host ""

$Opened = 0
foreach ($Project in $Projects) {
    $ProjectPath = Join-Path $RepoRoot $Project
    if (-not (Test-Path $ProjectPath)) {
        Write-Warning "Project not found: $Project"
        continue
    }

    $UnityVersion = Get-ProjectUnityVersion $ProjectPath
    if (-not $UnityVersion) {
        Write-Warning "No editor version in $Project/ProjectSettings/ProjectVersion.txt. Skipping."
        continue
    }

    $UnityExe = Get-UnityExecutable -Roots $Roots -Version $UnityVersion
    if (-not $UnityExe) {
        Write-Warning "Unity $UnityVersion is not installed. Skipping: $Project"
        continue
    }

    if ($PSCmdlet.ShouldProcess("$Project with $UnityExe", "Open")) {
        Write-Host "Opening: $Project (Unity $UnityVersion)" -ForegroundColor Yellow
        # One argument string with the path quoted: an argument array is not quoted per element.
        Start-Process -FilePath $UnityExe -ArgumentList "-projectPath `"$ProjectPath`""
        $Opened++
        # Delay between launches to avoid overwhelming the system
        Start-Sleep -Seconds 2
    }
}

Write-Host ""
Write-Host "Done! Opened $Opened project(s)." -ForegroundColor Green
