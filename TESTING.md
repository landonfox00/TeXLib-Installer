# Testing TeXLib-Installer

A manual test pass before tagging a release. Run top to bottom on a real
Windows 10/11 machine (or VM). Where it matters, test on a machine whose
OneDrive path contains a comma/space (e.g. UNR's `OneDrive - University of
Nevada, Reno`) so the junction path gets exercised.

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

> **Never** run `uninstall.ps1` / `uninstall.bat` to clean up after a local
> test. It removes `%USERPROFILE%\TeXLib` whenever that is a junction — on a
> developer machine that is the live junction to your real TeXLib library.
> Uninstall is covered by CI, where the VM is disposable.

## 2. Pre-flight (no changes made)

▶ `install.bat -DryRun`
✓ Prints the plan, lists each component, and mentions the `%USERPROFILE%\TeXLib`
  junction when the OneDrive path needs one. Makes no changes.

## 3. Full install

▶ `install.bat`
✓ Each component downloads, hash-verifies, and installs under
  `%LOCALAPPDATA%\TeXLib`. No red errors. Desktop + Start Menu shortcuts appear.

## 4. Doctor

▶ `install.bat -Doctor`
✓ All sections `[OK]`: components found, PATH set, junction state correct,
  `texlib_builder.py` deployed, LaTeXTools builder set to `texlib`,
  file associations registered.

## 5. Editor build (Sublime)

▶ Open `Documents\TeXLib\examples\…\*.tex`, press **Ctrl+B**.
✓ Builds and the PDF opens in SumatraPDF.
▶ Press **Ctrl+Shift+B**, pick a variant (Answer Key, Solutions, …).
✓ The variant builds; no `.aux`/`.log` left next to the source.

## 6. Uninstall

▶ `uninstall.bat` → confirm.
✓ `%LOCALAPPDATA%\TeXLib` removed; shortcuts gone; PATH cleaned.
✓ `Documents\TeXLib` (the library) is **preserved**. A real (non-junction)
  `%USERPROFILE%\TeXLib` is left untouched.

## 7. Release packaging

▶ `tools\make-release.ps1 -Version <v>`
✓ Produces `dist\TeXLib-Installer-v<v>.zip` + `SHA256SUMS`. Unzip and confirm
  it contains `templates/` and the `texlib/` library snapshot.
▶ Extract the ZIP to a clean machine and run §3–§6 from it.
✓ A from-ZIP install behaves identically to a from-repo install.
