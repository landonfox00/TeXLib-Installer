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

# Compile the hotkey helper
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:winexe /out:"$env:TEMP\TeXLibHotkey.exe" runtime\TeXLibHotkey.cs
```

✓ PSScriptAnalyzer reports no **errors**.
✓ Every `.ps1` reports `0 error(s)`.
✓ `csc` exits 0 and produces the exe.

> If editing on a OneDrive path, verify parsing on a copy under `$env:TEMP` —
> OneDrive can briefly desync a file mid-write and produce phantom errors.

## 2. Pre-flight (no changes made)

▶ `install.bat -DryRun`
✓ Prints the plan, lists each component, and mentions the `%USERPROFILE%\TeXLib`
  junction when the OneDrive path needs one. Makes no changes.

## 3. Full install

▶ `install.bat` (add `-EnableBuildHotkey` to also test the Ctrl+B hotkey).
✓ Each component downloads, hash-verifies, and installs under
  `%LOCALAPPDATA%\TeXLib`. No red errors. Desktop + Start Menu shortcuts appear.
✓ With `-EnableBuildHotkey`: "Hotkey active" line prints and `TeXLibHotkey.exe`
  is running (`Get-Process TeXLibHotkey`).

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

## 6. Build from File Explorer (no editor open)

Right-click menu (installed on every run):

▶ In File Explorer, right-click a `.tex` → **Build with TeXLib** → **Build**.
✓ PDF opens in SumatraPDF. Source dir stays clean (aux routed to temp).
▶ Repeat for each submenu mode: Answer Key, Solutions, Student Copy, Rubric,
  Draft, All Versions.
✓ Each produces the expected PDF(s); **All Versions** emits one `<base>_<V>.pdf`
  per `\versions{...}` entry.
▶ Right-click a `.tex` containing `% !TeX root = master.tex`.
✓ The master builds, not the child.
▶ Build a deliberately broken `.tex`.
✓ A failure toast appears and the engine `.log` opens. No PDF is produced.

Ctrl+B hotkey (only if installed with `-EnableBuildHotkey`):

▶ Click (select) a `.tex` in File Explorer and press **Ctrl+B**.
✓ It builds the selected file (default mode) and the PDF opens.
▶ Press **Ctrl+B** in another app (e.g. WordPad) with text selected.
✓ Ctrl+B still bolds — the hotkey only fires while Explorer is focused.

## 7. Uninstall

▶ `uninstall.bat` → confirm.
✓ `%LOCALAPPDATA%\TeXLib` removed; shortcuts gone; PATH cleaned; the
  `TeXLibHotkey` process stopped and its Startup shortcut removed; the
  `Build with TeXLib` menu no longer appears on `.tex` files.
✓ `Documents\TeXLib` (the library) is **preserved**. A real (non-junction)
  `%USERPROFILE%\TeXLib` is left untouched.

## 8. Release packaging

▶ `tools\make-release.ps1 -Version <v>`
✓ Produces `dist\TeXLib-Installer-v<v>.zip` + `SHA256SUMS`. Unzip and confirm
  it contains `runtime/` (with `texlib-build.ps1`, `texlib-build-selected.ps1`,
  `TeXLibHotkey.cs`), `templates/`, and the `texlib/` library snapshot.
▶ Extract the ZIP to a clean machine and run §3–§7 from it.
✓ A from-ZIP install behaves identically to a from-repo install.
