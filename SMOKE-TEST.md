# First-run smoke test (manual)

CI proves the installer **installs** correctly on a clean Windows VM, but a
headless CI job can't *activate* the things that need a real interactive
desktop session — double-clicking a file, a PDF viewer opening. Run this
five-minute checklist once on a real machine after an
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
- [ ] `tools\install-console.bat -Doctor` reports all `[OK]` and **exits 0**
      (`echo %ERRORLEVEL%` / `$LASTEXITCODE` should be 0).

## Library location
- [ ] The library is at `%LOCALAPPDATA%\TeXLib\Library` and **nothing new
      appeared in `Documents`**.
- [ ] Open a TeXLib document that `\usepackage`s the library and **build it** —
      it should compile (this is what the `TEXINPUTS` wiring exists for).
- [ ] Upgrading from ≤0.6.2: your old `Documents\TeXLib` is untouched, and any
      personal file from its `Sublime\` folder is now under
      `%LOCALAPPDATA%\TeXLib\Library\Sublime` too.
- [ ] Only when installed with an `-InstallPath` containing a space or comma:
      confirm `%USERPROFILE%\TeXLib` exists and is a **junction**
      (`fsutil reparsepoint query "%USERPROFILE%\TeXLib"` or
      `Get-Item $env:USERPROFILE\TeXLib -Force | Select LinkType,Target`).

## Editor + viewer integration
- [ ] **Double-click a `.tex` file** in Explorer → it opens in Sublime Text.
- [ ] In Sublime, build the document (LaTeXTools) → a PDF is produced and opens
      in **SumatraPDF**.
- [ ] **Double-click a `.pdf`** → it opens in SumatraPDF.
- [ ] **Double-click a `.txt`** → it opens in the system default (Notepad),
      NOT Sublime. Decided 2026-08-25: taking over every plain-text file was
      surprising, so `.txt` is no longer claimed; on an upgrade the old claim
      is released unless the user themselves pinned Sublime for it.
- [ ] Right-click → **Open with** on a `.tex`: no duplicate or dead Sublime entries, ours reads `Sublime Text (TeXLib)`, and a Sublime you installed yourself is **still listed**. This is the one thing no headless job can check, because it needs a real Explorer.

## Uninstall
- [ ] Leave Sublime Text open, then run `uninstall.bat`. It should notice and
      offer to close it.
- [ ] Answer `n` to TeX Live and `Y` to the rest: `Sublime Text\` and `Sumatra\`
      are gone, `TexLive\` survives.
- [ ] Run it again, answering `Y` to everything. Confirm `%LOCALAPPDATA%\TeXLib`
      is **entirely gone** (including `Library\`), the PATH entry is cleaned, and
      shortcuts/associations are removed.
- [ ] A pre-0.6.3 `Documents\TeXLib` is **preserved** unless you asked for it.
- [ ] Right-click → **Open with** again: the TeXLib entries are gone, and your own Sublime/SumatraPDF entries are still there.
