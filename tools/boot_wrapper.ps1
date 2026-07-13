<#
.SYNOPSIS
    Bootstrap wrapper for install.ps1 / uninstall.ps1 (selected by -Kind).
    Captures ALL output (even errors that happen before the inner script's
    Start-Transcript runs) and guarantees the console window stays open on
    failure.

.DESCRIPTION
    The bare .bat -> PowerShell -File invocation has two failure modes that
    eat your error message:

      1. If the inner script throws before its Start-Transcript runs
         (param-binding issue, locked %LOCALAPPDATA%, environment-variable
         corruption, ...), no log file is created. The user sees red text, the
         window closes, and there is nothing to diagnose.

      2. Even if a log IS written, the .bat does not pause on non-zero exit,
         so a double-click launch closes the window before the user can read
         the error.

    This wrapper fixes both:

      - Tee-Object captures the inner script's combined output stream (every
        PowerShell stream merged via *>&1) into a boot log in %TEMP% that is
        created BEFORE the inner script starts.
      - A top-level try/catch turns any uncaught PowerShell exception into a
        reportable exit code 99 instead of an unrecoverable crash.
      - On any non-zero exit, the wrapper prints the boot-log path and waits
        for the user before returning to the .bat.

.PARAMETER Kind
    'install' or 'uninstall' -- selects the sibling <Kind>.ps1 to run and the
    label used in messages and the boot-log name.

.NOTES
    Sets $env:TEXLIB_INSTALLER_WRAPPED = "1" so the inner script's
    Stop-Installer / Stop-Uninstaller knows not to double up its own
    "Press Enter to close" prompt.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('install', 'uninstall')]
    [string]$Kind,

    [Parameter(ValueFromRemainingArguments = $true)]
    $InnerArgs
)

$Label = if ($Kind -eq 'install') { 'Installer' } else { 'Uninstaller' }

# Tell the inner script we're handling user prompts + exit-code surfacing.
$env:TEXLIB_INSTALLER_WRAPPED = "1"

# tools\boot_wrapper.ps1 lives one directory below the inner scripts.
$ScriptDir = Split-Path $PSScriptRoot -Parent

# Boot log in %TEMP% so a locked install dir does not prevent logging. The
# timestamp prevents collisions if a coworker re-runs after a failure.
$Stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$BootLog = Join-Path $env:TEMP "TeXLib-$Label-boot-$Stamp.log"

# Eagerly touch the boot log so a hard crash inside the pipeline still leaves
# a file behind for the user to attach to a bug report.
try { New-Item -ItemType File -Path $BootLog -Force | Out-Null } catch { $null = $_ }

Write-Host ""
Write-Host "Boot log: $BootLog" -ForegroundColor Gray
Write-Host ""

$RC = 0
try {
    $InnerScript = Join-Path $ScriptDir "$Kind.ps1"
    if (-not (Test-Path $InnerScript)) {
        throw "$Kind.ps1 not found at $InnerScript. Is this a complete release archive?"
    }

    # *>&1 merges every output stream into the success stream so Tee-Object
    # captures host writes, warnings, verbose, AND error records to the boot
    # log without losing colors on the live console.
    & $InnerScript @InnerArgs *>&1 | Tee-Object -FilePath $BootLog
    $RC = $LASTEXITCODE
    if ($null -eq $RC) { $RC = 0 }

} catch {
    $msg = @"

FATAL: wrapper caught an uncaught exception from $Kind.ps1:

$($_ | Out-String)

Script stack trace:
$($_.ScriptStackTrace)
"@
    Add-Content -Path $BootLog -Value $msg
    Write-Host $msg -ForegroundColor Red
    $RC = 99
}

if ($RC -ne 0) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " $Label exited with code $RC."                                 -ForegroundColor Red
    Write-Host ""
    Write-Host " Boot log (always present, captures pre-transcript errors):"   -ForegroundColor Yellow
    Write-Host "   $BootLog"                                                   -ForegroundColor Yellow
    if ($Kind -eq 'install') {
        Write-Host ""
        Write-Host " Install log (if Start-Transcript reached it):"            -ForegroundColor Yellow
        Write-Host "   %LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log"     -ForegroundColor Yellow
        Write-Host "   (or %TEMP%\TeXLib-Install\install-<timestamp>.log if the" -ForegroundColor Yellow
        Write-Host "    install dir didn't exist yet)"                         -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host " Please attach the boot log when reporting:"                   -ForegroundColor Yellow
    Write-Host "   https://github.com/landonfox00/TeXLib-Installer/issues"     -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "Boot log saved to: $BootLog" -ForegroundColor Gray
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
exit $RC
