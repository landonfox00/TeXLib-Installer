@echo off
cd /d "%~dp0"
echo Starting TeXLib installer...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1" %*
