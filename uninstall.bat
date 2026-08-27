@echo off
REM The uninstaller. Double-click it; it shows what is actually installed,
REM with folder sizes, and gives you a tick box per component. Nothing is
REM pre-ticked.
REM
REM The console/scriptable surface is tools\uninstall-console.bat, which takes
REM the -Keep* / -Remove* switches directly.
REM
REM Launched through wscript so no PowerShell console ever shows; see
REM install.bat and tools\launch-hidden.vbs for why `start PowerShell
REM -WindowStyle Hidden` flashed a window and this does not. The fallback
REM line is the old launch, for machines where Windows Script Host is
REM disabled by policy.
cd /d "%~dp0"
"%SystemRoot%\System32\wscript.exe" //B //Nologo "tools\launch-hidden.vbs" uninstall %*
if errorlevel 1 start "" PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\tools\uninstall-gui.ps1" %*
