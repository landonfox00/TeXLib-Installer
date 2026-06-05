# Changelog

All notable changes to TeXLib-Installer are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions correspond to git tags.

## [Unreleased]

The TEXINPUTS comma trap, finally fixed in code. kpathsea (TeX Live's file resolver) splits `TEXINPUTS` entries on commas and chokes on spaces, so the UNR OneDrive folder ("OneDrive - University of Nevada, Reno") has silently broken every install on a UNR machine since v0.1.0. Landon hand-created a junction at `%USERPROFILE%\TeXLib` to work around it; coworkers didn't know to. v0.2.0's Doctor mode only printed a TEXINPUTS warning — useful diagnosis, no actual repair.

### Added

- **Automatic user-root junction at `%USERPROFILE%\TeXLib`** whenever the resolved OneDrive `Documents\TeXLib` path contains a space or comma. Reassigns `$TeXLibDir` to the junction path before any downstream consumer reads it, so the LaTeXTools template, deploy target, version stamp, `TEXINPUTS` exports, and the doctor all see a clean comma/space-free path. Created with `New-Item -ItemType Junction` (same pattern as the existing `Data\Packages\User` junction). Idempotent across re-runs: an existing junction at that path is trusted and reused; a non-junction folder there is treated as user content and the installer aborts rather than overwrite.
- **`-HideJunction` switch** in `install.ps1` that applies the `+h` (hidden) file attribute to the new junction after creation. Off by default — a visible junction is easier to discover and diagnose.
- **Doctor mode reports the junction state** under "LaTeX environment": `[OK]` when the junction is present and points at the OneDrive target, `[FAIL]` when it should exist but doesn't, or when something non-junction is squatting on the path. Replaces v0.2.0's TEXINPUTS comma-trap warning (which only diagnosed; the junction check actually tells you what to do).
- **DryRun plan and OneDrive pre-flight note** mention the junction when it would be created or is already in use, so coworkers seeing the new folder in their home directory can match it to a plan item rather than wondering what put it there.
- **Build a `.tex` from File Explorer, no editor open.** A new `runtime/texlib-build.ps1` is a standalone PowerShell port of the `texlib_builder.py` recipe — `%!TeX root`/`%!TeX program` resolution, lualatex-class detection, build-mode `\def` macros, `-synctex`/`-output-directory` aux routing (sharing the editor's `<<temp>>` aux dir so cross-references stay warm), the "Rerun to get … right." + biber rerun loop, copy-back of the PDF/`.synctex.gz`/`.spl`, the `.spl` PDF split, and hiding the `.synctex.gz`. Driven two ways:
  - **Right-click "Build with TeXLib" flyout on `.tex`** (every install). A per-user `ExtendedSubCommandsKey` submenu — Build / Answer Key / Solutions / Student Copy / Rubric / Draft / All Versions — registered under `HKCU:\…\SystemFileAssociations\.tex\shell\TeXLibBuild`; no admin, no COM handler. On success the PDF opens in SumatraPDF; on failure a toast fires and the engine `.log` opens.
  - **`-EnableBuildHotkey` opt-in Ctrl+B** (`runtime/TeXLibHotkey.cs`). A ~30 KB resident helper, compiled at install with the in-box .NET `csc.exe`, installs a `WH_KEYBOARD_LL` hook that fires **only** while a File Explorer window is foreground (so Ctrl+B still means bold everywhere else), reads the selection via `Shell.Application`, and builds the selected `.tex`. Auto-starts via a per-user Startup shortcut. Opt-in so default coworker installs stay lean and avoid AV questions about a login-launched background process.
- **`runtime/` bundled into release ZIPs** by `tools/make-release.ps1`, and `texlib-build.ps1` + its resolved-paths `texlib-build.config.psd1` deployed to `%LOCALAPPDATA%\TeXLib\Scripts` on every install (including `-OnlyTeXLib` refreshes, so the standalone recipe tracks the editor builder).

### Changed

- **`$InstallerVersion`** bumped 0.3.1 → 0.5.0. Adds the build-from-Explorer feature on top of the junction fix.
- **`$UninstallerVersion`** bumped 0.2.0 → 0.4.0. The uninstaller now removes `%USERPROFILE%\TeXLib` if and only if it is a reparse point — verified via `(Get-Item $path -Force).Attributes -match 'ReparsePoint'` to make sure a coworker's real `TeXLib` folder in their home directory is never recurse-deleted. Removal uses `[System.IO.Directory]::Delete($path, $false)` to drop the junction entry without following the link into the OneDrive target. It also stops the `TeXLibHotkey` process, removes its Startup shortcut, and deletes the `TeXLib.BuildMenu` store + `.tex` `TeXLibBuild` verb.

## [0.3.1] — 2026-05-28

Bundle release: ships a curated LaTeX-only spell-check dictionary.

### Added

- **`texlib/Sublime/LaTeX.sublime-settings`** in the TeXLib bundle — a syntax-scoped settings file with ~430 mathematician names + standard math terminology + LaTeX command fragments under `added_words`, and the usual LaTeX layout dimensions under `ignored_words`. Sourced from Landon's accumulated personal list, deduped, alphabetized, augmented with ~110 standard mathematician names and ~280 standard algebra/analysis/topology/geometry terms. Stacks on top of the user's global `Preferences.sublime-settings`, so personal proper nouns (collaborators, lab references, course-internal jargon) still apply when editing `.tex` files. Stuck-suffix artifacts (`ness`, `th`, `ech`, `lder`) intentionally excluded — they mask real typos; the accented forms (`Čech`, `Hölder`) are included instead.
- **Deploy hook in `install.ps1` section 16b** — `LaTeX.sublime-settings` is now copied to `Packages/User/` alongside `texlib_builder.py`, `TeXLib.sublime-build`, and `Default.sublime-commands`.

## [0.3.0] — 2026-05-28

Robustness release: the previous .bat -> PowerShell -File invocation closed the console window on early failure, eating both the error message and the log path. After a coworker tried v0.2.1 on a locked-down work PC and hit exactly this trap (red text, window gone, no log), the .bat layer was reworked to always capture output and always pause on non-zero exit.

### Added

- **`tools/install_wrapper.ps1` + `tools/uninstall_wrapper.ps1`** — bootstrap layer that runs in front of `install.ps1` / `uninstall.ps1`. Captures the inner script's merged output (`*>&1 | Tee-Object`) to a timestamped boot log in `%TEMP%\TeXLib-Installer-boot-<stamp>.log` (or `TeXLib-Uninstaller-boot-<stamp>.log`) BEFORE the inner script starts, so a crash during param-binding, environment-variable detection, or directory creation still produces an attachable log. Catches uncaught exceptions and surfaces them as exit code 99 with stack trace.
- **Unconditional pause on non-zero exit** in both wrappers, with a banner that points the user at the boot log path and the issue tracker. Replaces the old "window closes silently" failure mode.
- **`$env:TEXLIB_INSTALLER_WRAPPED` sentinel** so the inner `Stop-Installer` / `Stop-Uninstaller` functions know the wrapper is handling the prompt and skip their own, avoiding a double "Press Enter to close." Direct PowerShell invocations (no .bat) still see the inner prompt.

### Changed

- **`install.bat` / `uninstall.bat`** reduced to two-line wrappers that call into the new `tools\*_wrapper.ps1` scripts. All robustness logic now lives in reviewable PowerShell rather than .bat redirection trickery.
- **`$UninstallerVersion`** bumped 0.1.0 -> 0.2.0 to reflect the prompt-skip change.

## [0.2.1] — 2026-05-23

Patch release: Phase A external-install detection + CI lint cleanup.

### Added

- **External-install detection in pre-flight** (Phase A of the "polite tenant" design). Pre-flight now actively looks for an existing Sublime Text, SumatraPDF, TeX Live, and MiKTeX install in standard locations (App Paths registry, Sublime/TL/MiKTeX-specific registry keys, common Program Files / LocalAppData paths, PATH) and reports each finding. Behavior is unchanged in this version — the installer still always installs portable copies of every component — but the foundation is in place for Phase B, which will let users reuse detected TeX Live and SumatraPDF installs via `-UseSystemTeX` / `-UseSystemSumatra` flags. Sublime will always be installed isolated because making the texlib builder work in a user's existing Sublime requires modifying their config (against the polite-tenant philosophy).
- **`Add-PreflightNote` helper** for indented, dim-text continuation lines under a pre-flight `[OK]` / `[WARN]` line. Improves readability of multi-line pre-flight messages.

### Changed

- **`[WARN]` on "another LaTeX install detected" → `[OK]` with explanatory note.** The old phrasing implied the existing install was a problem; with detection in place, it's now correctly framed as a future opportunity ("future `-UseSystemTeX` flag will let you reuse it without re-downloading").

### Fixed

- CI lint failures from v0.2.0: added `PSScriptAnalyzerSettings.psd1` excluding `PSAvoidUsingWriteHost` (intentional for installer-style colored output), replaced `Test-NetConnection` with `Invoke-WebRequest` HEAD probe (avoids the analyzer's hardcoded-ComputerName false positive), made empty catch blocks explicit.

## [0.2.0] — 2026-05-23

QoL features for distributing to coworkers: diagnostic mode, dry-run, library-only refresh, custom install path, update notifications, automatic settings backup, and CI lint.

### Added

- **`-Doctor` mode** — diagnoses an existing install (`install.bat -Doctor`). Reports pass/warn/fail for install location, components, PATH integrity, TeXLib library presence, Sublime junction, builder deployment, LaTeXTools settings, TEXINPUTS comma-trap, and file associations. Output formatted for copy-paste into bug reports.
- **`-Version` mode** — prints installer version, bundled TeXLib version, and currently-installed metadata. No network calls.
- **`-DryRun` mode** — runs pre-flight checks and prints the install plan without modifying anything. Useful for piloting on a new machine.
- **`-OnlyTeXLib` switch** — refreshes only the TeXLib library bundle + Sublime builder files. Skips Sublime / Sumatra / TeX Live install entirely. Combine with `-Silent` for lab-machine deployments. Cuts a "just update the library" refresh from ~45 minutes to ~5 seconds.
- **`-InstallPath` parameter** — override the default `%LOCALAPPDATA%\TeXLib` install root. For users with small `%LOCALAPPDATA%` drives or Group Policy restrictions.
- **Update checker** — best-effort hit to the GitHub Releases API on launch. Prints `Update available: v0.X is the latest release` when a newer release exists. Never fatal; silent on offline.
- **Sublime settings backup** — every install run ZIPs `<TeXLib>\Sublime` to `<install>\Logs\sublime-user-backup-<timestamp>.zip` before touching anything. Cheap insurance against accidental wipes.
- **TeX Live install heartbeat** — replaces the silent 30-60-minute wait with a "still going, X.Y min elapsed" line every 30 seconds. Eliminates the "is it frozen?" concern.
- **PSScriptAnalyzer in CI** — `.github/workflows/lint.yml` runs on push/PR; fails the build on errors, surfaces warnings.
- **Structured bug-report issue form** — `.github/ISSUE_TEMPLATE/bug_report.yml` mandates installer version, Windows version, failing step (dropdown), Doctor output, and install-log excerpt. End users get a guided form instead of a blank textarea.

### Changed

- **Sublime "Reinstall" warning** corrected: was "wipes settings", now accurately reflects that user settings live in `TeXLib\Sublime` via the junction and are preserved across reinstalls. Only the Sublime binary, LaTeXTools install, and Installed Packages get re-fetched.
- **Pre-flight disk-space check** loosened to 200 MB in `-OnlyTeXLib` mode (since no TeX Live download).
- **Pre-flight internet check** skipped in `-OnlyTeXLib` mode (no downloads).
- **VERSION file** now also records `last_mode` (full vs only-texlib) so the next install can warn about partial states.

## [0.1.0] — 2026-05-23

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

[Unreleased]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.3.1
[0.3.0]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.3.0
[0.2.1]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.2.1
[0.2.0]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.2.0
[0.1.0]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.1.0
