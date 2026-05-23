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

$UninstallerVersion = "0.1.0"
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
    try { Stop-Transcript | Out-Null } catch {}
    if (-not $Silent -and $ExitCode -ne 0) {
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

# 2. Remove shortcuts.
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

# 3. Clean PATH.
Write-Host "Cleaning user PATH..." -ForegroundColor Yellow
$TexBinPath   = "$BaseDir\TexLive\2025\bin\windows"
$LegacyOneTeX = "$env:LOCALAPPDATA\OneTeX\TexLive\2025\bin\windows"
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

# 4. Remove registry associations.
Write-Host "Removing file-association registry keys..." -ForegroundColor Yellow
$RegPath = "HKCU:\Software\Classes"
foreach ($ID in @("TeXLib.SublimeFile", "TeXLib.SumatraPDF", "OneTeX.SublimeFile", "OneTeX.SumatraPDF")) {
    $full = "$RegPath\$ID"
    if (Test-Path $full) {
        Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed $ID" -ForegroundColor Gray
    }
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
