# Helpers shared by the scripts in commands/. Dot-source it:
#   . (Join-Path $PSScriptRoot "lib/Common.ps1")

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$UnityTestsDir = Join-Path $RepoRoot "Unity-Tests"
$WorkflowsDir = Join-Path $RepoRoot ".github/workflows"

# Unity editor version, e.g. "2022.3.62f3" or "6000.3.1f1".
$UnityVersionPattern = '^(\d+)\.(\d+)\.(\d+)([abfpx])(\d+)$'

function Test-UnityVersion {
    param([string]$Version)
    return $Version -cmatch $UnityVersionPattern
}

# Sort key that orders versions numerically: 2022.3.9f1 < 2022.3.62f3 < 6000.0.1a1.
function Get-UnityVersionKey {
    param([string]$Version)
    if ($Version -cnotmatch $UnityVersionPattern) {
        throw "Not a Unity version: '$Version' (expected e.g. 2022.3.62f3)"
    }
    return '{0:D6}.{1:D4}.{2:D4}.{3}.{4:D4}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3], $Matches[4], [int]$Matches[5]
}

# Reads a text file as UTF-8 and remembers whether it had a BOM. Returns $null for binary files.
function Read-TextFile {
    param([string]$Path)
    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ([Array]::IndexOf($Bytes, [byte]0) -ge 0) {
        return $null
    }
    $HasBom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    $Offset = if ($HasBom) { 3 } else { 0 }
    return [pscustomobject]@{
        Text   = [System.Text.Encoding]::UTF8.GetString($Bytes, $Offset, $Bytes.Length - $Offset)
        HasBom = $HasBom
    }
}

# Writes text as UTF-8 without changing line endings or the BOM.
function Write-TextFile {
    param([string]$Path, [string]$Text, [bool]$HasBom = $false)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($HasBom))
}

# Test projects: every Unity-Tests/<version> folder with a ProjectVersion.txt, sorted by version.
function Get-UnityTestProjects {
    if (-not (Test-Path $UnityTestsDir)) {
        return @()
    }
    $Projects = Get-ChildItem -Path $UnityTestsDir -Directory -Force |
        Where-Object { Test-Path (Join-Path $_.FullName "ProjectSettings/ProjectVersion.txt") }
    foreach ($Project in $Projects) {
        if (-not (Test-UnityVersion $Project.Name)) {
            throw "Unity-Tests/$($Project.Name) is not named after a Unity version (e.g. 2022.3.62f3)."
        }
    }
    return @($Projects | Sort-Object { Get-UnityVersionKey $_.Name } | ForEach-Object { $_.Name })
}

# Editor version a project was saved with, or $null.
function Get-ProjectUnityVersion {
    param([string]$ProjectPath)
    $VersionFile = Join-Path $ProjectPath "ProjectSettings/ProjectVersion.txt"
    if (-not (Test-Path $VersionFile)) {
        return $null
    }
    $Content = Get-Content -Path $VersionFile -Raw
    if ($Content -match 'm_EditorVersion:\s*(\S+)') {
        return $Matches[1]
    }
    return $null
}

# test.yml before init is test.yml-sample; both carry the plugin test matrix.
function Get-TestWorkflowPath {
    foreach ($Name in @("test.yml", "test.yml-sample")) {
        $Path = Join-Path $WorkflowsDir $Name
        if (Test-Path $Path) {
            return $Path
        }
    }
    return $null
}

# The plugin matrix line: "unityVersion: [2022.3.62f3, 6000.3.1f1]".
$MatrixPattern = '(?m)^(\s*unityVersion:\s*)\[([^\]]*)\]'

function Get-WorkflowUnityVersions {
    param([string]$WorkflowPath)
    $Content = Get-Content -Path $WorkflowPath -Raw
    $Found = [regex]::Matches($Content, $MatrixPattern)
    if ($Found.Count -ne 1) {
        throw "Expected exactly one 'unityVersion: [...]' matrix in $WorkflowPath, found $($Found.Count)."
    }
    return @($Found[0].Groups[2].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Rewrites the test matrix to the given versions. Returns $true when the file changed.
function Set-WorkflowUnityVersions {
    param([string]$WorkflowPath, [string[]]$Versions)
    $File = Read-TextFile $WorkflowPath
    $null = Get-WorkflowUnityVersions $WorkflowPath
    $NewText = [regex]::Replace($File.Text, $MatrixPattern, { param($m) $m.Groups[1].Value + '[' + ($Versions -join ', ') + ']' })
    if ($NewText -ceq $File.Text) {
        return $false
    }
    Write-TextFile -Path $WorkflowPath -Text $NewText -HasBom $File.HasBom
    return $true
}

# Files git would consider part of the repository: tracked plus untracked but not ignored.
function Get-RepositoryFiles {
    param([string[]]$PathSpec)
    $Output = & git -C $RepoRoot ls-files -z --cached --others --exclude-standard -- @PathSpec
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed. Run the script inside the repository."
    }
    return @(($Output -join '') -split "`0" | Where-Object { $_ } | Sort-Object -Unique)
}
