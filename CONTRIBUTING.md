# Contributing to TeXLib-Installer

This repo builds a portable Windows installer (Sublime Text + SumatraPDF +
TeX Live + the [TeXLib](https://github.com/landonfox00/TeXLib) library) for
non-technical colleagues. The audience matters: changes should keep the install
**robust and self-explanatory on a locked-down Windows machine**.

> Just installing TeXLib? See [INSTALL.md](INSTALL.md). This file is for people
> working on the installer itself. For the day-to-day layout, see
> [README.md](README.md); for the test checklist, [TESTING.md](TESTING.md).

## Ground rules

- **Branch off `main`** with a descriptive name; don't push to `main` directly.
- **One logical change per commit**, present-tense scoped messages
  (`fix(install): …`, `docs: …`).
- **Update `CHANGELOG.md`** under `## [Unreleased]` (Keep a Changelog). The
  installer and uninstaller version strings (`$InstallerVersion` in
  `install.ps1`, `$UninstallerVersion` in `uninstall.ps1`) are kept in lockstep.

## PowerShell conventions

- Scripts target **PowerShell 5.1** (the Windows-in-box version). Avoid 7+-only
  syntax (ternary, `??`, `&&`/`||` chaining).
- Set `$ErrorActionPreference = 'Stop'` and guard tolerated failures explicitly
  (`-ErrorAction SilentlyContinue` / `try`/`catch`).
- Files are UTF-8 **without BOM** (em dashes etc. appear in messages). When
  parse-checking, decode as UTF-8 explicitly — `ParseFile` on the raw bytes
  mis-reads the dashes as syntax errors.
- Downloads must verify a SHA256/SHA512 and fail closed on mismatch; pin
  third-party code to a tag/commit (never a moving branch).

## Testing before a PR

- **Lint** (CI runs this; fails only on Errors):

  ```powershell
  Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
  Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
  ```

- **Dry run** (no system changes): `install.bat -DryRun` (or
  `powershell -File install.ps1 -DryRun`).
- **Doctor** (diagnose an existing install): `install.bat -Doctor`.
- **Manual checklist:** work through [TESTING.md](TESTING.md). A real
  end-to-end install on a clean machine is the gold standard before any release
  that touches download/extract/configure logic — it's the one path CI can't
  cover.

## Refreshing component versions

The pinned versions live in the `$Downloads` table at the top of `install.ps1`;
the header documents the refresh steps (new URL → recompute hash → bump version
→ CHANGELOG → re-release). The SumatraPDF exe name derives from its zip name,
and the TeX Live tree year is `$TexLiveYear` — update those single sources.

## Releasing (maintainer)

```powershell
.\tools\make-release.ps1 -Version X.Y.Z   # bundles a TeXLib snapshot via git archive
git tag vX.Y.Z && git push --tags
gh release create vX.Y.Z dist\TeXLib-Installer-vX.Y.Z.zip dist\SHA256SUMS
```

Paste the CHANGELOG entry into the release notes.
