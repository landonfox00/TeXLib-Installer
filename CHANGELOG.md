# Changelog

All notable changes to TeXLib-Installer are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions correspond to git tags.

## [Unreleased]

_Nothing yet._

## [0.1.0] — 2026-05-22

Initial release. Reorganized and hardened port of the OneTeX installer (now archived at https://github.com/landonfox00/OneTeX), aimed at distribution to coworkers rather than personal use.

### Added

- **Portable per-user install** under `%LOCALAPPDATA%\TeXLib`. No admin rights required.
- **Hash-verified downloads** of Sublime Text, SumatraPDF, TeX Live. Aborts on mismatch (no continue-anyway prompts).
- **Pre-flight checks** for Windows version (>= 1809), PowerShell version (>= 5.1), free disk space (>= 6 GB), internet connectivity, and conflicting LaTeX installs.
- **`Start-Transcript` logging** — every install writes a complete log to `%LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log`. Failure messages reference the log path so users can attach it to issue reports.
- **`try/catch` around every major step** with distinct exit codes per phase, so failures are diagnosable from the log.
- **`-Silent` switch** for unattended installs.
- **End-of-install verification** — compiles a tiny LaTeX file to confirm the install works before reporting success.
- **Version stamp** at `%LOCALAPPDATA%\TeXLib\VERSION` recording installer version, install timestamp, and key paths.
- **OneDrive smart-detection** with fallback to `%USERPROFILE%\Documents`. Reports which mode is active.
- **Junction-based Sublime settings sync** so editor settings travel between machines through OneDrive.
- **Templated configurations** (`templates/LaTeXTools.sublime-settings`, `Preferences.sublime-settings`, `SumatraPDF-settings.txt`) with `{{SUMATRA_EXE}}` / `{{SUBLIME_EXE}}` / `{{TEX_PATH}}` / `{{TEX_LIB}}` placeholders that get substituted at install time.
- **Registry-based file associations** for `.tex` / `.cls` / `.sty` / `.bib` / `.pdf` (HKCU only; no admin needed).
- **Paired uninstaller** that reverses PATH, registry, shortcuts, and install directory while preserving `Documents\TeXLib`.
- **`tools/make-release.ps1`** — assembles the release ZIP (installer + bundled TeXLib snapshot) and a `SHA256SUMS` companion file, ready to attach to a GitHub Release.
- **End-user `INSTALL.md`** with screenshots-by-narration, SmartScreen workaround, troubleshooting section, and explicit log-attachment instructions for support.

### Component versions

- Sublime Text Build 4180 (`SHA256: 6B6B...A911F`)
- SumatraPDF 3.5.2 (`SHA256: 78D6...C58B`)
- TeX Live 2025 (`SHA512` fetched live from CTAN)
- LaTeXTools (master branch at install time)
- Package Control (latest from packagecontrol.io at install time)

### Removed (vs. OneTeX)

- "Continue anyway?" prompt on hash mismatch (was a security footgun).
- Final `Pause` at end of install (anti-pattern; replaced with conditional Read-Host on failure only).
- Legacy `SublimeUser` folder references (TeXLib now uses `Sublime/` as the canonical sync location).

[Unreleased]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.1.0
