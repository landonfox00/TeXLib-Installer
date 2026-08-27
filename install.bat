@echo off
REM The installer. Double-click it; INSTALL.md documents this one.
REM
REM The console/scriptable surface -- what CI drives, and what -Repair,
REM -Doctor, -Verify, -Update and -Silent are documented against -- is
REM tools\install-console.bat. It takes the same switches this one does.
REM
REM Launched through wscript so no PowerShell console ever shows. The old
REM `start PowerShell -WindowStyle Hidden` line created the console VISIBLE
REM and PowerShell only hid it once its startup processed -WindowStyle, so
REM every double-click flashed a window first. launch-hidden.vbs passes
REM SW_HIDE at process creation instead, and carries the details (including
REM the -STA WPF requirement).
REM
REM The fallback line is the old launch, kept for machines where Windows
REM Script Host is disabled by policy (wscript then exits nonzero): one
REM cosmetic flash there, never a dead double-click.
cd /d "%~dp0"
"%SystemRoot%\System32\wscript.exe" //B //Nologo "tools\launch-hidden.vbs" install %*
if errorlevel 1 start "" PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\tools\install-gui.ps1" %*
