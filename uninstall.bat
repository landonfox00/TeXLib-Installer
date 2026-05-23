@echo off
cd /d "%~dp0"
echo Starting TeXLib uninstaller...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File ".\uninstall.ps1" %*
