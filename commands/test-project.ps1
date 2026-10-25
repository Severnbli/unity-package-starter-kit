#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Adds or removes a Unity test project and keeps the test workflow in sync.

.DESCRIPTION
    Test projects live in Unity-Tests/<unity-version> and reference the package as a local,
    testable dependency. The test workflow runs the package tests on every one of them, so
    its matrix ("unityVersion: [...]" in .github/workflows/test.yml, or test.yml-sample
    before init) is rewritten to match the folders after every change.

    -Add copies the closest existing project (preferring the same major version) and
    points it at the new editor version. Unity upgrades the project settings the first
    time the project is opened.

.PARAMETER Add
    Unity version of the project to create, e.g. "2023.2.22f1".

.PARAMETER From
    Optional. Existing project to copy for -Add. Defaults to the closest version.

.PARAMETER Remove
    Unity version of the project to delete.

.PARAMETER Sync
    Only rewrite the workflow matrix from the folders in Unity-Tests/.

.PARAMETER List
    Print the test projects and the versions the workflow tests.

.EXAMPLE
    ./commands/test-project.ps1 -Add 2023.2.22f1

.EXAMPLE
    ./commands/test-project.ps1 -Add 6000.0.58f2 -From 6000.3.1f1

.EXAMPLE
    ./commands/test-project.ps1 -Remove 2022.3.62f3

.EXAMPLE
    ./commands/test-project.ps1 -List

.NOTES
    Windows script; requires PowerShell 7+ (pwsh) and git. On macOS and Linux use
    the .sh script of the same name.
#>

