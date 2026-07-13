@echo off
REM Thin entry point. All robustness lives in tools\boot_wrapper.ps1 so the
REM .bat surface stays trivial (and any future bat-flavored bugs stay scoped).
cd /d "%~dp0"
echo Starting TeXLib installer...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\boot_wrapper.ps1" install %*
