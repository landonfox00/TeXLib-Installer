<#
.SYNOPSIS
    TeXLib-Installer uninstall: reverses install.ps1.

.DESCRIPTION
    Removes the per-user TeXLib install (%LOCALAPPDATA%\TeXLib), Desktop and
    Start Menu shortcuts, PATH entries, and file-association registry keys.

    Preserves your Documents\TeXLib (the synced library + course materials).
    If you want to remove that too, delete it manually.

.PARAMETER Silent
    Skip all interactive prompts.

.NOTES
    Logs to %LOCALAPPDATA%\TeXLib\Logs\uninstall-<timestamp>.log if the install
    directory still exists, otherwise to $env:TEMP.
#>
[CmdletBinding()]
param(
    [switch]$Silent
)

$UninstallerVersion = "0.5.1"   # keep in lockstep with install.ps1 $InstallerVersion
$InstallerRepo      = "https://github.com/landonfox00/TeXLib-Installer"

$BaseDir = "$env:LOCALAPPDATA\TeXLib"
$LogDir  = if (Test-Path $BaseDir) { "$BaseDir\Logs" } else { "$env:TEMP\TeXLib-Uninstall" }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = "$LogDir\uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile -IncludeInvocationHeader | Out-Null

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   TeXLib-Uninstaller v$UninstallerVersion"      -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log file: $LogFile" -ForegroundColor Gray
Write-Host ""

function Stop-Uninstaller {
    param([int]$ExitCode = 0)
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    # tools\uninstall_wrapper.ps1 owns the prompt when present; see the
    # matching note in install.ps1's Stop-Installer.
    if (-not $Silent -and $ExitCode -ne 0 -and -not $env:TEXLIB_INSTALLER_WRAPPED) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    exit $ExitCode
}

# Quick check: anything to uninstall?
if (-not (Test-Path $BaseDir)) {
    Write-Host "Nothing to uninstall: $BaseDir does not exist." -ForegroundColor Yellow
    Write-Host "  (Will still clean up PATH entries, shortcuts, and registry keys in case of a partial prior install.)" -ForegroundColor Gray
    Write-Host ""
}

if (-not $Silent) {
    Write-Host "About to remove:" -ForegroundColor Yellow
    Write-Host "  - $BaseDir (Sublime, Sumatra, TeX Live, scripts, logs)" -ForegroundColor Gray
    Write-Host "  - Desktop and Start Menu shortcuts" -ForegroundColor Gray
    Write-Host "  - PATH entries pointing at TeX Live" -ForegroundColor Gray
    Write-Host "  - File-association registry keys" -ForegroundColor Gray
    Write-Host "  - 'Build with TeXLib' right-click menu + Ctrl+B hotkey (if installed)" -ForegroundColor Gray
    Write-Host "  - $env:USERPROFILE\TeXLib  (only if it is a junction -- see notes)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "PRESERVES:" -ForegroundColor Green
    Write-Host "  - $env:USERPROFILE\Documents\TeXLib  (or OneDrive equivalent)" -ForegroundColor Gray
    Write-Host ""
    $Confirm = Read-Host "Proceed? (Y/N)"
    if ($Confirm -ne "Y" -and $Confirm -ne "y") {
        Write-Host "Aborted." -ForegroundColor Yellow
        Stop-Uninstaller 0
    }
}

# 0. Stop the resident Ctrl+B hotkey so its exe isn't locked under BaseDir.
$Hk = Get-Process -Name "TeXLibHotkey" -ErrorAction SilentlyContinue
if ($Hk) {
    Write-Host "Stopping TeXLib build hotkey..." -ForegroundColor Yellow
    $Hk | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
}

# 1. Remove install directory.
if (Test-Path $BaseDir) {
    Write-Host "Removing $BaseDir..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $BaseDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Host "  [WARN] Some files could not be removed (likely in-use): $_" -ForegroundColor Yellow
        Write-Host "  [WARN] Close Sublime Text and SumatraPDF and re-run the uninstaller." -ForegroundColor Yellow
    }
}

