#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes the Unity Package project by replacing placeholders.

.DESCRIPTION
    Replaces placeholders in file content, filenames, and directory names.
    Placeholders:
    - YOUR_PACKAGE_ID
    - YOUR_PACKAGE_ID_LOWERCASE
    - YOUR_PACKAGE_NAME
    - YOUR_PACKAGE_NAME_PASCAL
    - YOUR_PACKAGE_NAME_INSTALLER
    - YOUR_PACKAGE_NAME_INSTALLER_FILE
    - YOUR_ROOT_NAMESPACE
    - YOUR_GITHUB_USERNAME_REPOSITORY

    Afterwards it enables the sample workflows and replaces the template README
    with the package README.

.PARAMETER PackageId
    The package ID (e.g., "com.company.package").

.PARAMETER PackageName
    The package name (e.g., "My Package").

.PARAMETER RootNamespace
    Optional. The C# root namespace (e.g., "Company.CoolPackage").
    Package IDs may contain characters that are not valid in a namespace, so it is
    derived from them by default: "com.mycompany.cool-package" with the name
    "Cool Package" becomes "Mycompany.CoolPackage".

.PARAMETER InstallerExtraPath
    Optional. An extra path segment between Assets/ and the Installer folder.
    For example, "Editor" places the installer at Assets/Editor/{Package} Installer.
    If not provided, you will be prompted (press Enter to skip).

    Run in a console, the script asks for every parameter that was not passed, with
    defaults taken from the git remote, so "commands\init.cmd" alone is enough.

.PARAMETER GitHubRepository
    The GitHub username and repository name in the format "Username/Repository-Name".
    For example, "MyGitHubUsername/My-Repository-Name".

.EXAMPLE
    ./commands/init.ps1 -PackageId "com.mycompany.cool-package" -PackageName "Cool Package" -GitHubRepository "myusername/cool-package"

.EXAMPLE
    ./commands/init.ps1 -PackageId "com.mycompany.cool-package" -PackageName "Cool Package" -GitHubRepository "myusername/cool-package" -InstallerExtraPath "Editor"

