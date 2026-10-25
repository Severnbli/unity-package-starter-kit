# Terminal UI for the .ps1 scripts in commands/: text prompts with defaults, arrow-key
# menus and checkbox lists. Dot-sourced by Common.ps1.
#
# Scripts ask for missing parameters only when Test-UiEnabled: input and output are a
# console and CI is not set. Drawing uses [Console] cursor positioning, not escape
# sequences, so it works in the Windows PowerShell 5.1 console. Keep this file ASCII-only.

function Test-UiEnabled {
    if ($env:CI) {
        return $false
    }
    try {
        return (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    }
    catch {
        return $false
    }
}

function Write-UiHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ":: $Title" -ForegroundColor Cyan
    Write-Host ""
}

# The answer line that replaces a finished prompt: "+ Question  answer".
function Write-UiAnswered {
    param([string]$Question, [string]$Answer)
    Write-Host "+ " -ForegroundColor Green -NoNewline
    Write-Host "$Question  " -NoNewline
    Write-Host $Answer -ForegroundColor Cyan
}

function Write-UiQuestion {
    param([string]$Question, [string]$Hint)
    Write-Host "? " -ForegroundColor Green -NoNewline
    Write-Host $Question -NoNewline
    Write-Host "  $Hint" -ForegroundColor DarkGray
}

# Blanks $Count lines starting at line $Top and puts the cursor at the start of $Top.
function Clear-UiLines {
    param([int]$Top, [int]$Count)
    $Blank = ' ' * [Math]::Max(0, [Console]::BufferWidth - 1)
    for ($Line = 0; $Line -lt $Count; $Line++) {
        [Console]::SetCursorPosition(0, $Top + $Line)
        [Console]::Write($Blank)
    }
    [Console]::SetCursorPosition(0, $Top)
}

# An option is "Name  description": text after two spaces is shown dimmed and left out
# of the answer line.
function Get-UiOptionName {
    param([string]$Option)
    $Index = $Option.IndexOf('  ')
    if ($Index -lt 0) {
        return $Option
    }
    return $Option.Substring(0, $Index)
}

function Write-UiOptions {
    param([string[]]$Options, [int]$Cursor, [bool]$Multi, [bool[]]$Checked)
    $Width = [Math]::Max(1, [Console]::BufferWidth - 1)
    for ($Index = 0; $Index -lt $Options.Count; $Index++) {
        $Name = Get-UiOptionName $Options[$Index]
        $Description = $Options[$Index].Substring($Name.Length)
        $Pointer = if ($Index -eq $Cursor) { "> " } else { "  " }
        $Mark = ""
        if ($Multi) {
            $Mark = if ($Checked[$Index]) { "[x] " } else { "[ ] " }
        }
        $Text = "  $Pointer$Mark$Name$Description"
        if ($Text.Length -gt $Width) {
            $Text = $Text.Substring(0, $Width)
        }
        $MarkColor = if ($Multi -and $Checked[$Index]) { "Green" } else { "DarkGray" }
        $Head = "  $Pointer"
        Write-Host $Head -ForegroundColor Cyan -NoNewline
        if ($Mark) {
            Write-Host $Mark -ForegroundColor $MarkColor -NoNewline
        }
        $Rest = $Text.Substring([Math]::Min($Text.Length, $Head.Length + $Mark.Length))
        $NamePart = $Rest.Substring(0, [Math]::Min($Rest.Length, $Name.Length))
        if ($Index -eq $Cursor) {
            Write-Host $NamePart -ForegroundColor Cyan -NoNewline
        }
        else {
            Write-Host $NamePart -NoNewline
        }
        Write-Host $Rest.Substring($NamePart.Length) -ForegroundColor DarkGray -NoNewline
        Write-Host (' ' * ($Width - $Text.Length))
    }
}

function Set-UiCursorVisible {
    param([bool]$Visible)
    try { [Console]::CursorVisible = $Visible } catch { }
}

