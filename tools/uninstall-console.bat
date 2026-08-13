@echo off
REM Console entry point for the uninstaller -- the scriptable surface. The one
REM you double-click is uninstall.bat at the release root; this one takes the
REM -KeepSublime / -KeepSumatra / -KeepTeXLive / -RemoveLibrary /
REM -RemoveJunction / -Force / -Silent switches directly.
REM
REM All robustness lives in boot_wrapper.ps1. cwd is the release root, not
REM tools\ -- see install-console.bat for why.
cd /d "%~dp0.."
echo Starting TeXLib uninstaller...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0boot_wrapper.ps1" uninstall %*
