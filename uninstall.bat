@echo off
REM The uninstaller. Double-click it; it shows what is actually installed,
REM with folder sizes, and gives you a tick box per component. Nothing is
REM pre-ticked.
REM
REM The console/scriptable surface is tools\uninstall-console.bat, which takes
REM the -Keep* / -Remove* switches directly.
REM
REM -STA is required for WPF; -WindowStyle Hidden keeps a console from sitting
REM behind the window.
cd /d "%~dp0"
start "" PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\tools\uninstall-gui.ps1" %*
