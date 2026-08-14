@echo off
REM The installer. Double-click it; INSTALL.md documents this one.
REM
REM The console/scriptable surface -- what CI drives, and what -Repair,
REM -Doctor, -Verify, -Update and -Silent are documented against -- is
REM tools\install-console.bat. It takes the same switches this one does.
REM
REM -STA is required for WPF; -WindowStyle Hidden keeps a console from sitting
REM behind the window. `start` returns immediately so the cmd window this .bat
REM runs in closes rather than lingering behind the installer.
cd /d "%~dp0"
start "" PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\tools\install-gui.ps1" %*
