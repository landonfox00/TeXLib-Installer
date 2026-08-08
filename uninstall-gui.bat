@echo off
REM Graphical uninstaller. uninstall.bat is the console one and remains the
REM scriptable surface; this is the one to hand someone who wants to pick what
REM goes. -STA is required for WPF; -WindowStyle Hidden keeps a console from
REM sitting behind the window.
cd /d "%~dp0"
start "" PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\tools\uninstall-gui.ps1" %*
