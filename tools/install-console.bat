@echo off
REM Console entry point -- the scriptable surface, and what CI drives. The
REM installer you double-click is install.vbs at the release root; this one
REM takes the same switches plus the ones only a console run makes sense for:
REM
REM   tools\install-console.bat -Doctor
REM   tools\install-console.bat -Repair
REM   tools\install-console.bat -Verify
REM   tools\install-console.bat -Silent -Reinstall Sublime,SumatraPDF
REM
REM All robustness lives in boot_wrapper.ps1 so the .bat surface stays trivial
REM (and any future bat-flavored bugs stay scoped).
REM
REM cwd is the RELEASE ROOT, not tools\ -- that is where texlib.config.json and
REM the texlib\ bundle live, and where a relative -InstallPath should resolve.
REM The scripts locate themselves via $PSScriptRoot regardless, so this only
REM affects paths the USER types.
cd /d "%~dp0.."
echo Starting TeXLib installer...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0boot_wrapper.ps1" install %*
