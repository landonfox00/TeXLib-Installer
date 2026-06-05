<#
.SYNOPSIS
    Resolve the file(s) currently selected in a File Explorer window and build
    each .tex with texlib-build.ps1. Invoked by the Ctrl+B hotkey process.

.DESCRIPTION
    The resident hotkey (TeXLibHotkey.exe) captures the foreground window's
    handle at the moment Ctrl+B is pressed and passes it here as -ExplorerHwnd.
    We enumerate open Explorer windows via the Shell.Application COM object,
    match the one whose .HWND equals that handle, read its SelectedItems(),
    and build every selected .tex. Matching on the captured HWND (rather than
    re-reading the foreground window) avoids the race where launching this
    script steals focus before we can read the selection.

.PARAMETER ExplorerHwnd
    The HWND (as a decimal integer) of the Explorer window that was focused
    when the hotkey fired. If 0 / omitted, falls back to the first Explorer
    window that reports a selection.

.PARAMETER Mode
    Build mode passed through to texlib-build.ps1 (default: default).
#>
[CmdletBinding()]
param(
    [long]$ExplorerHwnd = 0,
    [ValidateSet('default', 'key', 'solutions', 'student', 'rubric', 'draft', 'allversions')]
    [string]$Mode = 'default'
)

$ErrorActionPreference = 'Stop'
$builder = Join-Path $PSScriptRoot 'texlib-build.ps1'

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
function Notify {
    param([string]$Message)
    try {
        $tip = New-Object System.Windows.Forms.NotifyIcon
        $tip.Icon = [System.Drawing.SystemIcons]::Information
        $tip.Visible = $true
        $tip.ShowBalloonTip(3000, 'TeXLib Build', $Message, 'Info')
        Start-Sleep -Milliseconds 200
        $tip.Dispose()
    } catch {
        Write-Host $Message
    }
}

# Enumerate Explorer windows and gather the selection from the matching one.
$selected = New-Object System.Collections.Generic.List[string]
try {
    $shell = New-Object -ComObject Shell.Application
    foreach ($w in $shell.Windows()) {
        if (-not $w) { continue }
        # Only file-system Explorer windows expose a usable Document/HWND; the
        # Internet Explorer / Edge legacy COM windows also appear here, so guard.
        $hwnd = $null
        try { $hwnd = [long]$w.HWND } catch { continue }
        $isMatch = ($ExplorerHwnd -ne 0 -and $hwnd -eq $ExplorerHwnd)

        if ($ExplorerHwnd -eq 0 -or $isMatch) {
            $doc = $null
            try { $doc = $w.Document } catch { continue }
            if (-not $doc) { continue }
            $items = $null
            try { $items = $doc.SelectedItems() } catch { continue }
            if ($items) {
                foreach ($it in $items) {
                    if ($it -and $it.Path) { $selected.Add($it.Path) }
                }
            }
            if ($isMatch) { break }
            if ($ExplorerHwnd -eq 0 -and $selected.Count) { break }
        }
    }
} catch {
    Notify "Could not read the Explorer selection: $_"
    exit 2
}

$texFiles = @($selected | Where-Object { [System.IO.Path]::GetExtension($_).ToLower() -eq '.tex' })

if (-not $texFiles.Count) {
    Notify 'Select a .tex file in File Explorer, then press Ctrl+B.'
    exit 0
}

foreach ($f in $texFiles) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File $builder -Path $f -Mode $Mode
}