# 2. Remove user-root TeXLib junction (the TEXINPUTS-safe path created by
# install.ps1 when the OneDrive folder contains a space or comma).
# Critical safety check: only remove if it's actually a reparse point. If the
# user has a real folder at %USERPROFILE%\TeXLib (e.g. they built one before
# this installer existed), we must not touch it -- that would destroy their
# library.
$UserRootJunction = "$env:USERPROFILE\TeXLib"
if (Test-Path $UserRootJunction) {
    $Item = Get-Item $UserRootJunction -Force
    if ($Item.Attributes -match 'ReparsePoint') {
        Write-Host "Removing user-root junction $UserRootJunction..." -ForegroundColor Yellow
        try {
            # [System.IO.Directory]::Delete with recursive=$false unambiguously
            # deletes the junction entry without following the link into the
            # OneDrive target.
            [System.IO.Directory]::Delete($UserRootJunction, $false)
            Write-Host "  Removed junction (target preserved)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not remove $UserRootJunction : $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "$UserRootJunction is a real folder, not a junction; leaving it alone." -ForegroundColor Gray
    }
}

# 3. Remove shortcuts.
Write-Host "Removing shortcuts..." -ForegroundColor Yellow
$DesktopPath   = [Environment]::GetFolderPath("Desktop")
$StartMenuPath = [Environment]::GetFolderPath("StartMenu") + "\Programs"
$ShortcutNames = @("Sublime.lnk", "Sumatra.lnk", "Sublime Text.lnk", "SumatraPDF.lnk")
foreach ($n in $ShortcutNames) {
    foreach ($dir in @($DesktopPath, $StartMenuPath)) {
        $p = Join-Path $dir $n
        if (Test-Path $p) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed $p" -ForegroundColor Gray
        }
    }
}
# Build-hotkey Startup shortcut (present only with -EnableBuildHotkey).
$StartupLnk = Join-Path ([Environment]::GetFolderPath("Startup")) "TeXLib Build Hotkey.lnk"
if (Test-Path $StartupLnk) {
    Remove-Item $StartupLnk -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed $StartupLnk" -ForegroundColor Gray
}

# 4. Clean PATH.
Write-Host "Cleaning user PATH..." -ForegroundColor Yellow
$TexLiveYear  = "2025"   # keep in lockstep with install.ps1 $TexLiveYear
$TexBinPath   = "$BaseDir\TexLive\$TexLiveYear\bin\windows"
$LegacyOneTeX = "$env:LOCALAPPDATA\OneTeX\TexLive\$TexLiveYear\bin\windows"
$LegacyWrappers = "$env:LOCALAPPDATA\OneTeX\Wrappers"

$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath) {
    $PathParts = $CurrentPath -split ";"
    $NewParts = $PathParts | Where-Object {
        $_ -ne $TexBinPath -and $_ -ne $LegacyOneTeX -and $_ -ne $LegacyWrappers -and $_ -ne ""
    }
    if ($NewParts.Count -ne $PathParts.Count) {
        [Environment]::SetEnvironmentVariable("Path", ($NewParts -join ";"), "User")
        Write-Host "  PATH cleaned" -ForegroundColor Green
    } else {
        Write-Host "  PATH had nothing to remove" -ForegroundColor Gray
    }
}

# 5. Remove registry associations.
Write-Host "Removing file-association registry keys..." -ForegroundColor Yellow
$RegPath = "HKCU:\Software\Classes"
$TexlibProgIDs = @("TeXLib.SublimeFile", "TeXLib.SumatraPDF",
                   "OneTeX.SublimeFile", "OneTeX.SumatraPDF")
foreach ($ID in ($TexlibProgIDs + "TeXLib.BuildMenu")) {
    $full = "$RegPath\$ID"
    if (Test-Path $full) {
        Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed $ID" -ForegroundColor Gray
    }
}

# Remove the per-extension associations install created (HKCU\Software\Classes\
# <ext> whose default points at one of our ProgIDs). Without this, uninstall
# leaves .tex/.cls/... pointing at a now-deleted ProgID (a broken "open with"),
# and -- most rudely -- leaves .txt hijacked. Only delete a key whose default
# is OURS, so an association the user set themselves is never clobbered.
# Removing HKCU\.txt restores the system (HKLM) default for .txt.
foreach ($Ext in @(".txt", ".tex", ".cls", ".sty", ".bib",
                   ".sublime-project", ".sublime-workspace", ".pdf")) {
    $ExtKey = "$RegPath\$Ext"
    if (Test-Path $ExtKey) {
        $def = $null
        try { $def = (Get-Item -Path $ExtKey).GetValue("") } catch { $def = $null }
        if ($def -and ($TexlibProgIDs -contains $def)) {
            Remove-Item -Path $ExtKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed $Ext association ($def)" -ForegroundColor Gray
        }
    }
}
# Build-from-Explorer right-click flyout on .tex.
$BuildVerbKey = "$RegPath\SystemFileAssociations\.tex\shell\TeXLibBuild"
if (Test-Path $BuildVerbKey) {
    Remove-Item -Path $BuildVerbKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed .tex 'Build with TeXLib' menu" -ForegroundColor Gray
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   Uninstall complete." -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Your Documents\TeXLib folder was NOT touched. Delete it manually" -ForegroundColor Gray
Write-Host "if you want a fully clean removal." -ForegroundColor Gray
Write-Host ""
Write-Host "Issues: $InstallerRepo/issues" -ForegroundColor Cyan
Write-Host ""

Stop-Uninstaller 0
