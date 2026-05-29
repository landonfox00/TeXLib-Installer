@echo off
REM Thin entry point. All robustness lives in tools\uninstall_wrapper.ps1.
cd /d "%~dp0"
echo Starting TeXLib uninstaller...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\uninstall_wrapper.ps1" %*