# Arrow-key menu. Returns the chosen index (0-based).
function Read-UiSelect {
    param([string]$Question, [string[]]$Options, [int]$Default = 0)
    Write-UiQuestion $Question "(Up/Down, Enter)"
    $Cursor = $Default
    Set-UiCursorVisible $false
    try {
        Write-UiOptions -Options $Options -Cursor $Cursor -Multi $false
        # Measured after drawing, so a console that scrolled while drawing is accounted for.
        $Top = [Console]::CursorTop - $Options.Count
        $Done = $false
        while (-not $Done) {
            $Key = [Console]::ReadKey($true)
            switch ($Key.Key) {
                "UpArrow" { $Cursor = ($Cursor + $Options.Count - 1) % $Options.Count }
                "K" { $Cursor = ($Cursor + $Options.Count - 1) % $Options.Count }
                "DownArrow" { $Cursor = ($Cursor + 1) % $Options.Count }
                "J" { $Cursor = ($Cursor + 1) % $Options.Count }
                "Enter" { $Done = $true }
                "Spacebar" { $Done = $true }
                default {
                    $Digit = 0
                    if ([int]::TryParse([string]$Key.KeyChar, [ref]$Digit) -and $Digit -ge 1 -and $Digit -le $Options.Count) {
                        $Cursor = $Digit - 1
                    }
                }
            }
            [Console]::SetCursorPosition(0, $Top)
            Write-UiOptions -Options $Options -Cursor $Cursor -Multi $false
        }
    }
    finally {
        Set-UiCursorVisible $true
    }
    Clear-UiLines -Top ($Top - 1) -Count ($Options.Count + 1)
    Write-UiAnswered $Question (Get-UiOptionName $Options[$Cursor])
    return $Cursor
}

# Checkbox list: Space toggles, A toggles all, Enter confirms. Returns the checked
# indices (0-based, in order).
function Read-UiMultiSelect {
    param([string]$Question, [string[]]$Options, [int[]]$Checked = @())
    Write-UiQuestion $Question "(Up/Down, Space: toggle, A: all, Enter)"
    $State = [bool[]]::new($Options.Count)
    foreach ($Index in $Checked) {
        $State[$Index] = $true
    }
    $Cursor = 0
    Set-UiCursorVisible $false
    try {
        Write-UiOptions -Options $Options -Cursor $Cursor -Multi $true -Checked $State
        $Top = [Console]::CursorTop - $Options.Count
        $Done = $false
        while (-not $Done) {
            $Key = [Console]::ReadKey($true)
            switch ($Key.Key) {
                "UpArrow" { $Cursor = ($Cursor + $Options.Count - 1) % $Options.Count }
                "K" { $Cursor = ($Cursor + $Options.Count - 1) % $Options.Count }
                "DownArrow" { $Cursor = ($Cursor + 1) % $Options.Count }
                "J" { $Cursor = ($Cursor + 1) % $Options.Count }
                "Spacebar" { $State[$Cursor] = -not $State[$Cursor] }
                "A" {
                    $All = -not ($State -contains $false)
                    for ($Index = 0; $Index -lt $State.Count; $Index++) {
                        $State[$Index] = -not $All
                    }
                }
                "Enter" { $Done = $true }
            }
            [Console]::SetCursorPosition(0, $Top)
            Write-UiOptions -Options $Options -Cursor $Cursor -Multi $true -Checked $State
        }
    }
    finally {
        Set-UiCursorVisible $true
    }
    Clear-UiLines -Top ($Top - 1) -Count ($Options.Count + 1)
    $Selected = @()
    for ($Index = 0; $Index -lt $Options.Count; $Index++) {
        if ($State[$Index]) {
            $Selected += $Index
        }
    }
    $Summary = ($Selected | ForEach-Object { Get-UiOptionName $Options[$_] }) -join ', '
    Write-UiAnswered $Question $(if ($Summary) { $Summary } else { "(none)" })
    return , [int[]]$Selected
}

# Reads one line. Enter keeps the default. With a pattern, asks again until the answer
# matches it; the hint describes the expected format.
function Read-UiInput {
    param([string]$Question, [string]$Default = "", [string]$Pattern = "", [string]$Hint = "")
    $Lines = 2
    while ($true) {
        $Note = if ($Default) { "(Enter: $Default)" } else { "" }
        Write-UiQuestion $Question $Note
        Write-Host "  > " -NoNewline
        $Answer = [Console]::ReadLine()
        if ($null -eq $Answer) {
            throw "Input ended."
        }
        $Answer = $Answer.Trim()
        if (-not $Answer) {
            $Answer = $Default
        }
        $Top = [Console]::CursorTop - $Lines
        if (-not $Pattern -or $Answer -cmatch $Pattern) {
            break
        }
        # Replace the prompt (and an earlier error) with the error, then ask again below it.
        Clear-UiLines -Top $Top -Count $Lines
        Write-Host "x `"$Answer`" is not valid. $Hint" -ForegroundColor Red
        $Lines = 3
    }
    Clear-UiLines -Top $Top -Count $Lines
    Write-UiAnswered $Question $(if ($Answer) { $Answer } else { "(none)" })
    return $Answer
}

function Read-UiConfirm {
    param([string]$Question, [switch]$DefaultNo)
    $Default = if ($DefaultNo) { 1 } else { 0 }
    return (Read-UiSelect -Question $Question -Options @("Yes", "No") -Default $Default) -eq 0
}
