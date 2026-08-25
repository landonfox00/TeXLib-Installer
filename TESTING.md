# Testing TeXLib-Installer

A manual test pass before tagging a release. Run top to bottom on a real
Windows 10/11 machine (or VM). Where it matters, test with an `-InstallPath`
containing a comma and a space so the junction path gets exercised, and on a
machine that still has a pre-0.6.3 `Documents\TeXLib` so the migration does.

Legend: `▶` = action, `✓` = expected result.

---

## 1. Static checks (local mirror of CI)

▶ From the repo root in PowerShell:

```powershell
# Lint (same as .github/workflows/lint.yml)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1

# Parse every script (catches syntax breaks the linter may not)
Get-ChildItem -Recurse -Include *.ps1 | ForEach-Object {
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
    "{0}: {1} error(s)" -f $_.Name, $e.Count
}
```

✓ PSScriptAnalyzer reports no **errors**.
✓ Every `.ps1` reports `0 error(s)`.

> If editing on a OneDrive path, verify parsing on a copy under `$env:TEMP` —
> OneDrive can briefly desync a file mid-write and produce phantom errors.

## 1b. Contained local install (fast, safe to run on your own machine)

▶ From the repo root in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File tools\dev-install-test.ps1
```

✓ `ALL ASSERTIONS PASSED` (exit 0).

Builds a *returning machine* in a temp sandbox — an already-synced library, no
`texlib\` bundle, and empty component directories — then runs a real full
install through it twice: once `-Silent`, once interactively with the
Skip answers on stdin. Seeded component dirs make the installer skip all four
large downloads, so the whole thing takes about a minute.

Containment is by flag (`-InstallPath` / `-TeXLibPath` / `-Sandbox`), so there
is nothing to clean up but the sandbox directory; add `-Keep` to inspect it.
This is the fastest way to exercise the paths CI's clean-VM jobs cannot reach.

> **Never** run `uninstall.ps1` / the uninstaller to clean up after a local
> test. It rewrites HKCU file associations and the user PATH regardless of
> `-InstallPath`, and removes `%USERPROFILE%\TeXLib` when the install claims it
> — none of which the sandbox flags contain. Uninstall is covered by CI, where
> the VM is disposable.

## 2. Pre-flight (no changes made)

▶ `tools\install-console.bat -DryRun`
✓ Prints the plan, lists each component, and mentions the `%USERPROFILE%\TeXLib`
  junction when the OneDrive path needs one. Makes no changes.

## 3. Full install

▶ `install.bat` (graphical), then `tools\install-console.bat` (console)
✓ Each component downloads, hash-verifies, and installs under
  `%LOCALAPPDATA%\TeXLib`. No red errors. Desktop + Start Menu shortcuts appear.

## 3b. Library location and migration

▶ On a machine upgrading from ≤0.6.2, watch the pre-flight output.
✓ It names the pre-0.6.3 library it found, and says the old folder is left in
  place.
✓ After the install, `%LOCALAPPDATA%\TeXLib\Library` holds the library, and any
  personal file you had in the old `Sublime\` folder is there too.
✓ `Documents\TeXLib` is **byte-for-byte unchanged**.
✓ A `%USERPROFILE%\TeXLib` junction the old install created is gone; one you
  created yourself is still there.

## 4. Doctor

▶ `tools\install-console.bat -Doctor`
✓ All sections `[OK]`: components found, PATH set, junction state correct,
  `texlib_builder.py` deployed, the TeXLib Sublime package junctioned at
  `Packages\TeXLib`, every LaTeX package TeXLib requires resolvable,
  LaTeXTools builder set to `texlib`, file associations registered, no stale
  "Open with" registrations.

## 4a. Sublime package

▶ In Sublime, open the command palette (**Ctrl+Shift+P**) and type "TeXLib".
✓ TeXLib commands are listed, and a **TeXLib** menu is present in the menu bar.
✓ `<Sublime Data>\Packages\TeXLib` exists and is a junction to
  `<InstallPath>\Library\Sublime\texlib`.

## 4c. Repair

▶ Delete `<Sublime Data>\Packages\TeXLib` and
  `<InstallPath>\Library\Sublime\LaTeXTools.sublime-settings`, then run
  `tools\install-console.bat -Repair`.
✓ Finishes in seconds, downloads nothing, and both come back.
✓ Says it is leaving the library alone; nothing in `Library\` changes.
▶ `tools\install-console.bat -Repair -InstallPath C:\nowhere`
✓ Refuses with "needs an existing install to repair" and exits non-zero.

## 4d. Update

▶ `tools\install-console.bat -Update` on an up-to-date install.
✓ Reports both versions and does nothing.
▶ On an out-of-date install (or a copy with `$InstallerVersion` edited down).
✓ Downloads the newest release, reports `[OK] SHA256 verified`, and hands off to
  it; the handed-off run behaves like a normal install.

## 4b. Open With hygiene

▶ Before installing, note the entries under Right-click → **Open with** for a `.tex` and a `.pdf`.
✓ After installing, dead entries from earlier installs are gone, the TeXLib
  entries read `Sublime Text (TeXLib)` / `SumatraPDF (TeXLib)`, and any
  Sublime/SumatraPDF you installed yourself is **still listed**.
✓ The change is visible without signing out (the installer calls
  `SHChangeNotify`).

## 5. Editor build (Sublime)

▶ Open `%LOCALAPPDATA%\TeXLib\Library\examples\…\*.tex`, press **Ctrl+B**.
✓ Builds and the PDF opens in SumatraPDF.
▶ Press **Ctrl+Shift+B**, pick a variant (Answer Key, Solutions, …).
✓ The variant builds; no `.aux`/`.log` left next to the source.

## 6. Uninstall

▶ Leave Sublime Text **running**, then `tools\uninstall-console.bat` → confirm.
✓ It reports the running programs and offers to close them.
▶ Answer `Y` to Sublime and Sumatra, `n` to TeX Live.
✓ `Sublime Text\` and `Sumatra\` are gone; `TexLive\` remains; the install root
  survives to hold it, with `Scripts\` and `VERSION` intact.
▶ `tools\uninstall-console.bat` again, answering `Y` to everything.
✓ `%LOCALAPPDATA%\TeXLib` is **entirely gone** — including `Library\`. Shortcuts
  gone, PATH cleaned, TeXLib entries out of the Open With lists, entries for your
  own Sublime/SumatraPDF untouched.
✓ A pre-0.6.3 `Documents\TeXLib` is **preserved** unless you answered `Y` to the
  library question or passed `-RemoveLibrary`. A real (non-junction)
  `%USERPROFILE%\TeXLib` is left untouched.
✓ The uninstall log is in `%TEMP%\TeXLib-Uninstall\`, not inside the removed
  tree.

## 7. Release packaging

▶ `tools\make-release.ps1 -Version <v>`
✓ Produces `dist\TeXLib-Installer-v<v>.zip` + `SHA256SUMS`. Unzip and confirm the root holds `install.bat`, `uninstall.bat`, `templates/`, and `tools/` — no `texlib/` tree (the library is downloaded at install time, not bundled) and **no** `.ps1` files, so there is nothing to mis-click.
✓ `tools/` contains `boot_wrapper.ps1`, `install.ps1`, `uninstall.ps1`, and
  neither `make-release.ps1` nor `dev-install-test.ps1`.
▶ Extract the ZIP to a clean machine and run §3–§6 from it.
✓ A from-ZIP install behaves identically to a from-repo install.
