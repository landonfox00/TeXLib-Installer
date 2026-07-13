@echo off
REM Thin entry point. All robustness lives in tools\boot_wrapper.ps1.
cd /d "%~dp0"
echo Starting TeXLib uninstaller...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\boot_wrapper.ps1" uninstall %*
