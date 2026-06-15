# First-run smoke test (manual)

CI proves the installer **installs** correctly on a clean Windows VM, but a
headless CI job can't *activate* the things that need a real interactive
desktop session — double-clicking a file, a global hotkey, a PDF viewer
opening. Run this five-minute checklist once on a real machine after an
install (ideally a coworker's UNR machine, since the OneDrive-path junction is
the one behavior CI can only simulate).

## Setup
- [ ] On a clean machine, run `install.bat` by **double-clicking it** (not via
      PowerShell 7 / an editor). This is the exact path a coworker uses and the
      one that caught the v0.5.0 launch bug.
- [ ] Installer finishes with a success banner, no red `[FAIL]`/error text.

## TeX toolchain
- [ ] **Open a brand-new terminal** (PATH only refreshes in new processes) and
      run `pdflatex --version` — it should report TeX Live and a path under
      `%LOCALAPPDATA%\TeXLib\TexLive\<year>\bin\windows`.
- [ ] `install.bat`-installed `%LOCALAPPDATA%\TeXLib\install.bat ... -Doctor`
      (or run `install.ps1 -Doctor`) reports all `[OK]` and **exits 0**
      (`echo %ERRORLEVEL%` / `$LASTEXITCODE` should be 0).

## OneDrive path (UNR machines specifically)
- [ ] On a machine whose OneDrive folder contains a space/comma (e.g.
      `OneDrive - University of Nevada, Reno`), confirm `%USERPROFILE%\TeXLib`
      exists and is a **junction** (`fsutil reparsepoint query "%USERPROFILE%\TeXLib"`
      or `Get-Item $env:USERPROFILE\TeXLib -Force | Select LinkType,Target`).
- [ ] Open a TeXLib document that `\usepackage`s the library and **build it** —
      it should compile (this is what the comma-in-`TEXINPUTS` junction exists
      to make possible).

## Editor + viewer integration
- [ ] **Double-click a `.tex` file** in Explorer → it opens in Sublime Text.
- [ ] In Sublime, build the document (LaTeXTools) → a PDF is produced and opens
      in **SumatraPDF**.
- [ ] **Right-click a `.tex`** in Explorer → the **"Build with TeXLib"** menu
      appears; pick a build and confirm the PDF is produced.
- [ ] (If installed with `-EnableBuildHotkey`) select a `.tex` in Explorer with
      no editor open and press **Ctrl+B** → it builds. Also confirm your
      antivirus / endpoint-security didn't quarantine `TeXLibHotkey.exe`.
- [ ] **Double-click a `.pdf`** → it opens in SumatraPDF. Note: the installer
      also takes over `.txt` (opens in Sublime) — confirm that's intended.

## Uninstall
- [ ] Run `uninstall.bat`. Confirm `%LOCALAPPDATA%\TeXLib` is gone, the PATH
      entry is cleaned, shortcuts/associations are removed, and your
      `Documents\TeXLib` (the synced library) is **preserved**.
