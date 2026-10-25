# Helpers shared by the .ps1 scripts in commands/. Dot-source it:
#   . (Join-Path $PSScriptRoot "lib/Common.ps1")
#
# Everything here and in the scripts runs on the Windows PowerShell 5.1 that ships with
# Windows (.NET Framework) as well as on PowerShell 7. Keep the .ps1 files ASCII-only:
# Windows PowerShell reads script files without a BOM in the ANSI code page.

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$UnityTestsDir = Join-Path $RepoRoot "Unity-Tests"
$WorkflowsDir = Join-Path $RepoRoot ".github/workflows"

# $IsWindows only exists in PowerShell 6+; Windows PowerShell (Desktop edition) is always Windows.
$OnWindows = ($PSVersionTable.PSEdition -ne "Core") -or $IsWindows
$OnMacOS = (-not $OnWindows) -and $IsMacOS

# Reads a whole file as UTF-8 (BOM-aware). Get-Content -Raw would use the ANSI code page
# on Windows PowerShell and break non-ASCII text.
function Read-AllText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# Path relative to the repository root, with forward slashes.
# [System.IO.Path]::GetRelativePath does not exist on .NET Framework.
function Get-RelativePath {
    param([string]$Path)
    $Full = [System.IO.Path]::GetFullPath($Path)
    $Root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    if ($Full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) -and $Full.Length -gt $Root.Length) {
        $Full = $Full.Substring($Root.Length + 1)
    }
    return $Full.Replace('\', '/')
}

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
    $Content = Read-AllText $VersionFile
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
    $Content = Read-AllText $WorkflowPath
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
# One relative path per entry, with forward slashes.
function Get-RepositoryFiles {
    param([string[]]$PathSpec)
    # git prints UTF-8; Windows PowerShell decodes native output with the console code page.
    $PreviousEncoding = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
        $Output = & git -C $RepoRoot -c core.quotePath=false ls-files --cached --others --exclude-standard -- @PathSpec
    }
    finally {
        try { [Console]::OutputEncoding = $PreviousEncoding } catch { }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed. Run the script inside the repository."
    }
    return @($Output | Where-Object { $_ } | Sort-Object -Unique -CaseSensitive)
}
