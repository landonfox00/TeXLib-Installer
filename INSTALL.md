# Installing TeXLib on Windows

A guided walkthrough for installing the TeXLib teaching library on your Windows machine. Should take ~45 minutes start to finish (most of that is TeX Live downloading).

> If something goes wrong, scroll to [Troubleshooting](#troubleshooting) or open an issue at https://github.com/landonfox00/TeXLib-Installer/issues.

## Before you start

You need:

- **Windows 10 (version 1809 or newer) or Windows 11.** Run `winver` to check.
- **~6 GB of free disk space.** TeX Live full is big.
- **A working internet connection.** The installer downloads ~3 GB during the run.
- **PowerShell 5.1 or newer.** Comes pre-installed on every supported Windows version.
- **No admin rights required.** Everything installs into your user profile.

Optional but recommended:

- **OneDrive** — if you have OneDrive set up on this machine, the installer will put the TeXLib library inside your OneDrive folder so it syncs across machines automatically.

## Step 1 — Download the installer

1. Go to https://github.com/landonfox00/TeXLib-Installer/releases.
2. Click the latest release (top of the list).
3. Download **`TeXLib-Installer-v<version>.zip`** from the "Assets" section.
4. *(Optional but recommended)* Verify the download. Open PowerShell, navigate to your Downloads folder, and run:
   ```powershell
   Get-FileHash TeXLib-Installer-v<version>.zip -Algorithm SHA256
   ```
   The output should match the line in the release's `SHA256SUMS` file. If it doesn't, do **not** run the installer — re-download or open an issue.

## Step 2 — Unzip and run

1. Right-click the ZIP file → **Extract All...** → pick a destination (Desktop is fine).
2. Open the extracted folder. You should see:
   ```
   install.bat
   install.ps1
   uninstall.bat
   uninstall.ps1
   templates/
   texlib/
   README.md
   INSTALL.md
   ...
   ```
3. **Double-click `install.bat`.**

### The SmartScreen warning

Windows will probably show "Windows protected your PC" because the script is not code-signed. This is expected for personal-team distributions.

> **Click "More info" → "Run anyway".**

If you can't see the "Run anyway" button, your IT department has locked it down. Talk to them, or open the script in a text editor first to confirm it's the official copy from the verified release.

## Step 3 — Watch the install run

A console window opens and the installer walks through these phases:

1. **Pre-flight checks** — Windows version, free disk space, internet, etc. If anything fails, the installer aborts before touching your system.
2. **Sublime Text** — downloads + extracts (~10 seconds).
3. **SumatraPDF** — downloads + extracts (~10 seconds).
4. **TeX Live** — downloads installer + runs full install. **This takes 30-60 minutes.** It looks frozen sometimes; that's normal. Go grab a coffee.
5. **TeXLib library** — copies into your `Documents\TeXLib` (or OneDrive equivalent).
6. **PATH update** — adds TeX Live's `bin` directory so commands work from any terminal.
7. **Sublime sync setup** — junctions Sublime's user packages folder to the TeXLib sync folder so settings travel between your machines.
8. **Program configurations** — writes LaTeXTools, Preferences, and SumatraPDF settings with the right paths filled in.
9. **File associations** — sets `.tex`, `.cls`, `.sty`, `.bib` to open in Sublime; `.pdf` to open in SumatraPDF.
10. **Shortcuts** — puts Sublime and Sumatra icons on your Desktop + Start Menu.
11. **Verification** — compiles a tiny LaTeX file to confirm the install actually works.

If everything goes well, you'll see:

```
================================================
   TeXLib v<version> installation complete!
================================================
```

## Step 4 — First launch

A few things to know:

- **Open a NEW terminal** before running `pdflatex` or `lualatex` from the command line. The PATH update doesn't apply to terminals that were already open.
- **Sublime Text** may show a "Package Control" loading message the very first time you open it. Close Sublime and re-open it once — the message goes away.
- **File defaults** — if double-clicking a `.tex` doesn't open it in Sublime (or `.pdf` doesn't open in SumatraPDF), Windows sometimes ignores the registry settings on first install. Fix:
  - Right-click the file → **Open with → Choose another app**.
  - Pick Sublime / SumatraPDF.
  - Check **Always use this app**.

## Step 5 — Build your first document

1. Open Sublime Text.
2. Open `Documents\TeXLib\examples\Math181-Fall2026\lecture-01-limits.tex` (or any `.tex` from one of the module templates).
3. Press **Ctrl+B** to build with the default mode.

You should see a PDF open in SumatraPDF a few seconds later.