[CmdletBinding(DefaultParameterSetName = "List")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Add")]
    [string]$Add,

    [Parameter(ParameterSetName = "Add")]
    [string]$From,

    [Parameter(Mandatory = $true, ParameterSetName = "Remove")]
    [string]$Remove,

    [Parameter(Mandatory = $true, ParameterSetName = "Sync")]
    [switch]$Sync,

    [Parameter(ParameterSetName = "List")]
    [switch]$List
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/Common.ps1")
# Report failures as one line, like the .sh scripts, instead of a PowerShell stack trace.
trap { Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

function Show-Projects {
    $Projects = Get-UnityTestProjects
    Write-Host "Test projects (Unity-Tests/):" -ForegroundColor Cyan
    foreach ($Project in $Projects) {
        Write-Host "  $Project"
    }
    $Workflow = Get-TestWorkflowPath
    if ($Workflow) {
        $Matrix = Get-WorkflowUnityVersions $Workflow
        $WorkflowName = [System.IO.Path]::GetRelativePath($RepoRoot, $Workflow)
        Write-Host "Tested by $($WorkflowName): $($Matrix -join ', ')" -ForegroundColor Cyan
        if (($Projects -join ',') -cne ($Matrix -join ',')) {
            Write-Warning "The workflow is out of sync. Run ./commands/test-project.ps1 -Sync"
        }
    }
}

function Sync-Workflow {
    $Workflow = Get-TestWorkflowPath
    if (-not $Workflow) {
        Write-Warning "No .github/workflows/test.yml or test.yml-sample found; nothing to update."
        return
    }
    $Projects = Get-UnityTestProjects
    if ($Projects.Count -eq 0) {
        throw "Unity-Tests/ has no projects; the workflow matrix cannot be empty."
    }
    $WorkflowName = [System.IO.Path]::GetRelativePath($RepoRoot, $Workflow)
    if (Set-WorkflowUnityVersions -WorkflowPath $Workflow -Versions $Projects) {
        Write-Host "Updated $($WorkflowName): unityVersion: [$($Projects -join ', ')]" -ForegroundColor Green
    }
    else {
        Write-Host "$WorkflowName is already up to date." -ForegroundColor Gray
    }
}

# The existing project closest to $Version: same major version first, then the nearest one.
function Get-ClosestProject {
    param([string]$Version, [string[]]$Projects)
    $Major = ($Version -split '\.')[0]
    $SameMajor = @($Projects | Where-Object { ($_ -split '\.')[0] -eq $Major })
    $Candidates = if ($SameMajor.Count -gt 0) { $SameMajor } else { $Projects }
    $Key = Get-UnityVersionKey $Version
    # Highest version below the new one, otherwise the lowest one above it.
    $Below = @($Candidates | Where-Object { (Get-UnityVersionKey $_) -lt $Key })
    if ($Below.Count -gt 0) {
        return $Below[-1]
    }
    return $Candidates[0]
}

switch ($PSCmdlet.ParameterSetName) {
    "Add" {
        if (-not (Test-UnityVersion $Add)) {
            throw "Invalid Unity version '$Add' (expected e.g. 2023.2.22f1)."
        }
        $Target = Join-Path $UnityTestsDir $Add
        if (Test-Path $Target) {
            throw "Unity-Tests/$Add already exists."
        }
        $Projects = Get-UnityTestProjects
        if (-not $From) {
            if ($Projects.Count -eq 0) {
                throw "Unity-Tests/ has no project to copy. Pass -From or create one in Unity Hub."
            }
            $From = Get-ClosestProject -Version $Add -Projects $Projects
        }
        elseif ($Projects -notcontains $From) {
            throw "Unity-Tests/$From does not exist. Existing projects: $($Projects -join ', ')"
        }
        $SourceMajor = ($From -split '\.')[0]
        $TargetMajor = ($Add -split '\.')[0]

        # Copy only what belongs in the repository, never Library/, Temp/ or other generated folders.
        Write-Host "Creating Unity-Tests/$Add from Unity-Tests/$From..." -ForegroundColor Yellow
        $SourcePrefix = "Unity-Tests/$From/"
        $SourceFiles = Get-RepositoryFiles @("Unity-Tests/$From") |
            Where-Object { Test-Path -LiteralPath (Join-Path $RepoRoot $_) }
        foreach ($File in $SourceFiles) {
            $Relative = $File.Substring($SourcePrefix.Length)
            # The lock file pins package versions of the source editor; Unity writes a new one.
            if ($Relative -eq "Packages/packages-lock.json") {
                continue
            }
            $Destination = Join-Path $Target $Relative
            New-Item -Path (Split-Path -Parent $Destination) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $RepoRoot $File) -Destination $Destination
        }

        # Point the project at the new editor. The revision is unknown here; Unity writes it on first open.
        $VersionFile = Join-Path $Target "ProjectSettings/ProjectVersion.txt"
        Write-TextFile -Path $VersionFile -Text "m_EditorVersion: $Add`n"

        # Product name and bundle identifier are named after the version.
        $SettingsFile = Join-Path $Target "ProjectSettings/ProjectSettings.asset"
        if (Test-Path $SettingsFile) {
            $Settings = Read-TextFile $SettingsFile
            Write-TextFile -Path $SettingsFile -Text $Settings.Text.Replace($From, $Add) -HasBom $Settings.HasBom
        }

        Sync-Workflow
        Write-Host "Done. Open Unity-Tests/$Add in Unity $Add once and commit the upgraded project." -ForegroundColor Green
        if ($SourceMajor -ne $TargetMajor) {
            Write-Warning "Unity-Tests/$Add was copied from a different major version ($From). Check Packages/manifest.json for packages that do not exist in Unity $Add."
        }
    }
    "Remove" {
        $Target = Join-Path $UnityTestsDir $Remove
        if (-not (Test-Path $Target)) {
            throw "Unity-Tests/$Remove does not exist. Existing projects: $((Get-UnityTestProjects) -join ', ')"
        }
        if (@(Get-UnityTestProjects | Where-Object { $_ -ne $Remove }).Count -eq 0) {
            throw "Unity-Tests/$Remove is the last test project. Add another one first: the workflow matrix cannot be empty."
        }
        Write-Host "Removing Unity-Tests/$Remove..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $Target -Recurse -Force
        Sync-Workflow
        Write-Host "Done." -ForegroundColor Green
    }
    "Sync" {
        Sync-Workflow
    }
    "List" {
        Show-Projects
    }
}
