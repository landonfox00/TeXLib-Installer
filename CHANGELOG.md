# Changelog

All notable changes to TeXLib-Installer are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions correspond to git tags.

## [Unreleased]

### Added

- **A failed install leaves a breadcrumb instead of a mystery.** Nothing
  distinguished a run that died at section 16 from a machine that was never
  installed: the `VERSION` stamp is written at the very end, so a partial
  install was detectable only as a Doctor shrug ("VERSION file missing —
  partial install?"). The installer now writes `INSTALL-IN-PROGRESS` (start
  time, installer version, mode) at its first mutation of the machine and
  deletes it as the last act of a successful run. A surviving breadcrumb is
  positive proof of a died-partway run: the next install reports when and in
  what mode, then carries on — every section is idempotent, so re-running IS
  the recovery, and now the installer says so instead of leaving the user to
  wonder. Doctor reports it too, outranking the VERSION heuristic.

- **Doctor reads the library's own version.** TeXLib v0.7.3 ships
  `texlib-manifest.json` — the release tag's machine-readable mirror. When
  the deployed library carries one, Doctor reports "manifest vX.Y.Z" instead
  of inferring the library from the shape of three files; older deployments
  still pass on the probe alone.

### Changed

- **`.txt` belongs to the system again.** The installer had claimed `.txt`
  for Sublime alongside the TeX extensions since the OneTeX era, which meant
  every plain-text file on the machine — download receipts, exported notes,
  README.txt — opened in a programmer's editor. That surprises exactly the
  non-technical audience this installer is for, and SMOKE-TEST.md had carried
  "confirm that's intended" as an open question since it was written. Decided:
  it was not. Fresh installs no longer register `.txt`; upgrades release the
  old claim, but ONLY when the association still points at one of our ProgIDs
  (a `.txt` default the user set to anything else, including deliberately to
  Sublime via "always use this app", is never touched). `.txt` stays in the
  stale-entry purge list so old dead entries are still cleaned.