For variant builds (answer key, student copy, etc.), press **Ctrl+Shift+B** and pick from the menu, or open the command palette (**Ctrl+Shift+P**) and type "TeXLib".

## Step 6 — Build without opening the editor (optional)

You can also build a `.tex` straight from File Explorer, with no editor open.

**Right-click menu (always installed).** Right-click any `.tex` file and choose **Build with TeXLib**. A submenu offers every mode — Build, Answer Key, Solutions, Student Copy, Rubric, Draft, All Versions. The PDF opens in SumatraPDF when it finishes; if the build fails you get a notification and the `.log` opens so you can see why. This uses the exact same engine/mode/rerun logic as the in-editor build.

**Ctrl+B hotkey (opt-in).** If you install with:

```
install.bat -EnableBuildHotkey
```

a tiny background helper starts at login and gives File Explorer a **Ctrl+B** shortcut: click a `.tex` in Explorer, press Ctrl+B, and it builds (default mode) — no right-click needed. The hotkey only fires while a File Explorer window is focused, so Ctrl+B keeps meaning "bold" in Word, your browser, and everywhere else. It's opt-in because it runs a small program at startup; the right-click menu needs nothing resident.

> The Explorer builder mirrors the editor's build recipe but is a separate script (`%LOCALAPPDATA%\TeXLib\Scripts\texlib-build.ps1`). A `.tex` with a `% !TeX root = master.tex` line builds the master, just like in Sublime.

## Updating

Re-running the installer with a newer release ZIP **does not** wipe your settings — they live in `Documents\TeXLib\Sublime` and are preserved across re-installs via a junction.

The installer prints an "Update available: v0.X is the latest release (you are on v0.Y)" notice at the top of every run if a newer release is published, so you'll know when it's time to download a fresh ZIP.

To get the latest TeXLib library **only** (no need to touch Sublime/Sumatra/TeX Live), use:

```
install.bat -OnlyTeXLib
```

This skips the heavy components entirely and just refreshes the bundled library — takes seconds instead of an hour. Combine with `-Silent` for lab-machine deployment.

## About the user-root junction

If your OneDrive folder name contains a space or a comma — UNR's looks like `OneDrive - University of Nevada, Reno`, which has both — you'll see a new folder in your home directory after install:

```
%USERPROFILE%\TeXLib
```

This is a **directory junction** (a Windows reparse point), not a real folder. It points at your actual `OneDrive\Documents\TeXLib`. The installer creates it because `kpathsea`, TeX Live's file resolver, splits `TEXINPUTS` on commas and chokes on spaces — so it cannot find packages stored at `OneDrive - University of Nevada, Reno\Documents\TeXLib`. The junction gives TeX a comma/space-free path to chase, and everything downstream (LaTeXTools, the build template, the `Doctor` output, the `VERSION` stamp) is wired through it.

A few details worth knowing:

- **Editing files through the junction is the same as editing them in OneDrive.** They're the same bytes on disk; OneDrive will still sync them.
- **The junction is created only when needed.** No OneDrive, or an OneDrive path with no problematic characters in it → no junction.
- **Re-running the installer is idempotent.** If the junction is already there, the installer reuses it.
- **The uninstaller removes the junction**, but only after verifying it's a reparse point. If you happen to have a real `TeXLib` folder in your home directory from before this installer, it's left alone.
- **To hide it from File Explorer**, pass `-HideJunction` when installing. The default is visible (easier to discover and diagnose).
- **To remove it manually**, open PowerShell and run `(Get-Item $env:USERPROFILE\TeXLib).Delete()` — this removes the junction entry without touching the OneDrive target. Do **not** use `Remove-Item -Recurse` from File Explorer or older PowerShell on a junction; some Windows versions follow the link.

## Other flags worth knowing

