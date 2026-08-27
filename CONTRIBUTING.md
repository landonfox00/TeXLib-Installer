# Contributing to TeXLib-Installer

This repo builds a portable Windows installer (Sublime Text + SumatraPDF +
TeX Live + the [TeXLib](https://github.com/landonfox00/TeXLib) library) for
non-technical colleagues. The audience matters: changes should keep the install
**robust and self-explanatory on a locked-down Windows machine**.

> Only installing TeXLib? See the [install guide](INSTALL.md). This file is for people working on the installer itself. For the day-to-day layout, see the [README](README.md); for the test checklist, see [TESTING.md](TESTING.md).

## Ground rules

- **Branch off `main`** with a descriptive name; don't push to `main` directly.
- **One logical change per commit**, present-tense scoped messages
  (`fix(install): …`, `docs: …`).
- **Update `CHANGELOG.md`** under `## [Unreleased]` (Keep a Changelog). The
  installer and uninstaller version strings (`$InstallerVersion` in
  `tools/install.ps1`, `$UninstallerVersion` in `tools/uninstall.ps1`) are kept
  in lockstep.

## PowerShell conventions

- Scripts target **PowerShell 5.1** (the Windows-in-box version). Avoid 7+-only
  syntax (ternary, `??`, `&&`/`||` chaining).
- Set `$ErrorActionPreference = 'Stop'` and guard tolerated failures explicitly
  (`-ErrorAction SilentlyContinue` / `try`/`catch`).
- `tools/install.ps1` and `tools/uninstall.ps1` are UTF-8 **with** a BOM, and
  the `encoding-guard` CI job enforces it. Without the BOM, Windows PowerShell
  5.1 — which the `.bat` entry points launch — decodes any non-ASCII byte (an em dash in
  a message, say) as Windows-1252 and aborts with a parse error before running a
  line. That shipped once, in v0.5.0. Prefer `--` over em dashes in new script
  text anyway; the BOM is the belt to that suspenders.
- The `.ps1` files live in `tools/`, not at the repo root, so an extracted release folder offers exactly two clickable things: `install.vbs` and `uninstall.vbs`. Anything a script reads (`templates/`, an optional `texlib/` override tree, pre-staged component ZIPs) is resolved from the root, one level up.
- Downloads must verify a SHA256/SHA512 and fail closed on mismatch; pin
  third-party code to a tag/commit (never a moving branch).

## Test before you open a PR

- **Lint** (CI runs this; fails only on Errors):

  ```powershell
  Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
  Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
  ```

- **Dry run** (no system changes): `tools\install-console.bat -DryRun` (or
  `powershell -File tools\install.ps1 -DryRun`).
- **Doctor** (diagnose an existing install): `tools\install-console.bat -Doctor`.
- **Contained end-to-end run:** `powershell -File tools\dev-install-test.ps1`.
  Builds a returning-machine sandbox and installs into it twice; contained
  entirely by `-InstallPath` / `-TeXLibPath` / `-Sandbox`, so cleanup is deleting
  one directory. Never use the uninstaller to clean up a local test — it rewrites
  HKCU associations and the user PATH regardless of `-InstallPath`.
- **Manual checklist:** work through the [manual test checklist](TESTING.md). A real end-to-end install on a clean machine is the gold standard before any release that touches download/extract/configure logic — it's the one path CI can't cover.

### Write CI steps

- A `shell: pwsh` step propagates `$LASTEXITCODE` when it ends. Any step whose
  **last** child process is meant to exit non-zero — asserting that `-Verify`
  returns 22, or that `-Repair` refuses without an install — must end with an
  explicit `exit 0`, or it fails for passing. This has bitten three times.
- Don't put `2>&1` or `2>$null` on a native command. Windows PowerShell wraps
  each stderr line in an ErrorRecord, and with the script-wide
  `$ErrorActionPreference = 'Stop'` that becomes a *terminating* error. It is
  how the Doctor's package check ended up reporting all 50 packages missing on a
  healthy install.

## Refresh component versions

The pinned versions live in the `$Downloads` table at the top of `tools/install.ps1`; the header documents the refresh steps (new URL → recompute hash → bump version → CHANGELOG → re-release). The SumatraPDF exe name derives from its zip name — update that single source. The TeX Live tree year is derived at install time from the downloaded installer; the `$TexLiveYear` constant is only the fallback of last resort.

## Release a new version (maintainer)

```powershell
.\tools\make-release.ps1 -Version X.Y.Z   # builds the release ZIP (installer scripts only; the library is not bundled)
git tag vX.Y.Z && git push --tags
gh release create vX.Y.Z dist\TeXLib-Installer-vX.Y.Z.zip dist\SHA256SUMS
```

Paste the CHANGELOG entry into the release notes.
