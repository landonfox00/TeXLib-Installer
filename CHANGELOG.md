# Changelog

All notable changes to TeXLib-Installer are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions correspond to git tags.

## [Unreleased]

### Changed

- **Merged `tools\install_wrapper.ps1` + `tools\uninstall_wrapper.ps1` into one
  parameterized `tools\boot_wrapper.ps1`** (invoked as `boot_wrapper.ps1 install`
  / `boot_wrapper.ps1 uninstall`). The two were ~90% identical; the merge keeps
  every guarantee — boot-log capture, exit-code surfacing, pause-on-failure, and
  the install-specific log-location hint — while dropping ~90 duplicated lines.
  `install.bat` / `uninstall.bat` and `make-release.ps1`'s ship list updated to
  match.

### Removed

- **Speculative external-install detection** (~150 lines). The four
  `Find-Existing*` probes (system TeX Live / MiKTeX / Sublime / SumatraPDF) and
  their preflight notes were detect-and-report only — the installer always
  installs isolated portable copies regardless — and were groundwork for a
  `-UseSystemTeX` / `-UseSystemSumatra` reuse feature that isn't planned. The
  "existing TeXLib install detected" idempotency check (for the Skip/Reinstall
  prompt) is unchanged; preflight still reports that portable copies will be
  installed without touching any existing tools.

### Fixed

- **Uninstaller crashed on a no-arg launch** (the normal double-click) with
  `A positional parameter cannot be found that accepts argument '$null'`,
  aborting before removing anything. `tools\boot_wrapper.ps1` collects passthrough
  args via `ValueFromRemainingArguments`, which WinPS 5.1 leaves as `$null` (not
  an empty array) when none are given; splatting `$null` forwarded a lone
  positional `$null` to the inner script, and `uninstall.ps1` — whose only
  parameter is `[switch]$Silent` — had nothing to bind it to. (`install.ps1`
  escaped by luck: its `[string]$InstallPath` positional absorbed the stray
  `$null`.) The wrapper now coerces `$InnerArgs` to `@()` before the splat. Shipped
  in v0.6.0's `tools\uninstall_wrapper.ps1`; carried into the merged
  `boot_wrapper.ps1`. New `wrapper-arg-forwarding` CI job drives the real wrapper
  against a switch-only stub inner script to lock the fix in.

- **Install died at exit 10 with `Cannot overwrite the item ...
  texlib_builder.py with itself`** when reusing an already-synced TeXLib library.
  In that mode section 16 deployed the Sublime builder files from
  `<TeXLib>\Sublime`, which is also `$SublimeUserSync` — and `Packages\User` is
  junctioned to it, so every `Copy-Item` was a file-onto-itself copy. The
  installer aborted on the very last step with all four files already exactly
  where they belonged. It now skips the deploy when source and destination
  resolve to the same directory.

- **Update check told you to "update" to an older release.** `Test-LatestVersion`
  compared tags with `-ne`, so any build ahead of the newest published tag —
  the normal state while cutting a release — reported an update to the version
  behind it. Now compares parsed `[Version]` objects and warns only when the
  published tag is strictly newer (this also fixes `0.6.10` vs `0.6.9`, which
  string comparison got backwards). Falls back to string inequality for tags
  that don't parse.

- **Shortcut creation could write to the drive root.**
  `[Environment]::GetFolderPath("Desktop")` returns an empty string when the
  shell folder can't be resolved (redirected/roaming profiles, some service
  contexts); unguarded, `"$DesktopPath\$ShortcutName.lnk"` collapsed to
  `\Sublime.lnk`, which resolves to `C:\Sublime.lnk`. That fails noisily where
  the root isn't writable and succeeds *silently* where it is, littering `C:\`
  instead of creating shortcuts. Each folder is now skipped individually, with a
  warning, when it can't be resolved. Found by the first contained local run.

### Added

- **`-TeXLibPath` and `-Sandbox`.** `-InstallPath` only ever redirected
  `$BaseDir`; the library location, the user PATH entry, the HKCU file
  associations, and the Desktop / Start Menu shortcuts all still landed on the
  real machine, which made running the installer on a development box a
  snapshot-and-restore exercise. `-TeXLibPath` overrides where the library goes
  (and suppresses the `%USERPROFILE%\TeXLib` junction, since an explicit path is
  deliberate); `-Sandbox` skips exactly the three machine-state writes and
  nothing else, so the component install, library deploy, `Packages\User`
  junction, and builder config are all still exercised for real. `-DryRun` shows
  the skipped steps; `-Sandbox` without a redirect flag warns that components
  still install to their default locations.

