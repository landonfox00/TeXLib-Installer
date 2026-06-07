# TeXLib-Installer

One-click portable Windows installer for the [TeXLib](https://github.com/landonfox00/TeXLib) teaching library. Sets up Sublime Text, SumatraPDF, and TeX Live under `%LOCALAPPDATA%\TeXLib` (no admin needed), wires up LaTeXTools with the TeXLib custom builder, and deploys the library so `\documentclass{didactic}`, `{quiz}`, `{autoexam}`, etc. just work.

> Looking to **install** TeXLib on a coworker's machine? See [INSTALL.md](INSTALL.md). This README is for people maintaining the installer itself.

## What this installs

| Component | Source | Where it lands |
|---|---|---|
| Sublime Text 4 (portable) | https://download.sublimetext.com | `%LOCALAPPDATA%\TeXLib\Sublime Text` |
| SumatraPDF (portable) | https://www.sumatrapdfreader.org | `%LOCALAPPDATA%\TeXLib\Sumatra` |
| TeX Live (full, portable) | https://mirror.ctan.org/systems/texlive/tlnet | `%LOCALAPPDATA%\TeXLib\TexLive\2025` |
| Package Control | https://packagecontrol.io | Sublime user packages |
| LaTeXTools | https://github.com/SublimeText/LaTeXTools | Sublime packages |
| TeXLib library (bundled snapshot) | This repo's release ZIP | `<OneDrive>\Documents\TeXLib` (or `%USERPROFILE%\Documents\TeXLib` if no OneDrive) |

## Repo layout

```
.
├── install.ps1            # main installer (runs end-to-end install)
├── uninstall.ps1          # reverses install.ps1
├── install.bat            # wrapper: launches install.ps1 with ExecutionPolicy Bypass
├── uninstall.bat
├── templates/                   # config templates with {{...}} placeholders
│   ├── LaTeXTools.sublime-settings
│   ├── Preferences.sublime-settings
│   └── SumatraPDF-settings.txt
├── runtime/                     # build-from-Explorer feature (bundled into releases)
│   ├── texlib-build.ps1         # standalone PowerShell port of the texlib_builder recipe
│   ├── texlib-build-selected.ps1 # builds the .tex selected in File Explorer
│   └── TeXLibHotkey.cs          # resident Ctrl+B hotkey helper (opt-in)
├── tools/
│   ├── make-release.ps1         # builds the release ZIP (installer + TeXLib bundle)
│   ├── install_wrapper.ps1      # boot-log + always-pause wrapper for install.bat
│   └── uninstall_wrapper.ps1    # same, for uninstall.bat
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── bug_report.yml       # structured issue form for end-user bug reports
│   └── workflows/
│       └── lint.yml             # PSScriptAnalyzer on push/PR
├── PSScriptAnalyzerSettings.psd1 # lint rules used by lint.yml
├── INSTALL.md                   # end-user-facing install guide
├── TESTING.md                   # manual + automated test checklist
├── CHANGELOG.md
├── LICENSE
└── README.md                    # this file
```

## Installer flags

`install.ps1` (and `install.bat`, which forwards args) accepts:

| Flag | Effect |
|---|---|
| `-Silent` | Skip all interactive prompts. Safe defaults (skip if installed, abort on hash mismatch). Used for unattended deployment. |
| `-Doctor` | Skip install; diagnose an existing install and print a pass/warn/fail report. Pastes cleanly into bug reports. |
| `-Version` | Print installer version + bundled TeXLib version + currently-installed version metadata. Fast (no network). |
| `-DryRun` | Run pre-flight checks and print a plan of what would happen, without modifying the system. |
| `-OnlyTeXLib` | Refresh only the TeXLib library bundle + Sublime builder files. Skips Sublime / Sumatra / TeX Live install entirely. Use after pulling a newer installer release whose only change is the library. |
| `-InstallPath C:\path` | Override the install root. Defaults to `%LOCALAPPDATA%\TeXLib`. Use if `%LOCALAPPDATA%` is on a small SSD or locked down. |
| `-HideJunction` | Apply the hidden attribute to the `%USERPROFILE%\TeXLib` junction created on comma/space OneDrive paths. Off by default (a visible junction is easier to diagnose). |
| `-EnableBuildHotkey` | Also install the resident Ctrl+B Explorer build hotkey. Off by default; the right-click "Build with TeXLib" menu is always installed. |

Combine as needed (e.g. `-OnlyTeXLib -Silent` for unattended library refreshes on lab machines).

## How releases work

The installer needs a snapshot of TeXLib to deploy. We don't commit TeXLib into this repo (it has its own); instead, `tools/make-release.ps1` snapshots TeXLib at release time and bundles it into the release ZIP.

```powershell
.\tools\make-release.ps1 -Version 0.5.0
```

This produces `dist/TeXLib-Installer-v0.5.0.zip` and `dist/SHA256SUMS`. Upload both to a new GitHub Release.

End users download the ZIP, extract it, and run `install.bat`. The installer finds the bundled `texlib/` folder next to the script and deploys it.

## Refreshing component versions

The pinned versions in `install.ps1` (Sublime 4180, SumatraPDF 3.5.2, TeX Live 2025) are reproducible and known to work, but they go stale. To refresh:

1. Edit the `$Downloads` hashtable at the top of `install.ps1`.
2. For `Type = "Static"` entries, recompute the hash:
   ```powershell
   Get-FileHash <path-to-new-zip> -Algorithm SHA256
   ```
   and paste it into the `Hash` field.
3. Bump `$InstallerVersion`.
4. Add a `CHANGELOG.md` entry.
5. Run `tools/make-release.ps1 -Version <new>` and publish.

TeX Live's `texlive` entry uses `Type = "Dynamic"` — it fetches the upstream hash live at install time, so it doesn't need manual hash updates.

## Pre-staging downloads (for testing or offline installs)

If you drop the component ZIP files (e.g. `sublime_text_build_4180_x64.zip`) next to `install.ps1` before running it, the installer uses those local copies (after hash-verifying them) instead of re-downloading. Useful for repeated test installs without burning bandwidth.

## Hacking on the installer

- The installer **must** run cleanly with `-Silent` (no Read-Host prompts), since silent mode is what we'll use for lab-machine deployment later.
- Every major step is in a `try/catch` block and exits with a distinct code (see `Stop-Installer N` calls). Add new sections with their own exit codes; don't reuse existing ones.
- Logs land in `%LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log` via `Start-Transcript`. Always reference the log path in failure messages so users can attach it to issue reports.
- Pre-flight checks live in section 7 of `install.ps1`. Add new checks via `Add-PreflightFailure` (blocks install) or `Add-PreflightWarning` (advisory only).
- New doctor checks go in `Invoke-Doctor` (section 5). Use the `_Pass` / `_Warn` / `_Fail` helpers so the summary counters stay accurate.
- `PSScriptAnalyzer` runs on every push via `.github/workflows/lint.yml`. Run locally before pushing:
  ```powershell
  Install-Module PSScriptAnalyzer -Scope CurrentUser
  Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning, Error
  ```
- Before tagging a release, run the manual test pass in [TESTING.md](TESTING.md) (static checks → install → builds → uninstall → release ZIP).

## Why is this a separate repo from TeXLib?

Different audiences. TeXLib's users are developers of the library (forking, editing `.sty` files, contributing back). Installer users are *consumers* of the resulting setup — they don't need git, the smoke test, the CHANGELOG, etc. Keeping them separate keeps each surface clean.

## License

MIT — see [LICENSE](LICENSE). The components the installer pulls in have their own licenses (Sublime Text is commercial; TeX Live is mostly LPPL; LaTeXTools is MIT; the TeXLib library is MIT).