- **The plugin-host protection at `Sublime\` top level is an allowlist now.**
  Sublime loads every top-level `.py` in `Packages\User` as a plugin, and the
  library's `Sublime\` becomes `Packages\User` through the settings junction —
  the path by which the library's own test suite killed `plugin_host-3.8`
  twice (0.8.0, 0.9.5). The old guard was a denylist (`test_*.py`,
  `_testkit.py`): correct for every file that exists today, and one
  unfortunately-named future file away from a third crash. `Copy-LibraryTree`
  now inverts the rule at that one level: `Sublime\*.py` copies **only**
  `texlib_builder.py`, the sole Packages\User deployable. The plugin package
  under `Sublime\texlib\` reaches Sublime as `Packages\TeXLib` and is
  unaffected, and the any-depth denylist still applies everywhere else.

- **Pinned library moves to TeXLib v0.7.3** (from v0.7.2) — the v1-readiness
  library release. Since v0.7.2: the library's CI validates on TeX Live 2026
  with the container *and* every outcome-deciding tool pinned (imagemagick,
  poppler-utils, veraPDF 1.30.2 hash-verified, pypdf); an accessible build no
  longer stacks a second `\DocumentMetadata` onto a document that declares
  its own (the TL2026 kernel makes the duplicate fatal — the thesis
  template's layout); the library ships `texlib-manifest.json`, its first
  machine-readable version contract, with every `\ProvidesClass`/`Package`
  line normalized to the release version and a CI check holding them
  together; the duplicate `Sublime\texlib_pdfpost.py` is gone; and the README
  family documents the repo that exists (bank/thesis classes, real engine
  guidance, post-refactor paths). Hash-verified against the tag archive as
  always.

### Fixed

- **The `Packages\User` move cannot outrun its own safety net anymore.** On a
  first install with a pre-existing `Packages\User`, the backup was advisory:
  a failed `Compress-Archive` warned and the move → delete → junction
  sequence proceeded anyway, and a junction failure after the move left the
  user's settings stranded in the sync folder with `Packages\User` gone. The
  backup now GATES the move (a failed backup aborts with "close Sublime and
  re-run" — an open settings file is the usual cause), and a failed
  delete/junction step restores the moved contents to `Packages\User` before
  failing, so the editor keeps working even when the install did not.

- **Self-update refuses to run what it cannot verify.** `-Update` executes the
  downloaded installer — including under `-Silent`, where nobody reads a
  warning — yet three of its four verification failure modes only warned and
  carried on: a release shipping no `SHA256SUMS`, a failed `SHA256SUMS` fetch,
  and a sums file with no line for the downloaded asset all fell through to
  `& powershell.exe … -File $NewInstaller`. Only an outright hash mismatch
  refused. All four paths now stop with exit 21 and the same "refusing to run
  unverified bytes" message the mismatch branch always had, matching
  CONTRIBUTING's fail-closed rule for downloads; a new CI step parses
  `Invoke-SelfUpdate` out of the script and fails if any verification failure
  ever appears as a `[WARN]` again.

- **The TeX Live year is derived, not declared.** `$TexLiveYear` was hardcoded
  `"2025"` while the download URL is rolling tlnet — which installs whatever
  year is *current* — so a fresh install today laid TeX Live 2026 into a
  directory named `2025`, and the first year-constant bump would have made
  `Test-Path` miss every existing install and silently re-download ~6 GB
  beside an orphaned tree. Now: an existing install is found by **shape**
  (`TexLive\<year>\bin\windows`, newest wins) wherever the year landed; a
  fresh install derives the real year from the downloaded installer itself
  (`release-texlive.txt`, falling back to the `install-tl-YYYYMMDD` folder
  name) and labels the tree truthfully; the constant survives only as the
  provisional label of last resort. `uninstall.ps1` loses its "keep in
  lockstep" twin entirely — it already preferred the VERSION stamp, and its
  no-stamp fallback now uses the same shape search. Removing TeX Live now
  removes the whole `TexLive` root, taking the `texmf-local` planted beside
  the year tree (orphaned until now) and any second year tree with it; the
  legacy OneTeX PATH cleanup matches by prefix instead of an exact
  year-labeled string. CI's package-integrity job now enforces the other
  hand-synced pair (`$UninstallerVersion` == `$InstallerVersion`) and fails
  if a `$TexLiveYear` constant ever reappears in `uninstall.ps1`.

## [0.11.5] — 2026-08-25

### Changed

- **Pinned library moves to TeXLib v0.7.2** (from v0.7.1) — the box-grid
  schedule appearance fix. The box-grid renderer, which every accessible
  schedule build is forced onto, had always been an approximation of the
  tabularray calendar: rows floated apart, cells shifted against each other
  whenever a month-start date was `\fbox`'d, the WEEK divider was a fat white
  channel, and rows overran the text width. v0.7.2 re-baselines every row
  component to a uniform frame profile so the tagged schedule renders with the
  normal build's geometry — a Fall-term schedule paginates identically again
  (3 pages back to 2 on the real Math 126 course). Hash-verified against the
  tag archive as always.

## [0.11.4] — 2026-08-24

### Changed

- **Pinned library moves to TeXLib v0.7.1** (from v0.7.0) — the first-week
  follow-up to the pre-semester release. Since v0.7.0: the published coded copy
  takes the Math & Stat Office submission name (`MATH 181.1001_Fall 2026_Fox.pdf`)
  instead of needing a hand rename before it is mailed; exam dates print a
  weekday and the month spelled out, so a schedule-parseable `final-date` reads
  like the free-form exam dates beside it; `schedule.cls` actually publishes
  `Tentative Schedule.pdf`, which it had been named for in three places without
  ever producing, so the LMS bundle had been shipping the syllabus alone; an
  accessible Notes build with gated solutions no longer dies at
  `\end{document}`; and accessible mode is reachable from the Sublime build
  picker rather than only from Tools > Build With. Hash-verified against the tag
  archive as always.

## [0.11.3] — 2026-08-20

### Changed

- **Pinned library moves to TeXLib v0.7.0** (from v0.6.1) — the pre-semester
  release, shipped so coworkers get this semester's fixes before classes start.
  Since v0.6.1: inverse search works on solution boxes (whole-box, both
  multiple-choice key layouts, mechanism documented in the library's
  SYNCTEX.md), TeX Live 2026 compatibility for every class, the UNR-conformant
  thesis class gated in CI, the example corpus consolidated under one manifest
  with 33 scenario packs, the browsable class gallery, and
  \printbankcatalog[topic=...] filtering. Hash-verified against the tag
  archive as always; the sample bank fragments are now named problem-bank.tex,
  with bank.tex still resolved as a sibling for existing courses.


## [0.11.2] — 2026-08-17

### Changed

- **Pinned library moves to TeXLib v0.6.1** (from v0.6.0). Three commits: the
  `.schedmeta` calendar sidecar, and — the reason to bump rather than wait — the
  plugin now derives its own `texinputs` instead of shipping the key commented
  out.

  That last one closes the original build failure at its source. Installed
  machines were never exposed to it, because this installer writes an explicit
  `texinputs` into `Packages/User`; the people it broke were anyone who
  installed the Sublime package on its own and got a plugin that could not
  resolve a single class. The installer's setting still wins, so nothing about
  an installed machine changes — the difference is that the library no longer
  depends on this installer to be usable.

  290 files deployed, 37 held back, 11 search paths, 9 classes resolving.

### Fixed

- **`SHA256SUMS` failed its own verification anywhere but Windows.**
  `Set-Content` ended the line CRLF, so `sha256sum -c` parsed the filename with
  the `\r` still attached and reported `FAILED open or read` for a file sitting
  right there whose hash was correct. Windows verifiers use `Get-FileHash` and
  never saw it; anyone checking from WSL, git-bash or Linux got a checksum file
  that looked like it had caught a corrupted download. Written with an explicit
  LF now, and `sha256sum -c` passes. Found while publishing this release.

- **`make-release.ps1`'s synopsis described a file it has never written.** It
  said the version is "written into VERSION inside the bundle"; no bundle has
  ever contained a `VERSION` file — it goes into `RELEASE` as
  `release_version=`. Stale since 0.11.0, when `RELEASE` was introduced.

## [0.11.1] — 2026-08-15

### Fixed

- **A real full install could deploy the library one directory too deep, and
  report success.** `Copy-LibraryTree` took its source root from
  `Resolve-Path` while enumerating with `Get-ChildItem`. Those two can return
  the same file in different FORMS — an 8.3 short name (`C:\Users\RUNNER~1\…`)
  against its long equivalent — and the `Substring` that derives each relative
  path then slices at the wrong offset, leaving a tail of the *source* path
  glued to it. Every file lands under `<library>\<garbage>\…`.

  Nothing errors. The copies succeed, the counter still reads 271, the install
  exits 0. What follows is silent: no module directories at the library root,
  so the generated `texinputs` collapses from 11 search paths to 3; no `.cls`
  where anything looks for one; `Sublime\` missing. That is the original build
  failure restored in full, by its own fix. CI's `full-install` caught it, and
  `reuse-existing-library` had been passing *while* broken, because section 16b
  copies the builder straight from the archive and masked the symptom.

  The root is now taken from `Get-Item`, the same `FileSystemInfo`
  normalization `Get-ChildItem` uses, so the two cannot disagree. Any item that
  is somehow not under that root is a hard error rather than a guessed
  destination — the silent version of this is indistinguishable from success.

### Changed

- **The pinned library moves to TeXLib v0.6.0** (was v0.5.0, 2026-07-30) — 29
  commits of library work, hash-verified, 281 files deployed with 35 held back.

- **`-TeXLibPath` aimed at a git checkout overwrote it, destroying uncommitted
  work.** 0.11.0 regression, and the installer suggested the command itself:
  pre-flight prints *"Pass `-TeXLibPath <checkout>` to install AGAINST it
  deliberately"*. Through 0.10.x that was safe — with no bundle to deploy the
  checkout was used in place. Once the library became a download there was
  always something to deploy, so the suggested command replaced tracked files
  with the pinned release. Silently: exit 0, no warning.

  A git work tree is now never written to. It is used exactly as it is, no
  library is deployed over it, and the run says so. `.git` is probed with
  `Test-Path` rather than as a directory, because a linked worktree or submodule
  has a `.git` *file* and holds uncommitted work just the same.

  Relocation is unaffected: `-TeXLibPath` at a plain directory still deploys, so
  a custom install location keeps getting library updates.

- **`-OnlyTeXLib` skipped the internet check while being the one mode that is
  nothing but a download.** The skip was correct while the library shipped
  inside the release zip, and became wrong in 0.11.0. Offline, pre-flight
  announced that connectivity was fine and the run then died at exit 7 part way
  through. Only `-Repair` skips the check now, and the host tested is the one
  that mode actually needs — `-OnlyTeXLib` pulls from GitHub and never touches
  CTAN, so failing it on a CTAN outage was a false negative waiting to happen.

- **One `Copy-Item -Recurse -Exclude` survived the 0.11.0 sweep**, on the
  pre-0.6.3 settings carry-over — the single path whose destination *becomes*
  `Packages\User` through the settings junction, copying from a library an
  installer up to 0.9.4 had seeded with the author's test suite. So the exact
  filter that does not filter, on the exact path where the files it fails to
  filter get loaded as plugins. Now uses `Copy-LibraryTree` like everything
  else. (0.11.0's note claiming that helper covered "every source" was true of
  the library migration and not of this one.)

### Removed

- **Dead library-source branches.** `$UseExistingTeXLib` and
  `$MigrateFromLegacy` could no longer be set once the library became a
  download, but their branches survived in the plan, in section 11b and in
  section 13, along with a comment block describing a mode that could not
  happen. `$HaveBundle` was computed and never read. Behaviour is unchanged —
  every one of these was unreachable — but code that describes modes it cannot
  enter is how the next reader gets misled.

## [0.11.0] — 2026-08-14

### Changed

- **The release root now holds two files you can click, and both are the
  graphical ones.** `install.bat` and `uninstall.bat` *are* the GUI installer
  and uninstaller; the console entry points moved to
  `tools\install-console.bat` and `tools\uninstall-console.bat`.

  0.10.0 and 0.10.1 added the two GUIs but left them named `install-gui.bat` /
  `uninstall-gui.bat` beside the originals, so the root carried four `.bat`
  files — and the two with the plainest, most obvious names were the *console*
  ones. The file a first-time user was likeliest to double-click was the one
  written for scripting. Naming should follow what people reach for, and
  nobody reaches for `-gui`.

  Nothing about the console surface changed but its path: same switches, same
  `boot_wrapper.ps1`, same exit codes, and it is still what CI drives and what
  `-Repair` / `-Doctor` / `-Verify` / `-Update` / `-Silent` are documented
  against. The console `.bat` files set their working directory to the release
  root rather than `tools\`, so `texlib.config.json`, pre-staged component
  ZIPs, and a relative `-InstallPath` all resolve exactly where they did
  before.

  CI now pins the layout: exactly two `.bat` files at the bundle root, both
  launching a `-gui.ps1`, no `.ps1` at the root, and every file the four entry
  points invoke present in the bundle.

- **The TeXLib library is no longer bundled; the installer downloads it.** It is
  now the sixth entry in the same `$Downloads` table as Sublime Text,
  SumatraPDF, TeX Live, LaTeXTools and `regex` -- a pinned GitHub tag archive,
  SHA256-verified, and pre-stageable for offline installs like any other
  component.

  Bundling tied two projects' release cadences together. A library fix meant
  cutting an *installer* release, and every installer release had to decide
  which snapshot of a separate repo to freeze -- in practice whatever `HEAD`
  happened to be on the maintainer's machine at build time, which is not a
  decision a build script should be making quietly.

  Consequences worth knowing:

  - The release ZIP drops from ~3.4 MB to ~150 KB and no longer carries a
    second project inside it.
  - **The "you downloaded the wrong ZIP" trap is gone.** Three separate
    pre-flight failures existed to explain that *Code -> Download ZIP* has no
    `texlib\` in it. There is nothing to be missing now, so a source checkout
    installs exactly like a release.
  - A `texlib\` directory next to the release root still wins if one is there,
    which covers re-running an older release folder, air-gapped machines, and
    testing an unreleased library without cutting a tag.
  - Offline installs that relied on the bundle now want a pre-staged
    `texlib.zip` at the release root. That is why this is 0.11.0, not 0.10.2.

  The pin is three constants that have to agree: the tag in the URL,
  `$TeXLibZipDir` (GitHub drops the leading `v` when naming the folder inside
  the archive), and `$TeXLibVersion`. CI asserts all three, because a bump that
  updates one and not the others fails *after* the user has waited for the
  download. `RELEASE` now records `texlib_pin=`, so a built installer states
  which library it will fetch.

### Fixed

- **Every download could die on "The term 'Get-FileHash' is not recognized".**
  It lives in `Microsoft.PowerShell.Utility`, normally autoloaded — but a
  Windows PowerShell 5.1 child launched through `cmd /c` from a PowerShell 7
  parent inherits a `PSModulePath` that can leave it unresolvable. The failure
  lands *after* the bytes are already on disk, under a message that says
  nothing about downloading, and it was latent: every path that fetched
  anything had run some other Utility cmdlet first, so the module was already
  loaded. The library download is the first one that does not. Hashing now goes
  through `System.Security.Cryptography`, which needs no module at all; output
  is byte-identical to `Get-FileHash` for both SHA256 and SHA512.

- **`Copy-Item -Recurse -Exclude` never filtered nested paths.** It applies the
  exclusion to the items enumerated at the top level, so a `test_*.py` inside
  `Sublime\` rode straight through -- and `Packages\User` is a junction to that
  very folder, where Sublime loads every top-level `.py` as a plugin. That is
  the mechanism behind both `plugin_host-3.8` deaths (0.8.0's Package Control
  state; 0.9.5's test suite, where nine modules replace
  `sys.modules['sublime_plugin']` at import and three end in a bare
  `sys.exit()`).

  It stayed masked while `make-release.ps1` curated the bundle and only the
  migration paths used the copy. With the library arriving as a raw tag archive
  carrying the whole repo -- `.github\` plus eighteen `test_*.py` /
  `_testkit.py` under `Sublime\` -- it stopped being survivable. Replaced with
  `Copy-LibraryTree`, which walks the tree and drops an entry when **any** path
  segment matches, on every source: downloaded archive, local `texlib\` tree, or
  a pre-0.6.3 migration. Measured against the real v0.5.0 archive: 271 files
  copied, 32 held back, `Sublime\` reduced to exactly the two deployable
  builders. Section 16b-1b still purges as a backstop.

### Fixed

- **Nothing built on a fresh install.** Every TeXLib document failed at
  `\documentclass` with ``File `didactic.cls' not found`` — every class, every
  document, on a machine the installer had just reported as good.

  `Ctrl+B` on a `.tex` file runs the **native** `texlib_build` command (the
  TeXLib package's own keymap has bound it since the 2026-07-10 cutover), not
  LaTeXTools. The native command reads its `TEXINPUTS` from `texinputs` in
  `TeXLib.sublime-settings`, and the package default ships that key commented
  out — *"leave unset to inherit the process environment"*. Sublime inherits no
  `TEXINPUTS`, and the library deliberately lives outside every TEXMF tree, so
  unset means unresolvable. The installer wrote a perfectly correct `TEXINPUTS`
  into `LaTeXTools.sublime-settings`, but only the legacy
  *Tools > Build With > TeXLib* path ever reads that file.

  So the one file that made the primary build path work was the one file the
  installer did not write — the author's own copy is even labelled *"Machine-local
  override for the native TeXLib plugin (NOT shipped)"*, which is exactly why
  this was invisible from the development machine.

  The installer now writes `Packages/User/TeXLib.sublime-settings` from a
  template, the same way it already wrote the LaTeXTools one. The search path is
  **generated**, not hardcoded: the library root plus each immediate
  subdirectory that actually holds a `.cls`/`.sty`/`.lua`, so adding a module
  directory to the library needs no installer release. It is explicit rather
  than recursive (`<root>//` re-walks the tree every pass and lets a stale
  `.aux` shadow a same-named build), and it ends in the load-bearing empty
  segment — kpathsea only *appends* its default path at one, and without it
  `texmf-dist` drops out and builds fatal at startup instead.

  A file you have taken over is left alone: the installer rewrites this one only
  while it still carries the marker line saying it authored it, and if your own
  copy sets no `texinputs` it says so and prints the line to paste.

- **The end-of-install check could not have caught the above.** It compiled a
  plain `article`, which passes on a machine where not one real document
  builds. It now also asks `kpsewhich`, under precisely the `TEXINPUTS` just
  written, to resolve every class in the library — one call, and it fails in the
  same place a user's first `Ctrl+B` would.

- **The TeX Live step no longer opens a console window.** It put one on screen
  for the whole install — minutes to the better part of an hour — sitting in
  front of the GUI that was already reporting the same progress. `Start-Process`
  now passes `-NoNewWindow`, which sets `CreateNoWindow`; `-WindowStyle Hidden`
  is not the fix and never was, because `-RedirectStandardOutput` forces
  `UseShellExecute=$false`, under which `WindowStyle` is silently ignored.
  Measured both ways rather than assumed. Nothing is lost: output was already
  going to the log, and under `-no-gui` `install-tl-windows.bat` runs `perl
  install-tl` in-place, so its whole child tree inherits the same hidden console
  instead of opening windows of its own.

## [0.10.1] — 2026-08-08

### Added

- **`uninstall-gui.bat` — a graphical uninstaller.** It shows what is actually
  installed at a location, with folder sizes, and gives you a tick box per
  component so you can drop the editor and keep the 6 GB TeX Live tree. That
  choice is not new — `uninstall.ps1` has confirmed each component separately
  at the console since 0.6.x — but nothing put a window on it, and the console
  is not what you hand a colleague.

  Front-end only, same as the installer: it maps boxes to the switches that
  choice already had (`-KeepSublime`, `-KeepSumatra`, `-KeepTeXLive`,
  `-RemoveLibrary`, `-RemoveJunction`, `-Force`) and runs
  `uninstall.ps1 -Silent`.

  The boxes say "remove X" while the switches say "keep X", and that inversion
  is where a bug would quietly delete something someone meant to keep — so CI
  asserts the wiring, and a case table covers all 16 tick combinations plus the
  ticked-but-not-installed case. A component that is absent is shown disabled
  and can never contribute a switch.

  **Nothing is pre-ticked.** The console's own defaults do remove the programs,
  and the form followed them at first, but a window that opens with a 6 GB tree
  already marked for deletion is a different proposition from one you opt into
  — and the two mistakes do not cost the same. An unticked box you meant to
  tick costs a second run; a ticked box you failed to notice costs a
  multi-hour re-download. CI fails the build if anything pre-ticks again.

  Two bugs found by running it for real rather than by reading it:
  - `foreach ($s in @($S.OutStream, $S.ErrStream))` — **PowerShell variable
    names are case-insensitive**, so `$s` *is* `$S`, and the loop rebound the
    state hashtable the whole file hangs off to a `FileStream`. Everything
    after it in that branch threw, the catch fired, and a **successful
    uninstall was reported as a failure**. `install-gui.ps1` had used `$st` and
    was unaffected; CI now rejects `$s` in both.
  - The phase table named four banners `uninstall.ps1` does not print. They are
    composed from a `-Label` parameter, so they carry an `Emit` now, and the
    progress bar actually advances.

  Verified end to end on a throwaway install: ticking everything except TeX
  Live produced exactly `-KeepTeXLive -RemoveLibrary`, removed Sublime Text,
  SumatraPDF and the library, left the TeX Live tree on disk, left Desktop
  shortcuts pointing elsewhere alone, and exited 0.
- **`-Reinstall <components>` — replace some components, keep the rest.**
  `-Silent` was all-or-nothing skip, so there was no way to say "replace
  Sublime, keep the 6 GB TeX Live tree" without a human at the keyboard. That
  also meant the **GUI was a downgrade from the console** on this exact point:
  it drives `-Silent`, so it could not offer the `[S]kip or [R]einstall` choice
  the interactive prompt has always had.

      install.bat -Silent -Reinstall Sublime
      install.bat -Silent -Reinstall Sublime,SumatraPDF
      install.bat -Silent -Reinstall All

  It is a comma-separated **string**, not a `[string[]]` with a `ValidateSet`,
  and that is deliberate: `powershell.exe -File install.ps1 -Reinstall
  Sublime,TeXLive` — exactly how the GUI invokes it — does no array parsing and
  hands the whole value over as one token, which a `[string[]]` parameter then
  rejects. Caught while testing the GUI path, which is the only path where it
  shows. Tokens are split on commas, semicolons or whitespace, matched
  case-insensitively, and an unknown one fails with the offending token named.
- **The GUI detects what is already installed** under the chosen location and
  offers a tick box per component, with folder sizes, defaulting to leaving
  everything alone. Sizing is capped at 1.2 s and silently gives up rather than
  freezing the window on a 100k-file TeX Live tree. Boxes for components that
  are not present are cleared as well as hidden, so a path change cannot leave
  a stale tick behind that silently re-downloads several GB.
- **`unit-helpers` covers the parsing and the skip/reinstall decisions**,
  including an assertion that `-Reinstall` is still a `[string]` — the
  `[string[]]` regression is invisible until someone actually runs the GUI.

### Fixed

- **A TeXLib git checkout was detected as a pre-0.6.3 library and copied into
  the install root.** `Test-TeXLibLibraryDir` asks only whether the core
  `.sty` files are present, and the library's own source repo obviously has
  them — while `Documents\TeXLib` is *both* the default checkout location and
  the default pre-0.6.3 install location, so on a maintainer's machine the two
  collide exactly. Migrating a checkout is wrong in both directions: the copy
  is a detached snapshot, so later commits never reach the install and edits to
  the install never reach the repo. A candidate carrying `.git` is now skipped
  with a note naming `-TeXLibPath` as the way to install against a checkout on
  purpose, and the "this is the GitHub source download" pre-flight failure
  grows a maintainer-specific variant — telling someone with a perfectly good
  library checkout on disk to go download a release zip was wrong advice.
- **The library-copy paths carried the dev-only test suite.** A legacy
  migration and the Sublime settings carry-over both copy a folder straight off
  the user's disk, and that folder's `Sublime\` becomes `Packages\User` through
  the settings junction — so they reintroduced exactly what 0.9.5 removed from
  the bundle, by a different door. 16b-1b purged it afterwards so no plugin
  host died, but not copying it beats cleaning up after it. One shared
  exclusion list (`.git`, `.github`, `__pycache__`, `test_*.py`, `_testkit.py`)
  now covers both, and the bundle deploy uses it too: `-OnlyTeXLib` run from an
  *older* release folder deploys that older, unfiltered bundle.

### Removed

- **`"update_check": false` — it never did anything.** The setting went into
  the Preferences template in 0.7.2 to stop Sublime's "Update Available"
  dialog on the pinned portable build. `update_check` is a **command**, not a
  preference: it is the Help -> Check for Updates menu item, defined in
  `Default.sublime-package`'s `Default.sublime-commands` and `Main.sublime-menu`.
  Sublime 4200's own default `Preferences.sublime-settings` documents 196
  settings keys and `update_check` is not among them, and unrecognised keys are
  silently ignored. Verified against the shipped 4200 build.

  It was inert for three releases while two CHANGELOG entries and a template
  comment asserted otherwise; all three now say so. The update prompt seen on a
  work machine on 2026-08-07 was correct behaviour, not a mystery -- nothing
  was ever disabling the check. **No supported mechanism for suppressing it has
  been found**, and rather than ship another guess the template now records
  what was ruled out. The pin bump remains the real answer: the prompt returns
  only when Sublime ships something newer than what we pin.
- **The `config-artifacts` assertion that rubber-stamped it.** It checked that
  the string `"update_check": false` appeared in the deployed preferences --
  that a string was in a file, not that it had any effect -- and was green
  throughout. It now asserts `build_system` still pins Ctrl+B to TeXLib's build
  (a real, checkable behaviour) and fails if `update_check` ever comes back.

## [0.10.0] — 2026-08-07

A graphical installer, for handing to someone who should not have to read a
console to install a text editor.

### Added

- **`install-gui.bat` — a WPF installer window.** Pick the install location and
  the TeX Live scheme, optionally set the library path and the junction
  attribute under Advanced, then watch a progress bar and a live log. On
  failure it names the step that failed rather than printing a bare exit code,
  and offers the log in one click.

  It is a **front-end, not a second installer**: it builds an argument list,
  runs `install.ps1 -Silent` as a child process, and tails that process's
  output. Nothing about what gets installed or written lives in the GUI, so
  `install.ps1` remains the single implementation and the only thing the
  install jobs in CI exercise. `install.bat` is unchanged and is still the
  scriptable surface — the GUI is an addition, not a replacement, because
  quietly changing what a double-click does is how you surprise the person who
  has been using the console one for a year.
- **The log pane word-wraps.** Installer output is full of long absolute paths
  -- 193 characters in a routine dry run -- and reading them meant scrolling
  sideways. Note for anyone changing this: the enclosing `ScrollViewer` has to
  be `HorizontalScrollBarVisibility="Disabled"`, not `Auto`. A ScrollViewer
  that *can* scroll horizontally measures its child with infinite width, so the
  TextBox is never constrained to the viewport and `TextWrapping="Wrap"` does
  nothing at all.
- **A dry-run tick box.** Maps to the existing `-DryRun`: runs the pre-flight
  checks and reports what a real install would do, without downloading or
  writing anything. Seconds, not an hour, and the natural first thing to do on
  an unfamiliar machine.
- **`gui` CI job.** The GUI reads `install.ps1`'s console banners to drive its
  progress bar, which is a coupling that rots silently — rename a banner and
  the install still works perfectly behind a bar that never moves. The job
  asserts every phase marker still tracks `install.ps1`, loads the XAML for
  real (a typo there is a crash on launch, not a warning), checks every
  `FindName` target resolves, and holds the file to the same ASCII rule as
  `install.ps1`.

### Fixed

- **Found while building the above: `Start-Process -PassThru` reports `$null`
  for `.ExitCode`**, even after `WaitForExit()`, unless something kept the
  process handle open. `$null` coerces to `0` through an `[int]` parameter, so
  the first draft of the GUI would have reported a **failed install as a
  successful one**. Touching `.Handle` while the child is alive fixes it;
  verified against exit codes 0, 5 and 7, and there is a fallback that reports
  an unknown code rather than assuming success.
- **The `[TeX Live] finished` phase marker could never have matched.** It was
  compared with `-like`, which reads `[TeX Live]` as a wildcard character
  class. Matching is now plain `.Contains`, which also keeps any future marker
  containing `[ ] * ?` safe by default; CI fails the build if `-like` comes
  back.

### Fixed — found by actually clicking the thing

Four more, none of which any static check would have caught. Worth recording
because each one came from a first hands-on run, not from review.

- **A blank console window sat on screen for the whole install.**
  `Start-Process -RedirectStandardOutput` forces `UseShellExecute = $false`,
  and `-WindowStyle Hidden` is **silently ignored** when `UseShellExecute` is
  `$false`. The child got a real console, blank because its output had been
  redirected away, and on a full install it would have sat there for 40 to 90
  minutes. `CreateNoWindow` is the only flag that actually suppresses it, and
  it is reachable only through `ProcessStartInfo`. Now measured: zero console
  windows appear, sampled every 100 ms across a launch.
- **Every character in the log pane was separated by a space** --
  `C : \ U s e r s`. PowerShell 5.1's `*>` redirection writes **UTF-16LE**;
  the tailer decodes UTF-8, so the `0x00` after each ASCII byte rendered as a
  gap. Confirmed at byte level: the file began `FF FE 43 00 3A 00 5C 00`. The
  child's raw pipe bytes are copied to the file instead, which are single-byte
  and read back correctly. The same mangling was also breaking lines in the
  middle, which is why `Mode:` and `DRY RUN` appeared on separate lines.
- **`ProcessStartInfo.ArgumentList` does not exist on .NET Framework.** It is
  .NET Core / .NET 5+, so on the Windows PowerShell 5.1 that `install.bat`
  launches, `$psi.ArgumentList.Add(...)` throws "You cannot call a method on a
  null-valued expression." Arguments are now quoted by hand for
  `CommandLineToArgvW`, verified by round-tripping through that API: paths with
  spaces, paths with trailing backslashes (a real hazard, since the user types
  the install location into a text box), and embedded quotes all survive.
- **`-Command` loses the child's exit code.** A script's `exit N` becomes the
  process exit code under `-File`; under `-Command` it does not survive the
  call, and a child that really exited 3 came back as 1. The launch uses
  `-File`. This is the third time in this release that getting an exit code
  wrong would have reported a failed install as a good one.

- **An error inside the progress timer killed the window outright.** An
  exception escaping a `DispatcherTimer` handler goes to WPF's
  unhandled-exception path, which tears the process down -- the window simply
  vanished mid-run with no message and nothing to diagnose, which is the exact
  failure `boot_wrapper.ps1` exists to prevent on the console side. The tick is
  now fully trapped, there is a dispatcher-level handler behind it, and the
  window writes a session log to `%TEMP%\TeXLib-gui-session-*.log` from the
  moment it starts, so a crash leaves evidence either way.

## [0.9.5] — 2026-08-07

`plugin_host-3.8 has exited unexpectedly` again, on a work machine, from a clean
v0.9.4 install. 0.8.0 found one landmine in the library's `Sublime\` folder and
removed it; this is the rest of the minefield. Also answers the update prompt
that showed up next to it, by moving the pin rather than defending it.

### Changed

- **Sublime Text pinned to build 4200** (was 4180). The pin has never meant
  "TeXLib needs an old Sublime" — it means the installer knows which bytes it
  ran, fails closed on a hash mismatch, and can tell you via `-Verify` when
  something drifted. Answering the in-app "Update Ready: 4180 → 4200" prompt
  gets none of that: Sublime patches itself in place from
  `sublime_text_windows_x64_4200.pak.xz`, rewriting a tree the MANIFEST covers
  with bytes nothing verified, so `-Verify` then reports drift across the whole
  `Sublime Text\` folder and the uninstaller no longer matches what is on disk.
  The answer is to move the pin, which is cheap. Checked before pinning:
  - build 4200 still ships `plugin_host-3.8.exe` and `python38.dll`, so
    LaTeXTools' `.python-version = 3.8` and the cp38 `regex` wheel are
    unaffected — the ABI that matters here did not move;
  - the archive really contains build 4200 (`sublime_text.exe` FileVersion
    4200) and its SHA256 is stable across repeated downloads, so this is a
    genuine bump and not the in-place repackage that bit 0.6.4.

  `"update_check": false` stays. It is not there to keep you on an old build,
  it is there so the build changes when the installer says so.

  **Correction (0.10.1):** that last sentence is wrong, and so is the v0.7.2
  entry it rests on. `update_check` is a *command*, not a preference, so the
  setting never did anything. See 0.10.1.

### Fixed

- **The author's test suite shipped into `Packages\User` and crashed the plugin
  host.** `Sublime\` is the author's working directory — the four deployables
  next to `_testkit.py` and seventeen `test_*.py`. `deploy.ps1` copies an
  explicit allowlist, so the author's own machine never sees the tests in
  `Packages\User`; `make-release.ps1` bundled the folder wholesale
  (`git archive` of HEAD), and the settings junction makes that folder
  `Packages\User` verbatim. Sublime loads every top-level `.py` in
  `Packages\User` as a plugin, so on a bundle install the test suite ran inside
  `plugin_host-3.8`. Two independent kills:
  - Nine of them call `_testkit.stub_sublime()` at *module scope*, which does
    `sys.modules["sublime"] = <stub>` and
    `sys.modules["sublime_plugin"] = <stub>` — replacing, in the live host, the
    module Sublime dispatches commands and event listeners through.
  - `test_texlib_build`, `test_texlib_runner` and `test_texlib_texam` end in a
    module-scope `sys.exit()`. `SystemExit` is a `BaseException`, so the plugin
    loader's `except Exception` never sees it and it takes the process with it.

  The bundle now honours `deploy.ps1`'s contract. It is an **allowlist**
  (`texlib_builder.py`, `texlib_pdfpost.py`), not a `test_*` denylist: anything
  new and top-level in `Sublime\` becomes a plugin on every coworker's machine,
  so the deployables are named and everything else stays home.
  `Sublime\texlib\` is untouched — it ships as a real package to
  `Packages\TeXLib`, and Sublime does not auto-load `.py` from a subfolder.
- **An install now disarms a library an older release already deployed.** The
  bundle fix does nothing for the machines that have the files on disk, so
  section 16b-1b removes `test_*.py` / `_testkit.py` from `Packages\User` on
  every run, alongside the 0.8.0 Package Control purge it is modelled on. The
  pattern is the signature; a user's own plugins are left alone.

### Added

- **`package-integrity` asserts no non-deployable `.py` at the top level of the
  bundle's `Sublime\`**, by the same allowlist. The 0.8.0 assertion named one
  file, so it only ever caught the one file; this catches the class.

## [0.9.4] — 2026-08-06

### Changed

- **Corrected a second invented number.** `scheme-medium` was documented as
  "~2.5 GB". A completed install measures **1.3 GB** — the 2.5 was made up, the
  same way the discarded time estimates were. Having just fixed one set of
  fabricated figures, shipping another would have been poor form. `medium` is
  now quoted as measured (1.3 GB, 25.5 minutes), and `full` and `basic` say
  "about", because neither has actually been measured here and the docs should
  distinguish the two.
- The free-space pre-flight deliberately stays **above** the installed size —
  `install-tl` needs room to download and unpack on the way, and refusing an
  install for want of headroom beats dying two thirds of the way through one.

## [0.9.3] — 2026-08-06

### Fixed

- **v0.9.2 failed every TeX Live install, including successful ones. Upgrade
  past it.** The output redirection added in 0.9.2 changed how PowerShell starts
  `install-tl`, and the object `Start-Process -PassThru` returns then reports
  `ExitCode` as `$null` — *always*, on success as much as failure, and calling
  `WaitForExit()` first does not change it (measured in isolation, not assumed).
  The existing check was `if ($TLProc.ExitCode -ne 0)`, and `$null -ne 0` is
  true, so a perfectly good 25-minute install was reported as
  "did not install cleanly" and the run aborted at exit 5.
  - The check is now the **outcome**: does `pdflatex.exe` exist? That is the
    thing the step exists to produce, it cannot be null, and it is true exactly
    when the install is usable. An exit code is reported only if some future
    PowerShell starts supplying one, and a non-zero code with `pdflatex.exe`
    present is a warning rather than grounds for discarding a working install.
  - Caught because the 0.9.2 diagnostics it shipped alongside worked: the
    captured log showed `install-tl`'s ordinary *success* epilogue, and the
    preserved scratch showed a complete tree. Without those two additions this
    would have looked exactly like the transient failure it was pretending to be.

### Notes

- **`-TexLiveScheme medium` works.** It completed in **25.5 minutes** (~2.5 GB).
  The earlier 37-minute failure was a genuine transient — a mirror that dropped
  mid-transfer, leaving 0.08 GB and no `pdflatex.exe` — and not a defect in the
  scheme handling. Time remains dominated by the mirror, which is why the
  installer quotes size rather than minutes.

## [0.9.2] — 2026-08-06

### Fixed

- **A failed TeX Live install destroyed its own evidence.** Two compounding
  problems, found when a real `-TexLiveScheme medium` run died 37 minutes in:
  - `install-tl`'s output was never captured. It is the longest and most
    failure-prone step in the whole installer — gigabytes pulled from whichever
    CTAN mirror a redirector picks — and every word it said was discarded, so a
    failure produced exactly one line: `install-tl exited with code 1`. Nothing
    to act on, nothing to paste into a bug report. Its stdout and stderr now go
    to `<InstallPath>\Logs\texlive-install-<timestamp>.log`, stderr is folded
    in so a report needs one file, and **the last 20 lines are printed straight
    to the console on failure** — the reason is nearly always there, and making
    someone go hunting through a log to find out why their 40-minute install
    died is a poor way to treat them.
  - `Stop-Installer` then deleted the download scratch on *every* exit path,
    including failures — taking `install-tl`'s working directory and its own
    logs with it, at precisely the moment they were needed. The scratch is now
    kept when the installer exits non-zero, and its location is printed.
    Success still cleans it up, because then it is worthless and can be
    multi-gigabyte.

## [0.9.1] — 2026-08-06

### Changed

- **Stopped advertising TeX Live install times the installer cannot predict.**
  `scheme-basic` was claimed at "2-5 min" and measured **~12 minutes** on a fast
  connection; `scheme-medium` was claimed at "5-15 min" and ran past that. The
  install is dominated by downloading from whichever CTAN mirror the redirector
  hands you, so the scheme barely determines the wall clock. Every message now
  quotes the **size** — which is stable and real — and says plainly that the
  time depends on the mirror. `scheme-full` keeps its "typically 30-60 minutes"
  (measured 52 min on real hardware, ~38 in CI), now qualified rather than
  stated as fact.
- **The docs say outright that `basic` is not viable for TeXLib.** It is missing
  30 of the 50 packages the library requires — a fact the Doctor already
  reports, but which belongs in front of anyone choosing a scheme rather than
  behind a diagnostic they run afterwards.

### Testing

- **New `upgrade-from-old-release` CI job.** It downloads the real published
  **v0.6.4** ZIP, installs from it, removes that install with the **current**
  uninstaller, then installs the current version over the top and runs
  `-Verify`. Every other job installs and uninstalls the same version, so none
  of them could ask the question that actually matters to a returning user:
  does today's uninstaller understand yesterday's on-disk layout? v0.6.4 is the
  right baseline — it predates the Sublime plugin deploy, the manifest, the
  Installed Apps entry, and the removal of Package Control.
  - Verified locally against both real released ZIPs before being encoded as a
    job: v0.6.4 installs, the v0.9.0 uninstaller unlinks the `Packages\User`
    junction and removes the root with no warnings, and a fresh v0.9.0 install
    then passes `-Verify` with no Package Control anywhere.

## [0.9.0] — 2026-08-03

First of three batches of the over-engineering list.

### Added

- **TeXLib appears in Settings > Apps > Installed apps.** Until now it was
  invisible to Windows' own uninstall list, so removing it meant remembering
  where you extracted a ZIP months ago. A per-user `Uninstall` key now carries
  the display name, version, install location, icon and size — with
  `QuietUninstallString` wired to the one-click Uninstall in Settings, and
  **Modify mapped to `-Repair`**, which is exactly what that button should do.
  The uninstaller removes the entry, and only its own: an entry recording a
  different install root is left alone.
- **`install.bat -Verify`** — checks an existing install against a manifest
  written when it was made, and reports the three kinds of difference
  separately, because they mean different things:
  *missing* (the installer put it there and it is gone — usually the
  interesting one), *changed* (edited settings live here, which is normal), and
  *added* (almost always the user's own work, so it is listed last and never
  called a problem). Exit 0 when nothing is missing or changed, 22 otherwise.
  TeX Live is excluded — 100k+ files that `tlmgr` legitimately rewrites — and
  reparse points are skipped rather than followed, so the library is not hashed
  twice under two names via the `Packages\User` junction.
- **`texlib.config.json`** beside `install.bat` presets any option, so a lab
  deployment is "hand someone the folder" rather than a command line to retype.
  **Anything passed on the command line always wins** — the file is applied only
  to options the caller did not name. An unknown key is reported rather than
  silently ignored, and malformed JSON warns instead of aborting the install.

### Testing

- `config-artifacts` now also asserts the Installed Apps entry (including that
  Modify maps to `-Repair` and Quiet-uninstall actually invokes the
  uninstaller), that a manifest is written, that `-Verify` passes clean and then
  catches one of each difference, and that config presets apply while an
  explicit argument still beats them.

## [0.8.1] — 2026-08-03

Findings from a full audit plus a real end-to-end install on physical hardware. Four of these are bugs no CI job could have caught, for reasons worth recording.

### Fixed

- **The Doctor reported every LaTeX package missing on a healthy install.**
  `kpsewhich` prints a path per file it finds and an **empty line** per file it
  does not — and `Split-Path "" -Leaf` throws, which the script-wide
  `$ErrorActionPreference = "Stop"` promoted to terminating, so the `catch`
  reported all 50 packages absent. A real `-TexLiveScheme basic` install showed
  it: 50 missing where the true answer was 30. A **full** TeX Live resolves
  everything, produces no blank lines, and never trips it — so `full-install`
  could not have found this. The check only misbehaved when it had something to
  report. Parsing now lives in `Get-MissingTexPackage`, a pure function with a
  six-case unit table including the blank-line marker.
- **A user's own `Desktop\Sublime.lnk` was silently overwritten, then deleted.**
  Two separate halves of the same mistake — treating a filename as ownership.
  The installer wrote its Desktop shortcut to the generic `Sublime.lnk`, and
  `CreateShortcut` cheerfully rewrites an existing file, so anyone with their
  own shortcut to a Sublime in Program Files lost where it pointed; the
  uninstaller then removed it by name. The Desktop shortcuts are now
  `Sublime Text (TeXLib).lnk` / `SumatraPDF (TeXLib).lnk`, matching the Start
  Menu group and unable to collide, and *both* scripts resolve a shortcut and
  act only if it points into the install root — the ownership rule the "Open
  with" purge already applied. The pre-0.8.1 names are cleaned up on install,
  again only where they are provably ours.
  - Caught by the new `config-artifacts` job on its first run, which is the
    entire argument for writing it.
- **Shortcuts orphaned by a Desktop-redirection change are now cleaned up.**
  OneDrive's folder backup moves the Desktop; turning it off moves it back and
  strands whatever was there. Observed on a real machine: `GetFolderPath` said
  `C:\Users\<me>\Desktop` while ours sat in the OneDrive one. The uninstaller
  sweeps both, which is only safe because of the ownership check above.
- **A skipped SumatraPDF reinstall left three settings pointing at nothing.**
  The exe is named by version, and the pinned name is only right when *this* run
  installed it. Answer "Skip" after a version bump — or run `-Repair` — and the
  LaTeXTools viewer path, the `.pdf` association and the Start Menu shortcut all
  named a file that was not there, silently, until someone double-clicked a PDF.
  Worse, the Doctor resolved the real exe and reported `[OK]`, so it disagreed
  with the rest of the install without saying so. The exe on disk now wins.
- **`-Repair` overwrote the recorded TeX Live scheme** with its own parameter
  default, so repairing a `basic` install stamped it `full` — after which the
  missing-package report stopped naming the scheme that explained it. A mode
  that installs no TeX Live now preserves what the installing run wrote.
- **`-OnlyTeXLib` on a machine without Sublime aborted the whole of section 16**
  (exit 10) trying to create the plugin junction, because `New-Item -ItemType
  Junction` does not create missing parents. It now notes and skips.
- **`-Doctor` printed `.tex ->  (not a TeXLib association)`** with a hole in it
  when the extension key existed with no default value.

### Added

- **`config-artifacts` CI job** covering what sections 16–18 actually put on the
  machine, none of which was asserted anywhere: the SumatraPDF exe resolution
  (seeded with a *newer* exe than the pinned one), `"update_check": false` in
  the deployed preferences, the Start Menu group, and — on the way back out —
  that a user's own identically-named shortcut survives the uninstall.
- **`full-install` now asserts** that `scheme-full` satisfies every package
  TeXLib requires, that `regex` kept its `.dist-info`, and that Package Control
  has not come back.
- **`Get-MissingTexPackage` case table** in `unit-helpers`.

## [0.8.0] — 2026-08-03

Diagnoses and fixes `plugin_host-3.8 has exited unexpectedly`, seen on a coworker's machine right after a clean install.

### Removed

- **Package Control is no longer installed.** It was the cause. The chain,
  established by inspecting the pinned artifacts rather than guessing:
  - The library ships `Sublime/Package Control.sublime-settings` — a snapshot of
    the *author's* setup, listing `LaTeXTools`, `Package Control`, `PowerShell`
    and `UnitTesting` — and that folder becomes `Packages\User` through the
    settings junction, so it is live on every machine.
  - LaTeXTools declares `.python-version = 3.8`, so it runs in the 3.8 host, and
    `latextools\utils\analysis.py:4` does a bare, unguarded `import regex` that
    8+ startup modules pull in. `regex` is a native extension — the only thing
    in that host that can kill the process rather than raise.
  - LaTeXTools' `dependencies.json` declares `mdpopups` **and** `regex`. On first
    launch Package Control read the shipped list, found those libraries
    unaccounted for, and installed its own — writing over
    `_regex.cp38-win_amd64.pyd` while the host had it loaded and mapped.
  - Our copy was invisible to it because the installer extracted the wheel and
    kept only `regex\`, discarding `regex-2024.11.6.dist-info\` — the record
    Package Control identifies installed libraries by.

  Running two package managers over one `Packages` tree was never redundancy, it
  was a race. This installer already does that job with pinned, hash-verified
  artifacts, so the second manager goes. Anyone who wants Package Control for
  packages of their own can install it themselves; nothing here interferes, and
  an existing copy is left strictly alone on re-install.
  - Ruled out along the way, so they don't get blamed later: the `regex` wheel is
    correctly built (cp38 / win_amd64, links `python38.dll` + `VCRUNTIME140.dll`),
    and `mdpopups` really is guarded (`try: import mdpopups`), so its absence was
    never the problem.

### Fixed

- **The `regex` install keeps the wheel's `.dist-info`.** Beyond defusing the
  above, it is simply the correct way to place a Python package — so a user who
  installs Package Control later finds a registered library instead of an
  unmarked folder to trample.
- **The author's `Package Control.sublime-settings` no longer ships**, and an
  install removes a stale one left by an earlier release — unless Package
  Control is actually present, in which case the file is its own live state and
  is left alone. `package-integrity` asserts the bundle never carries it again.
- **The first-launch note that said "Sublime may show a Package Control loading
  message; just restart once and it goes away"** is gone. It was documenting the
  symptom of this bug as normal behaviour.

## [0.7.2] — 2026-08-03

From reading a real install log on a returning work machine.

### Fixed

- **The installer warned about a pin it was thirty lines from making correct.**
  Re-installing over a previous uninstall arrives with `.pdf` still pinned to
  `TeXLib.SumatraPDF` and that ProgID's key already deleted, so the stale-entry
  purge called it dead and told the user to go reset it by hand — while section
  17 was about to re-register that very ProgID and make the pin right again.
  The purge now excludes the ProgIDs the same run is about to register. The
  remaining warnings (`OneTeX.*`, from before the rename) are the genuinely
  dead ones.
- **"No stale 'Open with' entries found" printed directly beneath four warnings
  about stale entries.** The counter only incremented on a *successful* clear,
  so a `UserChoice` that Windows refused to delete produced a warning and then
  got reported as nothing found. Un-clearable pins are now collected and
  reported once, in one place, and never alongside a claim that there were none
  — matching what the uninstaller already did.
- **Sublime nagged to update itself out of the installer's control.** The
  bundled Sublime is a pinned portable build, hash-verified on the way in, but
  nothing set `update_check` — so it popped "Update Available: 4180 → 4200", and
  taking that swaps the managed copy for an unmanaged one that no longer matches
  what the installer configured around it. `"update_check": false` is now in the
  Preferences template; updates arrive with a new installer release instead
  (`install.bat -Update`).
  - **This fix did not work and was removed in 0.10.1.** `update_check` is a
    command, not a preference. The setting was inert from the day it shipped,
    and the update prompt it claimed to stop kept appearing.

## [0.7.1] — 2026-08-03

### Fixed

- **`-Update` never updated.** It called `Test-IsNewerVersion -Latest $Latest`,
  but the parameter is `-Candidate`. `Test-IsNewerVersion` is a *simple*
  function — no `[CmdletBinding()]` — and PowerShell sweeps unrecognised
  arguments into `$args` rather than erroring, so `-Candidate` stayed `$null`,
  the null guard returned `$false`, and every run reported "Already on the
  latest release" no matter how far behind it was. It failed safe, which is
  precisely why nothing complained: the unit test for the comparison passed
  (it calls the function correctly), and CI was green.
  - Found by testing the whole loop end to end against the real v0.7.0 release
    with `$InstallerVersion` faked down — something only possible once there was
    a published release newer than the working copy.
  - New CI step walks the AST and checks **every** call to a locally-defined
    function against that function's real parameter names, so the whole class of
    silently-swallowed argument goes from invisible to a build failure. Verified
    by reintroducing the bug in a copy and watching it fail.

> **v0.7.0's `-Update` cannot fetch this release** — that is the bug. Update to
> 0.7.1 by downloading the ZIP once; `-Update` works from there on.

## [0.7.0] — 2026-08-03

Convenience release. One of these is a gap rather than a nicety: the installer was shipping a Sublime plugin it never installed.

### Fixed

- **The TeXLib Sublime package was bundled but never deployed.** The library
  carries a real Sublime package in `Sublime\texlib\` — 16 `texlib_*` Python
  modules (doctor, scaffold, bank, texam, complete, locate, …) plus
  `Main.sublime-menu`, the command palette entries, snippets, and the
  `TeXLib Build Output` syntax. It rides in every release ZIP, and through 0.6.4
  the installer copied only the four flat builder files into `Packages\User`.
  Anyone who installed got working Ctrl+B builds and none of the rest, while a
  developer running the library's own `deploy-plugin.ps1` got everything — so
  the difference was invisible from the one machine most likely to notice it.
  - It could not simply stay where it was: `Packages\User` is junctioned to
    `<library>\Sublime`, so the package was already *visible* at
    `Packages\User\texlib\`, but Sublime only loads `.py` at the **top level** of
    a package directory, which makes a nested folder inert. It now gets its own
    `Packages\TeXLib`, junctioned to the library copy exactly as
    `deploy-plugin.ps1` does — so an `-OnlyTeXLib` refresh updates the plugin
    with no extra step. `-Doctor` reports it, and a real folder already sitting
    at that path is left alone rather than clobbered.

### Added

- **`install.bat -Repair`** — re-applies configuration to an existing install
  and nothing else: the settings junction, the builder files, the Sublime
  package, the LaTeXTools / Preferences / SumatraPDF settings, the file
  associations (with the stale "Open with" purge), and the shortcuts. Downloads
  nothing, installs no components, leaves the library alone, and works offline.
  This is the answer to "my file associations went weird" or "Sublime stopped
  seeing the builder", which until now meant a full re-run. Refuses, with a
  reason, when there is no install to repair.
- **`install.bat -Update`** — fetches the newest release, verifies it against
  that release's `SHA256SUMS`, and hands off to it, forwarding every other
  argument you passed. The installer has told you about new versions since
  0.4.0; you still had to go find the ZIP, download it, extract it and re-run.
  Note the hash check is served by the same release over TLS, so it is a
  corruption check rather than an independent signature — worth knowing, not a
  reason to skip it.
- **`-TexLiveScheme full|medium|basic`** — `full` stays the default and the
  tested configuration, but it is ~6 GB and 30-60 minutes, which is essentially
  the entire install. `medium` (~2.5 GB, 5-15 min) and `basic` (~0.6 GB, 2-5
  min) trade coverage for time. The pre-flight disk requirement follows the
  scheme.
  - Paired with a new `-Doctor` check that resolves, via `kpsewhich`, all 50
    LaTeX packages TeXLib's `.sty`/`.cls` files actually `\RequirePackage` —
    derived by reading the library rather than guessed. A thin scheme therefore
    shows up as a named list plus a ready-to-paste `tlmgr install` line, instead
    of surfacing months later as `File 'tabularray.sty' not found` mid-build.
- **A "TeXLib" Start Menu folder** holding Sublime Text, SumatraPDF, and a
  **TeXLib Doctor** entry, replacing two loose shortcuts scattered among every
  other installed program. Doctor runs from the copy stashed in
  `<InstallPath>\Scripts`, so it still works after the extracted installer
  folder is long gone — which is exactly when someone needs it. The Desktop
  keeps the two apps only. Pre-0.7.0 loose entries are cleaned up on install,
  and the uninstaller removes the group unless the user has put something of
  their own in it.

### Testing

- New CI jobs `repair-mode` (rebuilds what you break, offline, library
  untouched; and refuses when there is nothing to repair) and `self-update-noop`
  (reaches the API and correctly decides to do nothing — guarded so a branch
  behind the latest release skips rather than kicking off a real install).
- `reuse-existing-library` now asserts the Sublime package is deployed as a
  junction at `Packages\TeXLib`.
- `dev-install-test.ps1` seeds a stub plugin, asserts the junction, and adds a
  `-Repair` pass that deletes the junction and a settings file and checks both
  come back without a download.

## [0.6.4] — 2026-08-03

Follow-up to 0.6.3, from watching a real uninstall run on a pre-0.6.3 machine.

### Fixed

- **"Remove the TeXLib library" named the junction, not the library.** On a
  machine upgraded from ≤0.6.2 with a comma/space OneDrive path, `texlib_root`
  is the `%USERPROFILE%\TeXLib` *junction*, so the prompt read
  `Remove the TeXLib library (C:\Users\you\TeXLib)?` while the library itself
  was on the far side of that link. Answering yes removed the link and reported
  `Removed`; the library was still in OneDrive. The prompt now names the folder
  whose contents actually go, and yes deletes that folder and then drops the
  link.
  - The same path was one PowerShell build away from being much worse. WinPS
    5.1's `Remove-Item -Recurse` on a junction removes only the link *here*, but
    the behaviour has never been dependable, and on a build that follows the
    link it would have emptied the OneDrive folder without ever having named it.
    `Uninstall-Component` now refuses to hand a reparse point to `Remove-Item`
    at all: it unlinks with `Directory.Delete(path, recursive: false)`, and any
    caller that means to delete the far side resolves the target first.

### Changed

- **Dropped the `PRESERVES (unless you say otherwise below)` block.** Every
  component is asked about and kept on request, so singling the library out as
  the preserved one was inconsistent -- and it read as a promise while the
  prompt three lines later offered to delete it. The confirmation screen is now
  two honest lists: what goes regardless (shortcuts, PATH, registry entries, the
  installer's own bookkeeping) and what you get asked about (Sublime Text,
  SumatraPDF, TeX Live, the library), with each component's real path.
- **The library is always prompted for, including inside the install root.**
  0.6.3 removed an in-root library silently on the grounds that it is a deployed
  artifact. It still defaults to going, but the question is now asked like every
  other component's. The only asymmetry left is the default answer, and it turns
  on location rather than on the component: inside the install root defaults to
  yes, a pre-0.6.3 library out in Documents defaults to no. `-Silent` takes
  exactly those defaults.
- **`UserChoice` entries Windows refuses to clear are reported once at the end**
  instead of a four-line `[WARN]` block per extension, and the note says what
  actually happens (the ProgID is gone, so Windows asks which app to use next
  time) rather than just that the delete failed.

## [0.6.3] — 2026-08-03

An uninstall-and-layout release. The uninstaller genuinely removes what it says it removes, the library stops living in `Documents`, Windows stops accumulating dead "Open with" entries, and the release folder no longer offers four things to double-click when only two of them work.

### Fixed

- **The uninstaller removed almost nothing.** `Start-Transcript` wrote its log to
  `%LOCALAPPDATA%\TeXLib\Logs\uninstall-<timestamp>.log` -- inside the very
  directory the next statement deleted -- and held the file open for the whole
  run. `Remove-Item -Recurse` walked the root in enumeration order, hit the
  locked log, and aborted. Everything after it alphabetically (`Sublime Text`,
  `Sumatra`, `TexLive`) was never touched, and the one-line
  `[WARN] Some files could not be removed` gave no hint that three of the four
  components had survived. The log now goes to `%TEMP%\TeXLib-Uninstall\`.
- **`Packages\User` is a junction, and `Remove-Item -Recurse` follows it.** In
  Windows PowerShell 5.1 that meant the uninstaller reached *through* the
  junction into the library's `Sublime\` folder -- deleting the user's settings
  where it could, and throwing partway through the root removal where it could
  not (a locked file or a OneDrive placeholder on the other side). Junctions
  under the install root are now unlinked with
  `Directory.Delete(path, recursive: false)` before anything is removed.
- **A running Sublime Text or SumatraPDF made the removal fail.** Their own
  executables are locked while running, which produced the same partial-removal
  abort. The uninstaller now detects processes whose image lives under the
  install root, offers to close them (`-Force` to skip the question; `-Silent`
  closes them), and asks nothing about a Sublime the user installed elsewhere.
- **One locked file no longer abandons the rest of the removal.** When the bulk
  `Remove-Item` fails, the uninstaller retries child by child and then reports
  exactly how many items are left and where, instead of a bare warning.

### Changed

- **The TeXLib library installs to `<InstallPath>\Library`** (by default
  `%LOCALAPPDATA%\TeXLib\Library`) instead of `<OneDrive>\Documents\TeXLib`. It
  now sits alongside the Sublime plugin it carries and the portable Sublime /
  Sumatra / TeX Live trees. `Documents` made sense while the library was a
  OneDrive-synced document tree; it no longer is. A deployed snapshot that every
  re-install overwrites does not belong among the user's own files, and on a
  machine that also has a git checkout of TeXLib it was landing on top of it.
  Bonus: on a normal profile the new path has no space or comma in it, so
  kpathsea resolves it without the `%USERPROFILE%\TeXLib` junction.
  - **Upgrades migrate automatically.** A pre-0.6.3 library in Documents /
    OneDrive is detected (from the previous install's `VERSION` stamp, then the
    two defaults it could have used), the user's `Sublime\` settings are carried
    across, and -- when this installer copy ships no `texlib\` bundle -- the
    whole library is copied over rather than the install failing. The old folder
    is never modified or deleted; the installer says where it is and leaves the
    decision to you.
  - The `%USERPROFILE%\TeXLib` junction a pre-0.6.3 install created for the old
    location is retired on the next install, but only when that install's own
    `VERSION` stamp claims it -- the same ownership rule the uninstaller uses.
  - The junction logic is no longer OneDrive-specific: it fires whenever the
    resolved library path contains a space or comma, and pre-flight now warns
    (instead of building a useless link) when `%USERPROFILE%` has one too.
- **`install.ps1` and `uninstall.ps1` moved into `tools\`.** The release folder
  now contains exactly two clickable things -- `install.bat` and
  `uninstall.bat` -- rather than four files whose names differ by an extension,
  two of which do nothing useful on a double-click. `package-integrity` asserts
  both the new location and the absence of the old one.
- **File associations are labelled `Sublime Text (TeXLib)` / `SumatraPDF
  (TeXLib)`** in the Open With dialog, so they are distinguishable from a
  Sublime or SumatraPDF the user installed themselves.

### Added

- **Stale "Open with" entries are cleared on every install.** Each install and
  uninstall used to leave its `Applications\<exe>` key, its ProgIDs, and its rows
  in Explorer's per-extension `OpenWithList` / `OpenWithProgids` / `UserChoice`
  behind, so the dialog slowly filled with duplicate Sublime and SumatraPDF
  entries pointing at executables that were long gone. Section 17 now purges
  them first and registers fresh afterwards (through the namespaced `TeXLib.*`
  ProgIDs only -- writing `Applications\sublime_text.exe` would name the *exe*
  rather than us, and HKCU shadows HKLM, so it would hijack the Open With entry
  of a Sublime the user installed in Program Files), then calls `SHChangeNotify`
  so Explorer rereads instead of showing the old list until the next sign-out.
  Malformed rows (values that name no exe, AUMID, or CLSID path -- they render
  as blank lines) go too. Only entries that are **ours** and **dead** are
  touched: liveness is resolved through `HKEY_CLASSES_ROOT`, the merged view
  Explorer itself uses, so a per-machine Sublime registered in `HKLM` is
  recognised as live and left alone. The uninstaller does the same on the way
  out. `-Doctor` reports any leftovers it finds.
- **Per-component uninstall.** An interactive `uninstall.bat` now asks about
  Sublime Text, SumatraPDF, and TeX Live separately -- keeping the 6 GB TeX Live
  tree across a reinstall saves 30-60 minutes -- and about a pre-0.6.3 library in
  Documents, which is still preserved by default. Switches for unattended runs:
  `-All`, `-RemoveLibrary`, `-KeepSublime`, `-KeepSumatra`, `-KeepTeXLive`,
  `-Force`.
- **`uninstall.ps1 -InstallPath`**, the counterpart to `install.ps1`'s. Without
  it the uninstaller hardcoded `%LOCALAPPDATA%\TeXLib` and could only ever clear
  the registry/PATH/shortcut artifacts of a non-default install. It also now
  reads component paths from the install's `VERSION` stamp rather than assuming
  them, so an install made with `-InstallPath` uninstalls cleanly.
- **`legacy-library-migration` CI job.** Seeds a pre-0.6.3 machine, installs, and
  asserts the library moved, the user's settings came with it, and the old folder
  is untouched -- then tears down with `-All` and asserts that the old folder
  still survives, because a folder the installer only read from is not its to
  delete. The `junction` job now reaches the comma/space path through
  `-InstallPath` (the runner has no OneDrive), and both teardown jobs assert that
  the components are actually gone.

## [0.6.2] — 2026-07-30

A reliability release for the **returning machine** — a computer that already has TeXLib. Every path unique to that state was broken or untested: reusing an already-synced library aborted the install at the very last step, the uninstaller crashed on a plain double-click before removing anything, the update check offered to "update" you to an older release, and the uninstaller would unlink a `%USERPROFILE%\TeXLib` junction it had never created. None of it was visible to CI, which only ever installed once onto a clean VM.

Also adds `-TeXLibPath` / `-Sandbox`, which make the installer runnable on a development machine without writing outside a throwaway directory, and the test tiers that keep the above from regressing.

This release refreshes the bundled TeXLib library to **v0.5.0** (v0.6.0 shipped v0.4.0, a 2026-07-13 snapshot). That brings the accessible (tagged PDF/UA) build mode, multiple-choice problems with more than one correct option, worked-response gating in `{challenge}` across both theorem stacks, and a `coursemeta.tex` search that reaches five levels up. One breaking change rides along: the Problem-Set `{hint}` environment is now a `\hint` command — see the library's own changelog.

> **v0.6.1 was prepared but never tagged or published** — no `v0.6.1` tag exists in this repository. Its changes (LaTeXTools' missing `regex` dependency, Ctrl+B pinned to the TeXLib build system, and reuse of an already-synced library) ship to users for the first time here. Anyone who ran a "0.6.1" build took it from the source tree, which is how the reuse path above got exercised before it was fixed.

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

- **Every documented `install.bat -Flag` / `uninstall.bat -Flag` form was
  broken** — present since v0.3.0 and shipped in v0.5.0, v0.5.1 and v0.6.0.
  `tools\boot_wrapper.ps1` collected passthrough arguments into an array and
  forwarded them with `& $InnerScript @InnerArgs`; **array splatting binds
  positionally** and never re-reads `-Silent` as a parameter name (only a
  hashtable splat does). The consequences differed by script, and the quieter
  one was the worse one:

  | invocation | before |
  | --- | --- |
  | `install.bat -Doctor` | ran a **full install** into a folder named `-Doctor` |
  | `install.bat -Silent` | installed **non**-silently into a folder named `-Silent` |
  | `install.bat -DryRun -Silent` | crashed |
  | `install.bat -InstallPath <dir>` | crashed |
  | `uninstall.bat -Silent` | crashed, exit 99, removing nothing |

  `install.ps1`'s positional `[string]$InstallPath` silently swallowed the first
  flag, so the two most-recommended commands in INSTALL.md — including
  "First thing to try: `install.bat -Doctor`" — did the opposite of what they
  say. The wrapper now reads the inner script's own parameter metadata to learn
  which names are switches, and rebuilds the tokens into a named hashtable plus
  positional array (handling `-Name:Value`, `-Switch:$false`, case, and unique
  prefixes; ambiguous or unknown names are forwarded as-is so the inner script
  reports them properly). If the metadata can't be read it falls back to the old
  positional splat — a boot wrapper degrades, it does not refuse to launch.

  Caught by the `full-install` teardown, which this release routes through
  `uninstall.bat` for the first time; `wrapper-arg-forwarding` previously tested
  only the zero-argument case, which is exactly how it went unnoticed.

- **The uninstaller removed any junction at `%USERPROFILE%\TeXLib`, not just
  its own.** It checked that the path was a reparse point — so a real folder was
  always safe, and the target's contents were never at risk — but not that the
  *installer* had created the link. On a developer machine that path is
  routinely a hand-made junction to a real library, and unlinking it silently
  breaks every TeX build resolving through it. `uninstall.ps1` now reads
  `texlib_root` from `<BaseDir>\VERSION` **before** removing the install
  directory (the file lives inside it) and removes the junction only when the
  installer claimed it. An unclaimed junction is left in place with its target
  printed; `-RemoveJunction` overrides deliberately.

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

- **`unit-helpers` CI job** — pure-logic coverage with no VM install and no
  network, the tier `install.ps1` had none of. The update-check comparison is
  now the named `Test-IsNewerVersion`, and the job lifts that function out of
  `install.ps1` **by AST** and runs a nine-case table against it (including the
  shipped downgrade bug and `0.6.10` vs `0.6.9`). Extracting rather than
  dot-sourcing a `tools\` library is deliberate: `install.ps1` stays a single
  self-contained script with no runtime dependency a release bundle could omit.
  The job fails loudly if the function is renamed or re-inlined. A second step
  covers `uninstall.ps1`'s `Test-InstallerOwnsJunction` the same way — there the
  isolation is the point, since the alternative is creating a real junction at
  `%USERPROFILE%\TeXLib`. A third covers `boot_wrapper.ps1`'s
  `ConvertTo-InnerArgumentBinding` across 19 token forms.
  `reuse-existing-library` also plants an *unclaimed* junction before teardown
  and asserts the uninstaller leaves it, and its target's contents, alone, and
  `wrapper-arg-forwarding` grew from a single zero-argument case into a
  ten-form matrix that drives the real wrapper against stubs shaped like the
  real scripts and checks **where each token actually lands** — the assertion
  the previous version was missing.

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

## [0.6.1] — 2026-07-04 (never published)

> Prepared but never tagged or released; there is no `v0.6.1` tag. These changes
> reached users in [0.6.2](#062--2026-07-23).

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

The TEXINPUTS comma trap, finally fixed in code. kpathsea (TeX Live's file resolver) splits `TEXINPUTS` entries on commas and chokes on spaces, so the UNR OneDrive folder ("OneDrive - University of Nevada, Reno") has silently broken every install on a UNR machine since v0.1.0. The junction at `%USERPROFILE%\TeXLib` was hand-created to work around it; coworkers didn't know to. v0.2.0's Doctor mode only printed a TEXINPUTS warning — useful diagnosis, no actual repair.

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

- **`texlib/Sublime/LaTeX.sublime-settings`** in the TeXLib bundle — a syntax-scoped settings file with ~430 mathematician names + standard math terminology + LaTeX command fragments under `added_words`, and the usual LaTeX layout dimensions under `ignored_words`. Sourced from an accumulated personal list, deduped, alphabetized, augmented with ~110 standard mathematician names and ~280 standard algebra/analysis/topology/geometry terms. Stacks on top of the user's global `Preferences.sublime-settings`, so personal proper nouns (collaborators, lab references, course-internal jargon) still apply when editing `.tex` files. Stuck-suffix artifacts (`ness`, `th`, `ech`, `lder`) intentionally excluded — they mask real typos; the accented forms (`Čech`, `Hölder`) are included instead.
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

[Unreleased]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.11.3...HEAD
[0.11.3]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.11.2...v0.11.3
[0.11.2]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.11.1...v0.11.2
[0.6.2]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.6.0...v0.6.2
[0.6.0]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.2.1...v0.5.0
[0.2.1]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/landonfox00/TeXLib-Installer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/landonfox00/TeXLib-Installer/releases/tag/v0.1.0