- **`tools\dev-install-test.ps1`** — seeds a returning machine in a temp
  sandbox and drives a real full install through it twice (silent, then
  interactive with Skip answers on stdin), asserting 22 conditions including
  that nothing was written outside the sandbox. Runs in about a minute because
  the seeded component directories make the installer skip all four large
  downloads. Contained entirely by the new flags, so cleanup is deleting one
  directory. Documented in TESTING.md §1b; deliberately not shipped in the
  release bundle (asserted by `package-integrity`).

- **`reuse-existing-library` CI job** — covers the *returning* machine, which no
  other job did: every one of them staged a `texlib\` bundle and installed once
  onto a clean VM, so `$UseExistingTeXLib` was never true and the interactive
  `[S]kip or [R]einstall` prompts were dead code. Both install bugs above lived
  in exactly that gap. Seeding empty component directories makes the installer
  skip all four large downloads, so a real full (non-`-OnlyTeXLib`) install runs
  in about a minute. Covers, in one job: install with a library but no bundle,
  the junctioned-`Packages\User` self-copy, a non-silent re-run answering the
  Skip prompts on stdin, and teardown through `uninstall.bat` **with no
  arguments** — the double-click shape that produced the `$null`-splat crash and
  that invoking `uninstall.ps1` directly can never reproduce. `full-install`'s
  teardown now goes through `uninstall.bat` too.

## [0.6.1] — 2026-07-04

A Sublime-integration point release. Fixes the headline bug on a clean install — **Ctrl+B doing nothing** — by installing LaTeXTools' missing `regex` dependency and pinning Ctrl+B to the TeXLib build system. Also makes the installer **reuse a TeXLib library that's already synced** (OneDrive), so a source checkout or a copy without its `dist\` installs instead of hard-failing at pre-flight. Same bundled TeXLib library as v0.6.0 (`v0.3.0`); no library changes.

### Added

- **Detect an existing TeXLib library and reuse it, like the other components.**
  Pre-flight now treats the library the way it treats TeX Live / Sublime /
  SumatraPDF: if a valid library (core `.sty` files present) is already synced to
  the content location, the installer reuses it and skips deploying a bundle — so
  an installer copy with no bundled `texlib\` (a source checkout, or a copy synced
  without its `dist\`) installs instead of hard-failing. A bundled snapshot still
  takes priority when present, and `-OnlyTeXLib` still requires a bundle (its job
  is to push a newer one).

### Changed

- **Clearer "wrong download" failure** — the missing-bundle error now also names
  the release page's "Source code (zip)" link (not just "Code → Download ZIP")
  and reports whether an existing library was found. Reuse detection prints the
  library version, reading the first concrete `CHANGELOG.md` heading past
  `[Unreleased]`.
- **Ctrl+B is pinned to the TeXLib build system.** The Preferences template now
  sets `"build_system": "Packages/User/TeXLib.sublime-build"`. LaTeXTools ships
  `Compile to PDF.sublime-build` with the same `text.tex.latex` selector, so
  "Automatic" was ambiguous — and only TeXLib's build exposes the Ctrl+Shift+B
  mode variants (Answer Key / Solutions / Student / …).
- **Install verification and `-Doctor` now check the `regex` dependency**, so a
  broken Sublime build can't ship green (`install.ps1 -Doctor` reports it, and the
  end-of-install step warns if it's missing).

### Fixed

- **Ctrl+B now builds on a clean install — LaTeXTools' `regex` dependency is
  installed.** The installer drops LaTeXTools from a raw source archive (not via
  Package Control), so its declared dependency `regex` was never installed. On a
  machine with no prior Package-Control LaTeXTools, `latextools/utils/analysis.py`
  does a bare `import regex` that LaTeXTools' `plugin.py` triggers at load, so the
  import failed, **no** LaTeXTools command registered — including
  `latextools_make_pdf`, the target of `TeXLib.sublime-build` — and Ctrl+B did
  nothing at all. The installer now downloads and installs the hash-pinned `regex`
  wheel (cp38-win-amd64, Sublime 4's plugin-host ABI) into `<Sublime>\Data\Lib\python38`.
  (`mdpopups`, the other dependency, is imported guarded and only affects previews,
  so it is intentionally not installed in this fix.)

## [0.6.0] — 2026-06-26

Removes the build-a-`.tex`-from-Windows-Explorer feature and refreshes the bundled TeXLib library to v0.3.0.

### Changed

- **Bundled TeXLib refreshed to `v0.3.0`** (from `v0.2.0` in v0.5.1): syllabus section shortcuts (`\officehours`, `\communication`, `\academicintegrity`, …), a `\MetaHumanMonthDay` robustness fix, and two breaking removals — the syllabus command-style metadata shims and the library `\dd`/`\deriv`/`\inte` macros. See the TeXLib CHANGELOG for the full list.
- **`$InstallerVersion` / `$UninstallerVersion` bumped 0.5.1 → 0.6.0.**

### Removed

- **Build-a-`.tex`-from-Windows-Explorer feature, entirely.** Dropped the right-click "Build with TeXLib" context-menu flyout on `.tex`, the opt-in `-EnableBuildHotkey` Ctrl+B Explorer hotkey (the resident `TeXLibHotkey.exe` background process compiled from `TeXLibHotkey.cs`, plus its Startup shortcut), and the standalone `runtime/texlib-build.ps1` / `texlib-build-selected.ps1` builders (the `runtime/` folder is gone). `install.ps1` no longer registers the menu, compiles/launches the hotkey, or deploys the standalone builder + `texlib-build.config.psd1`; `uninstall.ps1` drops the matching cleanup (hotkey process, Startup shortcut, the `TeXLib.BuildMenu` ProgID, the `.tex` `TeXLibBuild` verb); `make-release.ps1` no longer bundles `runtime/`. Building a `.tex` is done from the editor — Sublime's Ctrl+B / the LaTeXTools "texlib" build — which is unchanged.

## [0.5.1] — 2026-06-26

Makes a fresh coworker install actually work. Three bugs each blocked the install at a different stage — Windows PowerShell 5.1 couldn't even *parse* the script (no BOM), then couldn't verify TeX Live, then couldn't verify the apps — so all three had to be fixed before an end-to-end install was possible. A new CI harness then ran the real install on a clean throwaway `windows-latest` VM, which surfaced two more verification-robustness fixes (CTAN mirror skew; a Doctor false-failure). Verified end-to-end: `install.ps1 -Silent` exits 0 with TeX Live, Sublime, SumatraPDF, LaTeXTools, the junction, and file associations all in place. This release also refreshes the bundled TeXLib library to **v0.2.0** (the large batch merged 2026-06-24/25 that v0.5.0, a 2026-06-07 snapshot, predated).

### Changed

- **Bundled TeXLib refreshed to `v0.2.0`.** This release carries the large library batch merged 2026-06-24/25 that v0.5.0 predated — the region-delimited bank format + multiple-choice redesign, repeatable `{problems}`/`{mcproblems}` sections, the layered metadata engine with coursemeta-driven exam dates, friendly "requires LuaLaTeX" guards, inline `\solution`/`\answer`/`\pf` lead-ins, shared `{hint}`/`{readings}` callouts, and an end-to-end example course. See the TeXLib CHANGELOG for the full list.
- **`make-release.ps1` records the bundled TeXLib commit + `git describe` in the `RELEASE` stamp** (`texlib_commit` / `texlib_describe`), so every installer release is traceable to an exact TeXLib state instead of only a source path.

### Added

- **`-VerifyDownloads` switch + `install-test.yml` CI.** A new early-exit mode downloads each pinned component and verifies its SHA256/512 against `$Downloads`, then exits 0 (all match) or 20 (drift), without installing anything, touching the registry/PATH/junction, or needing the texlib bundle. A GitHub Actions workflow runs it (plus a `-DryRun` sanity job and a gated real full-install job) on a clean `windows-latest` VM, so the next vendor repackage — or a regression of any of the fixes below — is caught on a throwaway machine before a coworker hits it. The workflow also guards against the BOM regression directly.
- **A `junction` CI job, a manual smoke checklist, and ASCII-only scripts.** The `junction` job fakes a comma/space OneDrive path and asserts the user-root junction is created and resolves correctly — the UNR-specific behavior a runner otherwise never reaches. `SMOKE-TEST.md` covers the interactive pieces CI can't activate headlessly (double-click `.tex` → Sublime, Ctrl+B build, viewer associations). And `install.ps1`/`uninstall.ps1` are now **ASCII-only** (em-dashes removed) with a `.gitattributes` pinning CRLF, so the BOM is a backstop rather than the only thing standing between a stray future edit and the WinPS-5.1 parse bug.

### Fixed

- **`install.ps1` / `uninstall.ps1` are now UTF-8 *with* BOM, so Windows PowerShell 5.1 can actually parse them.** Both files were saved UTF-8 *without* a BOM but contained em-dashes. Windows PowerShell 5.1 — what `install.bat` launches — decodes a BOM-less script as the system ANSI code page (Windows-1252), which mangles the multibyte characters into a parse error. The result: `& install.ps1` aborted *before executing a single line*, so a coworker double-clicking `install.bat` got a wall of red instead of an install. This affects shipped v0.5.0 as well. Verified the BOM'd files parse and run via both `-File` and the call-operator path the wrapper uses.
- **TeX Live's dynamic hash check no longer reads the expected hash as `50`.** Some CTAN mirrors serve `install-tl.zip.sha512` with `Content-Type: application/zip`, so `Invoke-WebRequest` returns `.Content` as a `byte[]` rather than a string. `($HashContent -split "\s+")[0]` then stringified the byte array and used `50` (the first byte's decimal value) as the expected SHA512 — guaranteeing a mismatch and aborting the TeX Live install (exit 5). The dynamic-hash path now decodes a `byte[]` response before splitting.
- **TeX Live hash verification is resilient to CTAN mirror skew.** `install-tl.zip` is a rolling artifact and `mirror.ctan.org` is a redirector, so fetching the zip and its `.sha512` in two separate requests could land on out-of-sync regional mirrors — pairing one version's hash with another version's zip and aborting a perfectly good install (exit 5) on a false mismatch. `Get-SourceFile` now resolves one concrete mirror up front and reads both the hash and the zip from it (falling back to the redirector URLs if resolution fails, so it can only help). `-VerifyDownloads` does the same, and treats any residual rolling-file mismatch as inconclusive (a mirror race) rather than re-pinnable drift — only a *static* pin can truly drift.
- **Doctor no longer false-reports `pdflatex not on PATH` right after install.** The check used `Get-Command pdflatex`, which only sees the *current* process's `$env:PATH` — but a just-added user-PATH entry isn't loaded until a new process starts, so running `-Doctor` in the same terminal as the install (or in CI) always `[FAIL]`ed even though TeX Live was installed and correctly added to the persisted PATH. Doctor now also checks the persisted user PATH (registry) plus the binary's presence, and reports `[OK]` with a "open a new terminal to use it" note instead of a scary failure.
- **Re-pinned the Sublime Text (build 4180) and SumatraPDF (3.5.2) SHA256 hashes.** Both vendors repackaged their archives in place — same version, new bytes — so the pinned hashes no longer matched what the URLs serve. Because the installer fails closed on a hash mismatch (no continue-anyway prompt), this aborted every fresh install at the first download, before anything was installed. Verified the new archives still contain exactly build 4180 (`sublime_text.exe` FileVersion 4180) and `SumatraPDF-3.5.2-64.exe`, and that both hashes are stable across repeated downloads, so this is a pure re-pin with no version drift. LaTeXTools (`st4-4.5.12`) was unaffected.
- **A transient CTAN mirror skew no longer aborts the install.** On a Dynamic (TeX Live) hash mismatch, `Get-SourceFile` now re-resolves a fresh concrete mirror and re-pulls the zip + `.sha512` a few times before failing — so a redirector that handed back mismatched rolling versions self-heals instead of killing an otherwise-good install. A *static* pin still fails immediately (that's real drift).
- **`-Doctor` exits non-zero when any check fails** (it always returned 0 before, so it couldn't gate automation), and **`uninstall.ps1` no longer hardcodes the TeX Live year** — it uses `$TexLiveYear` in lockstep with `install.ps1`, so a future year bump still cleans the old PATH entry on uninstall.
- **Clearer error when the installer is run from the GitHub *source* download.** The TeXLib library ships only in the release zip (assembled by `make-release.ps1`), not the repo source — so a coworker who clicks "Code → Download ZIP" got a confusing `TeXLib bundle not found ... partial download?` failure. Pre-flight now detects a source checkout (it has `.git`/`.github`/`tools\`, which a release zip doesn't) and says plainly: this is the source download, grab the release zip from the Releases page and run `install.bat` from inside it. A CI step asserts the guidance. (Surfaced by a real coworker install on 2026-06-15.)
- **The internet pre-flight check retries instead of hard-failing on a slow mirror.** `mirror.ctan.org` is a redirector to regional mirrors and can be briefly slow even on a good connection; a lone 5 s HEAD request would abort the entire install. It now tries 3 times with a 15 s timeout before declaring no connectivity.
- **Release bundles now include the `tools\` wrappers that `install.bat` needs.** `make-release.ps1` shipped `install.bat`/`uninstall.bat` but not the `tools\install_wrapper.ps1` / `tools\uninstall_wrapper.ps1` they invoke — so a *released* `install.bat` flashed open and closed instantly (PowerShell `-File` on a missing script): no install, no log. **Every prior release had this**, and CI missed it because the install jobs run `install.ps1` directly, not `install.bat`. A new `package-integrity` CI job now builds a bundle and actually launches `install.bat` from it. (Surfaced by a real coworker install on 2026-06-15.)

## [0.5.0] — 2026-06-07

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
- **`$UninstallerVersion`** bumped 0.2.0 → 0.5.0 (kept in lockstep with the installer). The uninstaller now removes `%USERPROFILE%\TeXLib` if and only if it is a reparse point — verified via `(Get-Item $path -Force).Attributes -match 'ReparsePoint'` to make sure a coworker's real `TeXLib` folder in their home directory is never recurse-deleted. Removal uses `[System.IO.Directory]::Delete($path, $false)` to drop the junction entry without following the link into the OneDrive target. It also stops the `TeXLibHotkey` process, removes its Startup shortcut, and deletes the `TeXLib.BuildMenu` store + `.tex` `TeXLibBuild` verb.

### Security

- **LaTeXTools is pinned to a tagged release (`st4-4.5.12`) with a SHA256**, replacing the unverified, ever-moving `master`-branch download. The installer no longer runs an unpinned, unhashed copy of the third-party Python that Sublime executes; a hash mismatch now fails the install closed. Update by bumping the tag + hash in the `$Downloads` table.
- **TLS 1.2 is forced** before any download (PowerShell 5.1 may otherwise negotiate TLS 1.0/1.1, which GitHub and several CDNs now reject).

### Fixed

- **`Stop-Installer` is defined above the section-1 user-root junction block.** It was called on the junction's failure paths (a real folder squatting at `%USERPROFILE%\TeXLib`, or a creation error) — which run at script load — but wasn't defined until ~130 lines later, so the installer crashed with "Stop-Installer is not recognized" on exactly the OneDrive comma/space case the feature exists to handle.
- **Downloads retry** (3× with backoff + 120 s timeout) so a campus Wi-Fi blip on the multi-hundred-MB TeX Live pull no longer hard-fails the whole install.
- **TeX Live install is verified** via `install-tl`'s exit code and the presence of `pdflatex.exe`; a failed install is now a hard stop, not a late non-fatal warning.
- **Scratch is always cleaned** — `Stop-Installer` removes `%TEMP%\TeXLib_Install` on every exit, so a failed run no longer strands multi-GB of downloads.
- **`$ErrorActionPreference = 'Stop'`** so an unguarded download/extract/copy error aborts instead of silently continuing into a half-built state.
- **Existing `Packages\User` is backed up before the destructive first-install sync move** (the prior backup only covered the not-yet-existing sync target).
- **Uninstall is a true reverse:** removes the per-extension association keys install created (`.tex/.cls/.sty/.bib/.pdf` and the hijacked `.txt`) when their default points at a TeXLib ProgID — previously left dangling at a deleted ProgID.
- **Building several `.tex` from Explorer opens only the last PDF** (was one SumatraPDF window per file); the `.spl` split verifies both halves exist before consuming the signal and reports clearly when `pypdf` is missing, instead of faking success.
- **Maintainability:** the SumatraPDF exe name is derived from the pinned zip (was hardcoded 5×) and the TeX Live year is centralized in `$TexLiveYear`.

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

[Unreleased]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.2.1...v0.5.0
[0.2.1]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.1.0
