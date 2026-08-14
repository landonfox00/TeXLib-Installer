# TeXLib-Installer

One-click portable Windows installer for the [TeXLib](https://github.com/landonfox00/TeXLib) teaching library. Sets up Sublime Text, SumatraPDF, and TeX Live under `%LOCALAPPDATA%\TeXLib` (no admin needed), wires up LaTeXTools with the TeXLib custom builder, and deploys the library so `\documentclass{didactic}`, `{quiz}`, `{autoexam}`, etc. just work.

> Looking to **install** TeXLib on a coworker's machine? See [INSTALL.md](INSTALL.md). This README is for people maintaining the installer itself.

## What this installs

| Component | Source | Where it lands |
|---|---|---|
| Sublime Text 4 (portable) | https://download.sublimetext.com | `%LOCALAPPDATA%\TeXLib\Sublime Text` |
| SumatraPDF (portable) | https://www.sumatrapdfreader.org | `%LOCALAPPDATA%\TeXLib\Sumatra` |
| TeX Live (full, portable) | https://mirror.ctan.org/systems/texlive/tlnet | `%LOCALAPPDATA%\TeXLib\TexLive\2025` |
| LaTeXTools | https://github.com/SublimeText/LaTeXTools | Sublime packages |
| TeXLib library | https://github.com/landonfox00/TeXLib (pinned tag) | `%LOCALAPPDATA%\TeXLib\Library` |

Everything lands under one root, which is what makes uninstall a single directory removal. Before 0.6.3 the library went to `<OneDrive>\Documents\TeXLib`; see [CHANGELOG.md](CHANGELOG.md) for why it moved and how upgrades migrate.

## Repo layout

```
.
├── install.bat                  # THE installer -- graphical, what to double-click
├── uninstall.bat                # THE uninstaller -- graphical, pick what goes
├── templates/                   # config templates with {{...}} placeholders
│   ├── LaTeXTools.sublime-settings
│   ├── TeXLib.sublime-settings  # native plugin's texinputs -- how Ctrl+B finds the classes
│   ├── Preferences.sublime-settings
│   └── SumatraPDF-settings.txt
├── tools/
│   ├── install-console.bat      # console installer -- scriptable surface, what CI drives
│   ├── uninstall-console.bat    # console uninstaller
│   ├── install.ps1              # main installer (runs end-to-end install)
│   ├── install-gui.ps1          # WPF front-end: collects options, runs install.ps1 -Silent, shows progress
│   ├── uninstall-gui.ps1        # WPF front-end: pick components, runs uninstall.ps1 -Silent
│   ├── uninstall.ps1            # reverses install.ps1
│   ├── boot_wrapper.ps1         # boot-log + always-pause wrapper for the console entry points
│   ├── make-release.ps1         # builds the release ZIP (installer scripts only)      [not shipped]
│   └── dev-install-test.ps1     # contained local end-to-end test harness              [not shipped]
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

The release root holds **exactly two** files you can click, and as of 0.11.0 both are the graphical ones: `install.bat` → `tools/install-gui.ps1` and `uninstall.bat` → `tools/uninstall-gui.ps1`. Everything else lives in `tools/`, including the console entry points. Before 0.11.0 the root carried four `.bat` files and the two plainest names were the *console* ones, so the file a first-time user was likeliest to double-click was the one meant for scripting.

The console surface did not go away, it moved: `tools/install-console.bat` → `tools/boot_wrapper.ps1` → `tools/install.ps1`. That is what CI drives and what `-Repair`, `-Doctor`, `-Verify`, `-Update` and `-Silent` are documented against. CI asserts both chains, that the root holds those two `.bat` files and nothing else, and that no `.ps1` sits at the root — `install.bat` next to `install.ps1` reliably got people running the wrong one.

The TeXLib library is **not bundled**. Since 0.11.0 `install.ps1` downloads a pinned tag of [TeXLib](https://github.com/landonfox00/TeXLib) and hash-verifies it, exactly like Sublime Text, SumatraPDF, TeX Live and LaTeXTools. The pin lives in the `texlib` entry of `$Downloads`, alongside `$TeXLibZipDir` (GitHub drops the leading `v` from the tag when naming the folder inside the archive) and `$TeXLibVersion`. CI asserts all three agree, because a bump that updates one and not the others fails *after* the user has waited for the download.

Bundling coupled two projects' release cadences: a library fix meant cutting an installer release, and every installer release had to choose which snapshot of a separate repo to freeze. A `texlib\` directory next to the release root still overrides the pin, which covers older release folders, air-gapped machines, and testing an unreleased library without cutting a tag.

Whatever the source, `Copy-LibraryTree` filters it: `.git`, `.github`, `__pycache__`, `test_*.py` and `_testkit.py` are dropped **at any depth**. That matters because `Packages\User` is a junction to the library's `Sublime\` folder and Sublime loads every top-level `.py` there as a plugin — which is how the author's test suite twice killed `plugin_host-3.8`. `Copy-Item -Recurse -Exclude` does not filter nested items, which was survivable only while `make-release.ps1` curated the bundle.

`tools/install-gui.ps1` is a **front-end, not a second installer**. It builds an argument list, runs `install.ps1 -Silent` as a child process, and tails that process's output into a log pane. Every decision about what to install and what to write stays in `install.ps1`, which is still the only thing the install jobs in CI exercise — if the two ever disagree, `install.ps1` is right.

`tools/uninstall-gui.ps1` is the same arrangement over `uninstall.ps1`. Per-component removal is not new — the console has confirmed Sublime Text, SumatraPDF, TeX Live and the library separately since 0.6.x — the window just puts a form over the `-Keep*` switches that choice already had. Note the polarity: the tick boxes say **remove**, the switches say **keep**, so the GUI inverts them in one place and CI asserts the wiring, because getting it backwards deletes a 6 GB tree someone meant to keep.

The coupling that can rot silently is each GUI's phase table: they recognise the console banners to drive their progress bars, so renaming a banner leaves a run that works correctly behind a bar that never moves. The `gui` CI job asserts every marker still tracks its script — literally for the ones printed as constants, and via a declared `Emit` construct for those composed at runtime (`"Downloading $($Info.File)..."`, `"Removing $Label ($Path)..."`).

## Installer flags

`tools/install.ps1` (and `tools/install-console.bat`, which forwards args) accepts:

| Flag | Effect |
|---|---|
| `-Silent` | Skip all interactive prompts. Safe defaults (skip if installed, abort on hash mismatch). Used for unattended deployment. |
| `-Doctor` | Skip install; diagnose an existing install and print a pass/warn/fail report. Pastes cleanly into bug reports. |
| `-Version` | Print installer version + the pinned TeXLib version it would fetch + currently-installed version metadata. Fast (no network). |
| `-DryRun` | Run pre-flight checks and print a plan of what would happen, without modifying the system. |
| `-OnlyTeXLib` | Fetch the pinned TeXLib library and refresh the Sublime builder files. Skips Sublime / Sumatra / TeX Live entirely. |
| `-Repair` | Re-apply configuration to an existing install: settings junction, builder files, Sublime package, app settings, file associations (with the stale Open With purge), shortcuts. No downloads, no components, library untouched. Works offline. |
| `-Update` | Fetch the newest release, verify it against its `SHA256SUMS`, and hand off to it. All your other arguments are forwarded. |
| `-TexLiveScheme full\|medium\|basic` | TeX Live size. `full` (default, about 6 GB) is what TeXLib is tested against; `medium` measured **1.3 GB / 25.5 min** here, `basic` about 0.6 GB. Saves disk reliably, time much less so — the install is dominated by CTAN mirror speed. **`basic` is missing 30 of the 50 packages TeXLib needs**, so run `-Doctor` after any non-full install. |
| `-Verify` | Check the install against the manifest written when it was made; reports files missing, changed, or added. Exit 22 if anything is missing or changed. |
| `-Reinstall Sublime\|SumatraPDF\|TeXLive\|All` | Replace the named components even though they are already installed; anything not named is still left alone. Comma-separated. This is what makes a *partial* reinstall possible without a human at the keyboard — `-Silent` on its own skips every installed component. A plain string, not a `[string[]]`: `powershell.exe -File install.ps1 -Reinstall Sublime,TeXLive` does no array parsing, and that is how the GUI invokes it. |

A `texlib.config.json` next to `install.bat` presets any of these — useful for lab deployment. Explicit command-line arguments always win:

```json
{ "InstallPath": "D:\\TeXLib", "TexLiveScheme": "medium", "Silent": true }
```
| `-InstallPath C:\path` | Override the install root. Defaults to `%LOCALAPPDATA%\TeXLib`. Use if `%LOCALAPPDATA%` is on a small SSD or locked down. The library follows it (`<InstallPath>\Library`). |
| `-TeXLibPath C:\path` | Override where the library lives. Also suppresses the junction and any pre-0.6.3 migration — an explicit path is taken as deliberate. |
| `-Sandbox` | Skip every write outside `-InstallPath` / `-TeXLibPath` (PATH, HKCU associations, shortcuts). For developing *on* the installer. |
| `-HideJunction` | Apply the hidden attribute to the `%USERPROFILE%\TeXLib` junction, which is created only when the library path contains a space or comma. Off by default (a visible junction is easier to diagnose). |

Combine as needed (e.g. `-OnlyTeXLib -Silent` for unattended library refreshes on lab machines).

## Uninstaller flags

`tools/uninstall.ps1` (and `tools/uninstall-console.bat`) accepts:

| Flag | Effect |
|---|---|
| `-Silent` | No prompts. Removes the programs; leaves a pre-0.6.3 library and an unclaimed junction. |
| `-All` | Remove everything with no per-component prompts. Implies `-RemoveLibrary` and `-RemoveJunction`. |
| `-InstallPath C:\path` | Uninstall an install rooted somewhere other than `%LOCALAPPDATA%\TeXLib`. |
| `-RemoveLibrary` | Answer yes to the library question up front. Only changes anything for a library *outside* the install root (a pre-0.6.3 `Documents\TeXLib`) — the one case that defaults to staying. |
| `-KeepSublime` / `-KeepSumatra` / `-KeepTeXLive` | Leave that component in place. Keeping TeX Live saves re-downloading ~6 GB, which is typically 30-60 minutes. |
| `-Force` | Close running Sublime / SumatraPDF without asking (they hold locks that would otherwise fail the removal). |
| `-RemoveJunction` | Remove `%USERPROFILE%\TeXLib` even when the installer cannot prove it created it. Check where it points first. |

An interactive run asks about each component, so the flags are only needed for unattended use.

## How releases work

The installer needs a snapshot of TeXLib to deploy. We don't commit TeXLib into this repo (it has its own); instead, `tools/make-release.ps1` snapshots TeXLib at release time and bundles it into the release ZIP.

```powershell
.\tools\make-release.ps1 -Version 0.5.0
```

This produces `dist/TeXLib-Installer-v0.5.0.zip` and `dist/SHA256SUMS`. Upload both to a new GitHub Release.

End users download the ZIP, extract it, and run `install.bat`. The installer finds the bundled `texlib/` folder at the release root (one level up from `tools/`) and deploys it.

## Refreshing component versions

The pinned versions in `tools/install.ps1` (Sublime 4200, SumatraPDF 3.5.2, TeX Live 2025) are reproducible and known to work, but they go stale. To refresh:

1. Edit the `$Downloads` hashtable at the top of `tools/install.ps1`.
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

If you drop the component ZIP files (e.g. `sublime_text_build_4200_x64.zip`) at the repo/release root (next to `install.bat`, *not* inside `tools/`) before running it, the installer uses those local copies (after hash-verifying them) instead of re-downloading. Useful for repeated test installs without burning bandwidth.

## Hacking on the installer

- The installer **must** run cleanly with `-Silent` (no Read-Host prompts), since silent mode is what we'll use for lab-machine deployment later.
- Every major step is in a `try/catch` block and exits with a distinct code (see `Stop-Installer N` calls). Add new sections with their own exit codes; don't reuse existing ones.
- Logs land in `%LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log` via `Start-Transcript`. Always reference the log path in failure messages so users can attach it to issue reports. The **uninstall** log deliberately goes to `%TEMP%\TeXLib-Uninstall\` instead — a transcript open inside the tree you are deleting aborts the removal partway through, which is the bug 0.6.3 fixed.
- Pre-flight checks live in section 7 of `tools/install.ps1`. Add new checks via `Add-PreflightFailure` (blocks install) or `Add-PreflightWarning` (advisory only).
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
