@echo off
REM Graphical entry point. install.bat is the console one and remains the
REM scriptable/CI surface; this is the one to hand someone who just wants to
REM click through it. -STA is required for WPF; -WindowStyle Hidden keeps a
REM console from sitting behind the window.
cd /d "%~dp0"
start "" PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\tools\install-gui.ps1" %*
