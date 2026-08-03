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

Everything — Sublime Text, SumatraPDF, TeX Live, and the TeXLib library itself — installs under a single folder, `%LOCALAPPDATA%\TeXLib`. Nothing goes into your `Documents`.

> **Upgrading from v0.6.2 or earlier?** Your library used to live in `Documents\TeXLib` (or the OneDrive equivalent). The installer moves it for you: your Sublime settings come across automatically, and the old folder is left exactly as it was for you to delete once you're happy. See [Upgrading from an older version](#upgrading-from-an-older-version).

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
   uninstall.bat
   templates/
   texlib/
   tools/
   README.md
   INSTALL.md
   ...
   ```
   There are exactly two things to click here, and `install.bat` is one of them. (The actual scripts live in `tools/`; you never need to open that folder.)
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
5. **TeXLib library** — copies into `%LOCALAPPDATA%\TeXLib\Library`, alongside the other components. If you're upgrading, your old library is found first and your Sublime settings are carried across.
6. **PATH update** — adds TeX Live's `bin` directory so commands work from any terminal.
7. **Sublime sync setup** — junctions Sublime's user packages folder to the library's `Sublime\` folder, so your settings survive re-installs.
8. **Program configurations** — writes LaTeXTools, Preferences, and SumatraPDF settings with the right paths filled in.
9. **File associations** — clears any stale "Open with" entries left by earlier installs, then sets `.tex`, `.cls`, `.sty`, `.bib` to open in Sublime and `.pdf` in SumatraPDF.
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
  - Pick **Sublime Text (TeXLib)** / **SumatraPDF (TeXLib)** — the `(TeXLib)` suffix tells them apart from any copy you installed yourself.
  - Check **Always use this app**.

## Step 5 — Build your first document

1. Open Sublime Text.
2. Open `%LOCALAPPDATA%\TeXLib\Library\examples\Math181-Fall2026\lecture-01-limits.tex` (or any `.tex` from one of the module templates).
3. Press **Ctrl+B** to build with the default mode.

You should see a PDF open in SumatraPDF a few seconds later.

For variant builds (answer key, student copy, etc.), press **Ctrl+Shift+B** and pick from the menu, or open the command palette (**Ctrl+Shift+P**) and type "TeXLib".

## Upgrading from an older version

If your last install was v0.6.2 or earlier, your TeXLib library is in `Documents\TeXLib` (or the OneDrive equivalent). v0.6.3 installs it to `%LOCALAPPDATA%\TeXLib\Library` instead, next to the other components. Just run `install.bat` from the new release — it handles the move:

- It finds your old library and says so in the pre-flight output.
- Your Sublime settings (`Sublime\`) are copied to the new location, so your keymaps, snippets, and word lists follow you.
- **Your old folder is not modified or deleted.** Once you've confirmed the new install works, delete `Documents\TeXLib` yourself.
- If you had a `%USERPROFILE%\TeXLib` junction, it's retired automatically — but only if this installer created it. A junction you made yourself is left alone.

Why the move? The library is a snapshot the installer overwrites on every re-install, so in `Documents` it was indistinguishable from your own files (and, if you kept a git checkout of TeXLib there, it landed on top of it). Under `%LOCALAPPDATA%` it's clearly install-managed, uninstall is a single folder removal, and TeX can resolve the path without the comma/space workaround.

## Updating

Re-running the installer with a newer release ZIP **does not** wipe your settings — they live in `%LOCALAPPDATA%\TeXLib\Library\Sublime` and are preserved across re-installs via a junction.

The installer prints an "Update available: v0.X is the latest release (you are on v0.Y)" notice at the top of every run if a newer release is published, so you'll know when it's time to download a fresh ZIP.

To get the latest TeXLib library **only** (no need to touch Sublime/Sumatra/TeX Live), use:

```
install.bat -OnlyTeXLib
```

This skips the heavy components entirely and just refreshes the bundled library — takes seconds instead of an hour. Combine with `-Silent` for lab-machine deployment.

## About the user-root junction

Since v0.6.3 you will almost certainly never see this. It appears only when the library's path contains a space or a comma, and the default path (`%LOCALAPPDATA%\TeXLib\Library`) has neither — so this now applies only if you pass `-InstallPath` pointing somewhere with one, or if your Windows account name has one. Before v0.6.3 the library lived in OneDrive, whose UNR folder name (`OneDrive - University of Nevada, Reno`) has both, and the junction was the normal case.

When it is needed, you'll see a new entry in your home directory after install:

```
%USERPROFILE%\TeXLib
```

This is a **directory junction** (a Windows reparse point), not a real folder. It points at the actual library folder. The installer creates it because `kpathsea`, TeX Live's file resolver, splits `TEXINPUTS` on commas and chokes on spaces — so it cannot find packages stored under a path containing either. The junction gives TeX a clean path to chase, and everything downstream (LaTeXTools, the build template, the `Doctor` output, the `VERSION` stamp) is wired through it.

A few details worth knowing:

- **Editing files through the junction is the same as editing the real ones.** They're the same bytes on disk.
- **The junction is created only when needed** — a library path with no problematic characters in it → no junction. If `%USERPROFILE%` itself contains a space or comma, a junction there would not help either, and the installer warns instead of creating a useless one.
- **Re-running the installer is idempotent.** If the junction is already there, the installer reuses it.
- **The uninstaller removes the junction**, but only after verifying it's a reparse point. If you happen to have a real `TeXLib` folder in your home directory from before this installer, it's left alone.
- **To hide it from File Explorer**, pass `-HideJunction` when installing. The default is visible (easier to discover and diagnose).
- **To remove it manually**, open PowerShell and run `(Get-Item $env:USERPROFILE\TeXLib).Delete()` — this removes the junction entry without touching what it points at. Do **not** use `Remove-Item -Recurse` from File Explorer or older PowerShell on a junction; some Windows versions follow the link.

## Other flags worth knowing

| Flag | What it does |
|---|---|
| `install.bat -Doctor` | Diagnose an existing install (see Troubleshooting). |
| `install.bat -Version` | Print installer version + bundled TeXLib version. |
| `install.bat -DryRun` | Run pre-flight checks and print what would happen, without installing anything. Safe to run on a fresh machine to confirm prerequisites. |
| `install.bat -OnlyTeXLib` | Refresh just the TeXLib library. |
| `install.bat -InstallPath C:\Tools\TeXLib` | Install to a non-default location (e.g. if `%LOCALAPPDATA%` is on a small SSD). The library follows it, to `C:\Tools\TeXLib\Library`. |
| `install.bat -Silent` | No prompts; safe defaults; intended for unattended deployment. |
| `install.bat -HideJunction` | Hide the `%USERPROFILE%\TeXLib` junction (see [About the user-root junction](#about-the-user-root-junction)). Off by default. |

Flags can be combined: `install.bat -OnlyTeXLib -Silent` is the typical lab-machine refresh.

## Uninstalling

Double-click `uninstall.bat` from the same folder you ran the installer from. After confirming, it asks about each component in turn, so you can remove some and keep others:

```
Remove Sublime Text (...)?        (Y/n)
Remove SumatraPDF (...)?          (Y/n)
Remove TeX Live (...)?            (Y/n)
Remove the TeXLib library (...)?  (Y/n)
```

Nothing is exempt from the question, and each prompt names the folder that actually gets deleted. Only the *default* differs: the library defaults to going when it's inside the install root, and to staying when it's a pre-0.6.3 `Documents\TeXLib` that may have your own materials next to it.

Keeping TeX Live is worth considering — it's ~6 GB and takes 30-60 minutes to reinstall, and a later `install.bat` run detects it and offers to skip it.

Whatever you choose, the uninstaller also:

- Cleans the PATH entry, the file associations, and the stale "Open with" entries
- Removes the Desktop and Start Menu shortcuts
- Removes the `%USERPROFILE%\TeXLib` junction, if this installer created one (a real folder with the same name, or a junction you made yourself, is preserved)

**A pre-0.6.3 `Documents\TeXLib` defaults to staying**, since you may have parked course materials next to it — press Enter to keep it, or answer `y` (or pass `-RemoveLibrary`) to delete it. If that library is reached through a `%USERPROFILE%\TeXLib` junction, the prompt names the real OneDrive/Documents folder, because that's the one whose contents go.

For unattended use: `uninstall.bat -Silent` removes the programs with no prompts, and `uninstall.bat -All -Silent` removes everything. Add `-InstallPath` if you installed to a non-default location, and `-Force` to close a running Sublime / SumatraPDF without being asked (they hold file locks that would otherwise stop the removal).

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

1. `texlib_builder.py` is in `%LOCALAPPDATA%\TeXLib\Sublime Text\Data\Packages\User\` (a junction to `%LOCALAPPDATA%\TeXLib\Library\Sublime`, where the install puts it).
2. `LaTeXTools.sublime-settings` in the same folder has `"builder": "texlib"`.
3. Restart Sublime — the builder is loaded at startup.

### Compile works on command line but not in Sublime

Usually a `TEXINPUTS` problem, caused by **commas or spaces in paths**. kpathsea (TeX Live's file resolver) splits `TEXINPUTS` on commas and chokes on spaces. As of v0.6.3 the library installs to `%LOCALAPPDATA%\TeXLib\Library`, which normally has neither, so this should no longer come up; if you used `-InstallPath` to put it somewhere with a space or comma, the installer creates a junction at `%USERPROFILE%\TeXLib` — see [About the user-root junction](#about-the-user-root-junction). If `install.bat -Doctor` reports the junction as `[FAIL]` (or doesn't mention it at all on an affected machine), re-run the installer to create it. Open an issue if the junction is in place and you're still hitting this.

### Double-clicking a .tex or .pdf opens the wrong app

Modern Windows 10/11 protects the default-app setting for each file type, so an
installer can't silently flip it — the first time you open a `.tex`/`.pdf` you
may have to set it once by hand:

- Right-click the file → **Open with → Choose another app**
- Pick **Sublime Text (TeXLib)** (for `.tex`/`.cls`/`.sty`/`.bib`) or
  **SumatraPDF (TeXLib)** (for `.pdf`), and check **Always use this app**.

It's purely cosmetic: building from inside Sublime works regardless of which app
owns the double-click. You only need to do this once per file type.

### The "Open with" menu is full of duplicate Sublime / SumatraPDF entries

Each install and uninstall before v0.6.3 left its registry entries behind, so the
list slowly filled with copies pointing at executables that no longer exist.
Re-running `install.bat` clears them: it purges the dead entries (and any
malformed ones, which show as blank rows) before registering fresh ones, and
tells Explorer to reload so you see the change immediately. Entries for a Sublime
or SumatraPDF you installed yourself are recognised as live and left alone.

`install.bat -Doctor` reports any leftovers it finds without changing anything.

### Getting help

When opening an issue, the GitHub issue form asks for the **Doctor output** and the **install log**. The faster you can get those into the report, the faster I can help.

- **Doctor output:** `install.bat -Doctor` and paste the whole console output.
- **Install log:** `%LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log` (most recent). The log captures everything the installer did, including which files were downloaded and what error stopped it.

Issue tracker: https://github.com/landonfox00/TeXLib-Installer/issues