.NOTES
    Windows script; runs on the built-in Windows PowerShell 5.1 or on PowerShell 7. On macOS and Linux use
    the .sh script of the same name. Run it once, on a
    fresh copy of the template.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$PackageId,

    [Parameter(Mandatory = $false)]
    [string]$PackageName,

    [Parameter(Mandatory = $false)]
    [string]$RootNamespace,

    [Parameter(Mandatory = $false)]
    [string]$InstallerExtraPath,

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepository
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/Common.ps1")
# Report failures as one line, like the .sh scripts, instead of a PowerShell stack trace.
trap { Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

# Refuse to run twice: the second run would find no placeholders and only overwrite README.md.
$PackageJson = Join-Path $RepoRoot "Unity-Package/Assets/root/package.json"
if (-not (Read-AllText $PackageJson).Contains("YOUR_PACKAGE_ID")) {
    throw "The template is already initialized: $PackageJson has no placeholders left."
}

$PackageIdPattern = '^[a-z0-9_-]+(\.[a-z0-9_-]+){2,}$'
$GitHubRepositoryPattern = '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$'
$NamespacePattern = '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$'

# "Cool Package" -> "CoolPackage", "cool-package" -> "CoolPackage"
function ConvertTo-PascalCase {
    param([string]$Text)
    $Words = $Text -split '[^A-Za-z0-9]+' | Where-Object { $_ }
    return ($Words | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ''
}

# Skip the reverse-domain prefix ("com", "org", ...) and use the company segment:
# "com.mycompany.cool-package" + "Cool Package" -> "Mycompany.CoolPackage".
function Get-DefaultRootNamespace {
    param([string]$Id, [string]$Name)
    $IdSegments = $Id.ToLower() -split '\.'
    $Company = if ($IdSegments.Count -ge 3) { ConvertTo-PascalCase $IdSegments[1] } else { "" }
    return (@($Company, (ConvertTo-PascalCase $Name)) | Where-Object { $_ }) -join '.'
}

# Ask for everything that was not passed. Defaults come from the git remote:
# github.com/User/cool-package -> "User/cool-package", "Cool Package", "com.user.cool-package".
$Asked = $false
if ((Test-UiEnabled) -and (-not $PackageId -or -not $PackageName -or -not $GitHubRepository)) {
    $AskAll = $PSBoundParameters.Count -eq 0
    $Asked = $true
    Write-UiHeader "Initialize the package"

    $RemoteSlug = ""
    try {
        $RemoteUrl = [string](& git -C $RepoRoot remote get-url origin 2>$null)
        if ($RemoteUrl -match 'github\.com[:/]([^/]+/[^/]+?)(\.git)?$' -and $Matches[1] -match $GitHubRepositoryPattern) {
            $RemoteSlug = $Matches[1]
        }
    }
    catch { }
    if (-not $GitHubRepository) {
        $GitHubRepository = Read-UiInput -Question "GitHub repository" -Default $RemoteSlug -Pattern $GitHubRepositoryPattern -Hint "Use 'Username/Repository-Name'."
    }

    $Owner, $RepositoryName = $GitHubRepository -split '/', 2
    if (-not $PackageName) {
        $DefaultName = ((($RepositoryName -split '[-_.]+') | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ' ')
        $PackageName = Read-UiInput -Question "Package display name" -Default $DefaultName -Pattern '\S' -Hint "Enter a name."
    }
    if (-not $PackageId) {
        $IdPart = { param($Text) (($Text.ToLower() -replace '[^a-z0-9_-]+', '-').Trim('-')) }
        $DefaultId = "com.$(& $IdPart $Owner).$(& $IdPart $PackageName)"
        $PackageId = Read-UiInput -Question "Package id" -Default $DefaultId -Pattern $PackageIdPattern -Hint "Use a lowercase reverse-domain name such as 'com.company.cool-package'."
    }
    if ($AskAll) {
        $RootNamespace = Read-UiInput -Question "C# root namespace" -Default (Get-DefaultRootNamespace $PackageId $PackageName) -Pattern $NamespacePattern -Hint "Use a C# namespace such as 'Company.CoolPackage'."
    }
}

foreach ($Required in @("PackageId", "PackageName", "GitHubRepository")) {
    if (-not (Get-Variable -Name $Required -ValueOnly)) {
        throw "-$Required is required (see Get-Help $PSCommandPath)."
    }
}

# Package Manager accepts lowercase reverse-domain names only.
if ($PackageId -cnotmatch $PackageIdPattern) {
    throw "Invalid package id '$PackageId'. Use a lowercase reverse-domain name such as 'com.company.cool-package'."
}
if ($GitHubRepository -notmatch $GitHubRepositoryPattern) {
    throw "Invalid GitHub repository '$GitHubRepository'. Use 'Username/Repository-Name'."
}

# Ask for InstallerExtraPath if not provided
if (-not $PSBoundParameters.ContainsKey('InstallerExtraPath')) {
    if (Test-UiEnabled) {
        $Asked = $true
        $Choice = Read-UiSelect -Question "Installer location" -Options @(
            "Installer/Assets/Editor/$PackageName Installer",
            "Installer/Assets/$PackageName Installer",
            "Another folder..."
        )
        $InstallerExtraPath = switch ($Choice) {
            0 { "Editor" }
            1 { "" }
            2 { Read-UiInput -Question "Folder between Assets/ and the installer folder" -Pattern '^([^\\/].*)?$' -Hint "Use a relative path such as 'Editor/Tools'." }
        }
    }
    else {
        Write-Host "Optional: Enter an extra path for the Installer (e.g., 'Editor')." -ForegroundColor Cyan
        Write-Host "Press Enter to skip." -ForegroundColor Gray
        $InstallerExtraPath = Read-Host "Installer Extra Path"
    }
}

# Normalize InstallerExtraPath
if (-not [string]::IsNullOrWhiteSpace($InstallerExtraPath)) {
    $InstallerExtraPath = ($InstallerExtraPath.Trim() -replace '\\', '/').TrimStart('/').TrimEnd('/')
}

# Derived variables
$PackageIdLowercase = $PackageId.ToLower()

$PackageNamePascal = ConvertTo-PascalCase $PackageName
if ([string]::IsNullOrWhiteSpace($RootNamespace)) {
    $RootNamespace = Get-DefaultRootNamespace $PackageId $PackageName
}
if ($RootNamespace -notmatch $NamespacePattern) {
    throw "Invalid root namespace '$RootNamespace'. Pass a valid C# namespace with -RootNamespace."
}

# Compute base installer name and file name first
$PackageNameInstallerBase = "$PackageName Installer"
$PackageNameInstallerFile = $PackageNameInstallerBase -replace ' ', '-'  # Stays unchanged (no path prefix)

# Prepend extra path to installer name if provided
if ([string]::IsNullOrWhiteSpace($InstallerExtraPath)) {
    $PackageNameInstaller = $PackageNameInstallerBase
}
else {
    $PackageNameInstaller = "$InstallerExtraPath/$PackageNameInstallerBase"
}

# Replacements map for file content (includes extra path in installer name)
$Replacements = @{
    "YOUR_PACKAGE_ID"                  = $PackageId
    "YOUR_PACKAGE_ID_LOWERCASE"        = $PackageIdLowercase
    "YOUR_PACKAGE_NAME"                = $PackageName
    "YOUR_PACKAGE_NAME_PASCAL"         = $PackageNamePascal
    "YOUR_ROOT_NAMESPACE"              = $RootNamespace
    "YOUR_PACKAGE_NAME_INSTALLER_FILE" = $PackageNameInstallerFile
    "YOUR_PACKAGE_NAME_INSTALLER"      = $PackageNameInstaller
    "YOUR_GITHUB_USERNAME_REPOSITORY"  = $GitHubRepository
}

# Replacements map for file/folder renaming (uses base names without extra path)
$ReplacementsForRenaming = @{
    "YOUR_PACKAGE_ID"                  = $PackageId
    "YOUR_PACKAGE_ID_LOWERCASE"        = $PackageIdLowercase
    "YOUR_PACKAGE_NAME"                = $PackageName
    "YOUR_PACKAGE_NAME_PASCAL"         = $PackageNamePascal
    "YOUR_ROOT_NAMESPACE"              = $RootNamespace
    "YOUR_PACKAGE_NAME_INSTALLER_FILE" = $PackageNameInstallerFile
    "YOUR_PACKAGE_NAME_INSTALLER"      = $PackageNameInstallerBase
    "YOUR_GITHUB_USERNAME_REPOSITORY"  = $GitHubRepository
}

# Sort keys by length descending to avoid partial replacements
$SortedKeys = $Replacements.Keys | Sort-Object { $_.Length } -Descending

Write-Host "Initializing package with:" -ForegroundColor Cyan
Write-Host "  ID: $PackageId"
Write-Host "  Name: $PackageName"
Write-Host "  Root Namespace: $RootNamespace"
Write-Host "  Installer: $PackageNameInstaller"
Write-Host "  Installer File: $PackageNameInstallerFile"
Write-Host "  GitHub Repository: $GitHubRepository"
if (-not [string]::IsNullOrWhiteSpace($InstallerExtraPath)) {
    Write-Host "  Installer Extra Path: $InstallerExtraPath"
}
Write-Host ""
if ($Asked -and -not (Read-UiConfirm "Initialize with these values?")) {
    Write-Host "Cancelled, nothing was changed." -ForegroundColor Yellow
    exit 0
}

# Folders that get placeholders replaced, with the folders to skip inside them.
# Unity's generated folders can be huge and must never be rewritten.
$UnityGenerated = @("Library", "Temp", "Logs", "obj", "UserSettings", "Build", "Builds", ".vs", ".idea")
$TargetPaths = @(
    @{ Path = "Installer"; Skip = $UnityGenerated },
    @{ Path = "Unity-Package"; Skip = $UnityGenerated },
    @{ Path = "Unity-Tests"; Skip = $UnityGenerated; SkipDepth = 1 },
    @{ Path = "README.md" },
    @{ Path = "CHANGELOG.md" },
    @{ Path = "docs" },
    @{ Path = ".github" }
)

# All files and folders below a target, without the skipped folders.
# -Force is required: on macOS and Linux every dot-prefixed item (.github, .gitignore) is hidden.
function Get-TargetItems {
    param([hashtable]$Target)
    $Root = Join-Path $RepoRoot $Target.Path
    if (-not (Test-Path $Root)) {
        Write-Warning "Path not found: $Root"
        return
    }
    $RootItem = Get-Item -Path $Root -Force
    if (-not $RootItem.PSIsContainer) {
        return $RootItem
    }

    # Skip names apply directly inside the project folder (SkipDepth 0) or inside each
    # project of a folder of projects (SkipDepth 1, Unity-Tests/<version>/Library).
    $SkipDepth = if ($Target.SkipDepth) { $Target.SkipDepth } else { 0 }
    $Pending = [System.Collections.Generic.Stack[object]]::new()
    $Pending.Push(@($RootItem, 0))
    while ($Pending.Count -gt 0) {
        $Directory, $Depth = $Pending.Pop()
        foreach ($Child in Get-ChildItem -LiteralPath $Directory.FullName -Force) {
            if ($Child.PSIsContainer) {
                if ($Child.Name -eq ".git") { continue }
                if ($Target.Skip -and $Depth -eq $SkipDepth -and $Target.Skip -contains $Child.Name) { continue }
                $Pending.Push(@($Child, ($Depth + 1)))
            }
            $Child
        }
    }
}

function Get-AllTargetItems {
    foreach ($Target in $TargetPaths) {
        Get-TargetItems $Target
    }
}

# Ordinal, case-sensitive replacement: placeholders are literal text, not patterns.
function Edit-Placeholders {
    param([string]$Text, [hashtable]$Map)
    foreach ($Key in $SortedKeys) {
        $Text = $Text.Replace($Key, $Map[$Key])
    }
    return $Text
}

# 1. Replace content in files
Write-Host "Replacing content in files..." -ForegroundColor Yellow
foreach ($File in Get-AllTargetItems | Where-Object { -not $_.PSIsContainer }) {
    $Content = Read-TextFile $File.FullName
    if ($null -eq $Content) {
        continue
    }
    $NewText = Edit-Placeholders $Content.Text $Replacements
    if ($NewText -cne $Content.Text) {
        Write-TextFile -Path $File.FullName -Text $NewText -HasBom $Content.HasBom
        Write-Host "  Updated: $((Get-RelativePath $File.FullName))" -ForegroundColor Gray
    }
}

# 1.5. Create extra path folders and move installer (if extra path provided)
if (-not [string]::IsNullOrWhiteSpace($InstallerExtraPath)) {
    Write-Host "Creating extra path and moving installer folder..." -ForegroundColor Yellow
    $InstallerAssetsDir = Join-Path $RepoRoot "Installer/Assets"
    $SourceFolder = Join-Path $InstallerAssetsDir "YOUR_PACKAGE_NAME_INSTALLER"
    $ExtraPathDir = Join-Path $InstallerAssetsDir $InstallerExtraPath

    # Create extra path directories
    if (-not (Test-Path $ExtraPathDir)) {
        New-Item -Path $ExtraPathDir -ItemType Directory -Force | Out-Null
        Write-Host "  Created: $ExtraPathDir" -ForegroundColor Gray
    }

    # Move installer folder
    if (Test-Path $SourceFolder) {
        $DestFolder = Join-Path $ExtraPathDir "YOUR_PACKAGE_NAME_INSTALLER"
        Move-Item -LiteralPath $SourceFolder -Destination $DestFolder -Force
        Write-Host "  Moved installer to: $InstallerExtraPath/" -ForegroundColor Gray
    }
}

# 2. Rename files and directories
# Deepest paths first, so a folder is renamed only after everything inside it.
Write-Host "Renaming files and directories..." -ForegroundColor Yellow
$Items = Get-AllTargetItems | Sort-Object -Property { $_.FullName.Length } -Descending
foreach ($Item in $Items) {
    $NewName = Edit-Placeholders $Item.Name $ReplacementsForRenaming
    if ($NewName -cne $Item.Name) {
        Rename-Item -LiteralPath $Item.FullName -NewName $NewName
        Write-Host "  Renamed: $($Item.Name) -> $NewName" -ForegroundColor Gray
    }
}

# 3. Enable the sample workflows
Write-Host "Enabling workflows..." -ForegroundColor Yellow
$WorkflowsDir = Join-Path $RepoRoot ".github/workflows"
foreach ($Sample in Get-ChildItem -Path $WorkflowsDir -Filter "*.yml-sample" -File -Force) {
    $Enabled = $Sample.Name -replace '\.yml-sample$', '.yml'
    Move-Item -Path $Sample.FullName -Destination (Join-Path $WorkflowsDir $Enabled) -Force
    Write-Host "  Enabled: $Enabled" -ForegroundColor Gray
}

# 4. The template README is no longer needed: the package README replaces it.
#    Both copies must stay identical (commands/check-package.ps1 checks it).
Write-Host "Replacing README.md with the package README..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $RepoRoot "Unity-Package/Assets/root/README.md") -Destination (Join-Path $RepoRoot "README.md") -Force

Write-Host "Done!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Fill in description, keywords and unity in Unity-Package/Assets/root/package.json."
Write-Host "  2. Open every project once to generate .meta files: commands\open-all-projects.cmd"
Write-Host "  3. Run commands\check-package.cmd and commit."
Write-Host "  4. Add the CI secrets (UNITY_*, UPM_*), see docs/openupm-signing.md."