| Flag | What it does |
|---|---|
| `install.bat -Doctor` | Diagnose an existing install (see Troubleshooting). |
| `install.bat -Version` | Print installer version + bundled TeXLib version. |
| `install.bat -DryRun` | Run pre-flight checks and print what would happen, without installing anything. Safe to run on a fresh machine to confirm prerequisites. |
| `install.bat -OnlyTeXLib` | Refresh just the TeXLib library. |
| `install.bat -InstallPath C:\Tools\TeXLib` | Install to a non-default location (e.g. if `%LOCALAPPDATA%` is on a small SSD). |
| `install.bat -Silent` | No prompts; safe defaults; intended for unattended deployment. |
| `install.bat -HideJunction` | Hide the `%USERPROFILE%\TeXLib` junction (see [About the user-root junction](#about-the-user-root-junction)). Off by default. |
| `install.bat -EnableBuildHotkey` | Install the resident **Ctrl+B** Explorer build hotkey (see [Step 6](#step-6--build-without-opening-the-editor-optional)). Off by default; the right-click menu is installed either way. |

Flags can be combined: `install.bat -OnlyTeXLib -Silent` is the typical lab-machine refresh.

## Uninstalling

Double-click `uninstall.bat` from the same folder you ran the installer from. It will:

- Remove `%LOCALAPPDATA%\TeXLib` (Sublime, Sumatra, TeX Live, logs, scripts)
- Clean PATH and registry entries
- Remove Desktop and Start Menu shortcuts
- Remove the `%USERPROFILE%\TeXLib` junction, if one was created (only if it's actually a junction — a real folder with the same name is preserved)

It **does not** delete your `Documents\TeXLib` folder. If you want a fully clean removal, delete that too.

## Troubleshooting

### First thing to try: `install.bat -Doctor`

Open the folder you extracted the installer to and run:

```
install.bat -Doctor
```

This runs a diagnostic against your existing install and prints a pass/warn/fail report for each component: install location, Sublime Text, SumatraPDF, TeX Live, the TeXLib library, the Sublime junction, the custom builder, LaTeXTools settings, file associations. The output is structured for copy-paste into a bug report.

Most "Sublime can't find the builder" / "PDF isn't opening" / "pdflatex not on PATH" issues are diagnosed (and often repaired by re-running the installer) in under 30 seconds.

You can also check the installed version at any time:

```
install.bat -Version
```

### Pre-flight check failed

Read the message — it tells you what's missing. Common ones:

- **"Need >= 6 GB free"** — clear space on your `%LOCALAPPDATA%` drive (usually `C:`).
- **"Cannot reach mirror.ctan.org"** — check your internet, VPN, or institutional firewall.
- **"Another LaTeX install detected"** — usually fine; this is just a warning. The installer will still proceed.

### Hash mismatch on download

The installer aborts on hash mismatch as a security precaution. Most often this means the upstream file has been re-released with a new hash (Sublime did this when bumping point releases). Open an issue with the line `expected: ...` and `actual: ...` from the log and we'll publish a refreshed installer.

### Install hung during TeX Live

TeX Live's install is genuinely slow — 30 to 60 minutes is normal. There's typically no progress indicator for long stretches. If it's been >90 minutes with zero console activity, kill the console window and re-run the installer with TeX Live's "Reinstall" option.

### Sublime can't find the builder

If `Ctrl+B` says "Cannot find builder texlib", verify:

1. `texlib_builder.py` is in `<Sublime Data>\Packages\User\` (the install copies it here).
2. `LaTeXTools.sublime-settings` in the same folder has `"builder": "texlib"`.
3. Restart Sublime — the builder is loaded at startup.

### Compile works on command line but not in Sublime

Usually a `TEXINPUTS` problem. The most common cause is **commas (or spaces) in paths**. kpathsea (TeX Live's file resolver) splits `TEXINPUTS` on commas and chokes on spaces. OneDrive at universities often has both ("OneDrive - University of Nevada, Reno"). As of v0.4.0 the installer detects this and creates a junction at `%USERPROFILE%\TeXLib` automatically — see [About the user-root junction](#about-the-user-root-junction). If `install.bat -Doctor` reports the junction as `[FAIL]` (or doesn't mention it at all on an affected machine), re-run the installer to create it. Open an issue if the junction is in place and you're still hitting this.

### Double-clicking a .tex or .pdf opens the wrong app

This is a known **Windows** behavior, not a TeXLib bug. Modern Windows 10/11
protects the default-app setting for each file type, so an installer can't
silently flip it — the first time you open a `.tex`/`.pdf` you may have to set
it once by hand:

- Right-click the file → **Open with → Choose another app**
- Pick **Sublime Text** (for `.tex`/`.cls`/`.sty`/`.bib`) or **SumatraPDF**
  (for `.pdf`), and check **Always use this app**.

It's purely cosmetic: the **right-click "Build with TeXLib"** menu, the optional
**Ctrl+B** Explorer hotkey, and building from inside Sublime all work regardless
of which app owns the double-click. You only need to do this once per file type.

### Getting help

When opening an issue, the GitHub issue form asks for the **Doctor output** and the **install log**. The faster you can get those into the report, the faster I can help.

- **Doctor output:** `install.bat -Doctor` and paste the whole console output.
- **Install log:** `%LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log` (most recent). The log captures everything the installer did, including which files were downloaded and what error stopped it.

Issue tracker: https://github.com/landonfox00/TeXLib-Installer/issues
