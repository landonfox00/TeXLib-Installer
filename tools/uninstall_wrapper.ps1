<#
.SYNOPSIS
    Bootstrap wrapper for uninstall.ps1. Same robustness guarantees as
    tools\install_wrapper.ps1 -- see that file for design rationale.

.NOTES
    Sets $env:TEXLIB_INSTALLER_WRAPPED = "1" so uninstall.ps1's
    Stop-Uninstaller knows not to double up its own prompt.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $InnerArgs
)

$env:TEXLIB_INSTALLER_WRAPPED = "1"

$ScriptDir = Split-Path $PSScriptRoot -Parent

$Stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$BootLog = Join-Path $env:TEMP "TeXLib-Uninstaller-boot-$Stamp.log"

try { New-Item -ItemType File -Path $BootLog -Force | Out-Null } catch { $null = $_ }

Write-Host ""
Write-Host "Boot log: $BootLog" -ForegroundColor Gray
Write-Host ""

$RC = 0
try {
    $InnerScript = Join-Path $ScriptDir "uninstall.ps1"
    if (-not (Test-Path $InnerScript)) {
        throw "uninstall.ps1 not found at $InnerScript. Is this a complete release archive?"
    }
    & $InnerScript @InnerArgs *>&1 | Tee-Object -FilePath $BootLog
    $RC = $LASTEXITCODE
    if ($null -eq $RC) { $RC = 0 }
} catch {
    $msg = @"

FATAL: wrapper caught an uncaught exception from uninstall.ps1:

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
    Write-Host " Uninstaller exited with code $RC."                            -ForegroundColor Red
    Write-Host ""
    Write-Host " Boot log: $BootLog"                                           -ForegroundColor Yellow
    Write-Host " Issues:   https://github.com/landonfox00/TeXLib-Installer/issues" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "Boot log saved to: $BootLog" -ForegroundColor Gray
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
exit $RC
