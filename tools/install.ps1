<#
.SYNOPSIS
    TeXLib-Installer: portable Windows install of Sublime Text + SumatraPDF +
    TeX Live, pre-configured to use the TeXLib teaching library.

.DESCRIPTION
    Installs everything per-user under %LOCALAPPDATA%\TeXLib (no admin needed).
    Downloads each component, verifies its SHA256/SHA512 hash, and aborts if
    the hash doesn't match (no continue-anyway prompts).

    Hardware/software requirements:
      - Windows 10 (1809+) or Windows 11
      - PowerShell 5.1 or newer
      - ~6 GB free disk space (TeX Live full)
      - Working internet connection
      - PowerShell script execution allowed (Bypass is set by the .bat wrapper)

.PARAMETER Silent
    Skip all interactive prompts. Uses safe defaults: skip any component that
    is already installed, abort on hash mismatch. Used for unattended setup.

.PARAMETER Doctor
    Skip installation; instead diagnose an existing install. Prints a
    pass/warn/fail report you can paste into a bug report.

.PARAMETER Version
    Print installer version + bundled component versions and exit. Lightweight
    -- no network calls (unless combined with non-silent update check).

.PARAMETER DryRun
    Run pre-flight checks and summarize what would happen, but do not modify
    the system. Useful for piloting on a new machine.

.PARAMETER OnlyTeXLib
    Refresh only the TeXLib library bundle and Sublime builder files. Skips
    re-installing Sublime / SumatraPDF / TeX Live entirely. Use after pulling
    a newer installer release whose only change is the library.

.PARAMETER InstallPath
    Override the install root. Defaults to %LOCALAPPDATA%\TeXLib. Use this if
    %LOCALAPPDATA% lives on a small SSD or is locked down by Group Policy.

.PARAMETER HideJunction
    Apply the +h (hidden) file attribute to the %USERPROFILE%\TeXLib junction,
    which gets created only when the library path contains a space or comma
    (i.e. when -InstallPath points somewhere with one). Off by default -- a
    visible junction is easier to discover and diagnose. No effect when no
    junction is needed, which is the normal case as of 0.6.3.

.PARAMETER TeXLibPath
    Override where the TeXLib library lives. Defaults to <InstallPath>\Library,
    so it sits alongside the Sublime plugin and moves with -InstallPath.
    Setting this also suppresses the %USERPROFILE%\TeXLib junction and any
    migration from a pre-0.6.3 location: an explicit path is taken as
    deliberate, so the installer does not second-guess it. Pair with -Sandbox
    for a throwaway run on a machine you care about.

.PARAMETER Sandbox
    Skip every write that lands outside -InstallPath / -TeXLibPath: the user
    PATH entry, the HKCU file associations, and the Desktop / Start Menu
    shortcuts. Everything else runs for real, so the component install, the
    library deploy, the Packages\User junction, and the builder config are all
    still exercised. Intended for developing ON the installer -- a full run
    against a seeded state with nothing left to clean up afterwards. Warns if
    used without -InstallPath or -TeXLibPath, since those are what keep the
    remaining writes inside the sandbox.

.PARAMETER VerifyDownloads
    Hash-rot canary. Download each pinned component and verify its SHA256/512
    against $Downloads, then exit -- without installing anything, touching the
    registry/PATH/junction, or needing the texlib bundle. Exit 0 if every hash
    matches, 20 if any drifted (a vendor silently repackaged a pinned artifact;
    re-pin it). Used by CI to catch the break before a coworker does.

.NOTES
    Refresh procedure (when component versions go stale):
      1. Edit the $Downloads hashtable below with the new file name + URL.
      2. For "Static" entries, recompute the SHA256 with:
           Get-FileHash <path-to-downloaded-zip> -Algorithm SHA256
         and paste into the Hash field.
      3. Bump $InstallerVersion below.
      4. Update CHANGELOG.md.
      5. Tag and re-release.

    Support: open an issue at
      https://github.com/landonfox00/TeXLib-Installer/issues
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    [switch]$Doctor,
    [switch]$Version,
    [switch]$DryRun,
    [switch]$OnlyTeXLib,
    [string]$InstallPath = "",
    [string]$TeXLibPath = "",
    [switch]$Sandbox,
    [switch]$HideJunction,
    [switch]$VerifyDownloads
)

# =============================================================================
# 0. INSTALLER METADATA
# =============================================================================
$InstallerVersion = "0.6.3"
$InstallerRepo    = "https://github.com/landonfox00/TeXLib-Installer"
$ReleasesApi      = "https://api.github.com/repos/landonfox00/TeXLib-Installer/releases/latest"

# Fail fast: a non-terminating error in a download/extract/copy step must abort
# the install rather than silently barrel on into a half-built state.
$ErrorActionPreference = "Stop"

# PowerShell 5.1 may negotiate TLS 1.0/1.1 by default, which several CDNs
# (including GitHub) now reject -- producing an opaque download failure. Force
# TLS 1.2 (kept additive so a host that already enables 1.3 is unaffected).
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { $null = $_ }

# --- Early exit + banner -----------------------------------------------------
# Defined up here (before the user-root junction logic in section 1) because
# that block can call Stop-Installer on its failure paths, which execute at
# script load -- before the rest of the function definitions further down.
function Show-Banner {
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "   TeXLib-Installer v$InstallerVersion"        -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Stop-Installer {
    param([int]$ExitCode = 0)
    # Stop-Transcript throws if no transcript is running; that's expected for
    # early-exit paths (e.g. -Version, or a junction failure before logging
    # starts), so swallow it deliberately.
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    # Always clear the (possibly multi-GB) download scratch on the way out, so a
    # failed run doesn't leave %TEMP%\TeXLib_Install behind. The success path
    # cleans it in section 21; this covers every non-success Stop-Installer exit.
    # ($TempDir is $null on the very early junction failure paths -> guarded.)
    if ($TempDir -and (Test-Path $TempDir)) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    # When launched via install.bat -> tools\boot_wrapper.ps1, the wrapper
    # owns the pause-on-failure prompt and the exit-code surfacing. Skip our
    # own prompt to avoid two "Press Enter to close" prompts back to back.
    # Direct PS launches (no bat) still see the prompt here.
    if (-not $Silent -and $ExitCode -ne 0 -and -not $env:TEXLIB_INSTALLER_WRAPPED) {
        Write-Host ""
        Write-Host "Installer exited with code $ExitCode." -ForegroundColor Red
        Write-Host "If you need help, attach the log file above to a new issue at" -ForegroundColor Yellow
        Write-Host "  $InstallerRepo/issues" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    exit $ExitCode
}


# =============================================================================
# 1. SETUP VARIABLES
# =============================================================================
# This script lives in tools\; everything it reads (templates\, the texlib\
# bundle, any pre-staged component ZIPs) sits at the release root one level up.
# Keeping the .ps1 files out of that root is deliberate: the only clickable
# things a user sees there are install.bat and uninstall.bat, so there is
# nothing to mis-click.
$ScriptDir  = Split-Path $PSScriptRoot -Parent

# Install location (per-user, no admin needed). -InstallPath overrides.
$BaseDir = if ($InstallPath) { $InstallPath } else { "$env:LOCALAPPDATA\TeXLib" }
$ScriptsDir = "$BaseDir\Scripts"
$LogDir     = "$BaseDir\Logs"

# Program paths.
# TeX Live's tlnet installer always installs the current year; we pin the tree
# name here in ONE place so a yearly bump is a single edit rather than a
# scattered find-and-replace. (install-tl honors the explicit TEXDIR in the
# profile, so the folder name is just a label.)
$TexLiveYear = "2025"
$SublimeDir = "$BaseDir\Sublime Text"
$SumatraDir = "$BaseDir\Sumatra"
$TexLiveDir = "$BaseDir\TexLive\$TexLiveYear"
$TexBinPath = "$TexLiveDir\bin\windows"

# TeXLib bundle: a `texlib\` directory at the release root (one level up from
# this script) holding the TeXLib library snapshot. The release ZIP includes it.
$TexLibBundle = Join-Path $ScriptDir "texlib"

# --- TeXLib library location -------------------------------------------------
# The library is deployed INSIDE the install root, next to the portable Sublime
# Text / SumatraPDF / TeX Live trees -- and so next to the Sublime plugin, which
# rides in the library's own Sublime\ subfolder and is junctioned in as
# Packages\User.
#
# Through 0.6.2 it went to <OneDrive>\Documents\TeXLib instead, from back when
# the library was a OneDrive-synced document tree. It no longer is, and a
# deployed snapshot that every re-install overwrites has no business in
# Documents: there it is indistinguishable from the user's own work, and on a
# machine that also has a git checkout of TeXLib it lands right on top of it.
# Keeping it under the install root also makes the uninstall a single directory
# removal, and on a normal profile hands kpathsea a path with no space or comma
# in it -- which is what the junction below exists to work around.
$DefaultTeXLibDir = "$BaseDir\Library"

$OneDrivePath = $env:OneDrive
if (-not $OneDrivePath) { $OneDrivePath = $env:OneDriveCommercial }
if (-not $OneDrivePath) { $OneDrivePath = $env:OneDriveConsumer }

# -TeXLibPath still wins and is still taken as deliberate: no junction is built
# for it, and no legacy location is migrated into it (notably for -Sandbox runs,
# where that junction is the one artifact left outside the sandbox).
$ExplicitTeXLibPath = [bool]$TeXLibPath
$TeXLibDir = if ($ExplicitTeXLibPath) { $TeXLibPath } else { $DefaultTeXLibDir }

# Kept in the VERSION stamp for continuity with pre-0.6.3 installs. True only
# when the resolved library really sits inside OneDrive (an explicit -TeXLibPath
# pointed there), never merely because OneDrive is present on the machine.
$UsingOneDrive = [bool]($OneDrivePath -and ($TeXLibDir -like "$OneDrivePath*"))

# Writes that land outside -InstallPath / -TeXLibPath: user PATH (14), HKCU
# file associations (17), Desktop + Start Menu shortcuts (18). -Sandbox skips
# exactly those three and nothing else.
$WriteMachineState = (-not $OnlyTeXLib) -and (-not $Sandbox)

function Test-TeXLibLibraryDir {
    # A directory counts as a TeXLib library only when the core .sty files are
    # actually in it -- the same probe pre-flight 7i and the Doctor use, so an
    # empty leftover folder never passes for a library.
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path $Dir)) { return $false }
    foreach ($f in @("course-metadata.sty", "texlib-build.sty", "basic-utilities.sty")) {
        if (-not (Test-Path (Join-Path $Dir $f))) { return $false }
    }
    return $true
}

function Get-ShellCommandExe {
    # Pull the executable out of a shell command. Two shapes turn up in the
    # wild, and only one of them is well behaved:
    #     "C:\path\app.exe" "%1"            -- quoted
    #     C:\Program Files\app.exe "%1"     -- UNQUOTED, spaces and all
    # Splitting the second on whitespace yields "C:\Program", which does not
    # exist -- so a naive parse declares a perfectly live app dead and the purge
    # below rips it out of the user's Open With lists. Match up to the FIRST
    # .exe instead, and keep first-token as a last resort.
    param([string]$Command)
    if (-not $Command) { return $null }
    if ($Command -match '^\s*"([^"]+)"')        { return $Matches[1] }
    if ($Command -match '^\s*(.*?\.exe)(\s|$)') { return $Matches[1] }
    if ($Command -match '^\s*(\S+)')            { return $Matches[1] }
    return $null
}

function Test-ShellCommandLive {
    # A shell registration is stale when the exe it names is no longer on disk
    # -- which is exactly what every leftover "Open with" entry looks like.
    # Shared by the Doctor's association check and section 17's purge.
    param([string]$RegKey)
    if (-not (Test-Path $RegKey)) { return $false }
    $cmd = $null
    try { $cmd = (Get-Item -Path $RegKey).GetValue("") } catch { $cmd = $null }
    $exe = Get-ShellCommandExe $cmd
    if (-not $exe) { return $false }
    return (Test-Path $exe)
}

function Get-StampedValue {
    # Read one `key=value` line out of a VERSION stamp. $null when absent/blank.
    param([string]$VersionFile, [string]$Key)
    if (-not $VersionFile -or -not (Test-Path $VersionFile)) { return $null }
    $line = Get-Content $VersionFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "^\s*$([regex]::Escape($Key))\s*=" } |
            Select-Object -First 1
    if (-not $line) { return $null }
    $val = ($line -split '=', 2)[1]
    if (-not $val) { return $null }
    $val = $val.Trim()
    if (-not $val) { return $null }
    return $val
}

# --- Pre-0.6.3 library locations ---------------------------------------------
# A returning machine has its library -- and, more to the point, the user's own
# Sublime settings -- in one of these. They serve two purposes: seeding the new
# location with those settings, and standing in as an install source when this
# installer copy ships no texlib\ bundle. Priority is most-authoritative first:
# what the previous install actually stamped, then the two defaults it could
# have picked, then the user-root junction those were reached through.
$PriorTeXLibRoot = Get-StampedValue -VersionFile "$BaseDir\VERSION" -Key "texlib_root"

$LegacyTeXLibDir = $null
if (-not $ExplicitTeXLibPath) {
    $LegacyCandidates = @()
    if ($PriorTeXLibRoot) { $LegacyCandidates += $PriorTeXLibRoot }
    if ($OneDrivePath)    { $LegacyCandidates += "$OneDrivePath\Documents\TeXLib" }
    $LegacyCandidates += "$env:USERPROFILE\Documents\TeXLib"
    $LegacyCandidates += "$env:USERPROFILE\TeXLib"
    foreach ($Candidate in $LegacyCandidates) {
        if ($Candidate.TrimEnd('\') -ieq $TeXLibDir.TrimEnd('\')) { continue }
        if (Test-TeXLibLibraryDir $Candidate) { $LegacyTeXLibDir = $Candidate; break }
    }
}

# --- User-root junction (TEXINPUTS-safe path) --------------------------------
# kpathsea (TeX Live's file resolver) splits TEXINPUTS on commas and chokes on
# spaces. The default library path (%LOCALAPPDATA%\TeXLib\Library) is clean on a
# normal profile, so as of 0.6.3 this is a fallback rather than the usual case:
# it fires when -InstallPath puts the library somewhere with a space or comma in
# it. We pipe the path through a junction at %USERPROFILE%\TeXLib and reassign
# $TeXLibDir to the clean path so every downstream consumer (settings template,
# deploy target, version stamp, doctor) sees a sane location.
# Idempotent across re-runs; not touched in Doctor/Version/DryRun modes.
$UserRootJunction       = "$env:USERPROFILE\TeXLib"
$UserRootJunctionTarget = $TeXLibDir
# The junction only helps if the junction's OWN path is clean. With a Windows
# account named "Jane Smith", %USERPROFILE%\TeXLib carries the same space the
# library path did, so rehoming through it would fix nothing while adding a
# reparse point to explain. Pre-flight warns about that case instead.
$JunctionPathIsClean    = ($UserRootJunction -notmatch '[ ,]')
$DirtyTeXLibPath        = (-not $ExplicitTeXLibPath) -and ($TeXLibDir -match '[ ,]')
$NeedsUserRootJunction  = $DirtyTeXLibPath -and $JunctionPathIsClean
$UnfixableTeXLibPath    = $DirtyTeXLibPath -and (-not $JunctionPathIsClean)
$UserRootJunctionState  = "not-needed"   # not-needed | present | blocked | will-create

if ($NeedsUserRootJunction) {
    if (Test-Path $UserRootJunction) {
        $UserRootItem = Get-Item $UserRootJunction -Force
        if ($UserRootItem.Attributes -match 'ReparsePoint') {
            $UserRootJunctionState = "present"
            $TeXLibDir = $UserRootJunction
        } else {
            $UserRootJunctionState = "blocked"
        }
    } else {
        $UserRootJunctionState = "will-create"
    }

    # Only the install path mutates disk. Doctor / Version / DryRun observe
    # and report, never create.
    if (-not ($Version -or $Doctor -or $DryRun -or $VerifyDownloads)) {
        if ($UserRootJunctionState -eq "blocked") {
            Write-Host ""
            Write-Host "FATAL: $UserRootJunction exists but is not a junction." -ForegroundColor Red
            Write-Host "       The installer needs to create a junction here so TeX can resolve" -ForegroundColor Red
            Write-Host "       $TeXLibDir, which contains a space or comma. Move or rename the" -ForegroundColor Red
            Write-Host "       existing folder (it looks like a real directory you created" -ForegroundColor Red
            Write-Host "       yourself) and re-run the installer -- or pass -InstallPath with a" -ForegroundColor Red
            Write-Host "       path free of spaces and commas." -ForegroundColor Red
            Write-Host ""
            Stop-Installer 12
        }
        if ($UserRootJunctionState -eq "will-create") {
            try {
                if (-not (Test-Path $UserRootJunctionTarget)) {
                    New-Item -ItemType Directory -Force -Path $UserRootJunctionTarget | Out-Null
                }
                New-Item -ItemType Junction -Path $UserRootJunction -Target $UserRootJunctionTarget -ErrorAction Stop | Out-Null
                Write-Host "Created user-root junction $UserRootJunction -> $UserRootJunctionTarget" -ForegroundColor Green
                $UserRootJunctionState = "present"
                $TeXLibDir = $UserRootJunction
            } catch {
                Write-Host "FATAL: Could not create junction at $UserRootJunction : $_" -ForegroundColor Red
                Stop-Installer 13
            }
        }
        if ($HideJunction -and ($UserRootJunctionState -eq "present")) {
            try { & attrib.exe +h $UserRootJunction } catch { $null = $_ }
        }
    }
}

# A pre-0.6.3 install rehomed the library through this same junction and stamped
# it as texlib_root. With the library now inside the install root, that junction
# is a leftover -- and one this installer is entitled to retire, because the
# stamp proves we created it (the same ownership rule uninstall.ps1 applies).
# Retired in section 11b, after the settings behind it have been carried over.
$StaleUserRootJunction = $null
if ((-not $NeedsUserRootJunction) -and $PriorTeXLibRoot -and
    ($PriorTeXLibRoot.TrimEnd('\') -ieq $UserRootJunction.TrimEnd('\')) -and
    (Test-Path $UserRootJunction)) {
    if ((Get-Item $UserRootJunction -Force).Attributes -match 'ReparsePoint') {
        $StaleUserRootJunction = $UserRootJunction
    }
}

$SublimeUserSync = "$TeXLibDir\Sublime"
$TempDir = "$env:TEMP\TeXLib_Install"

# Pinned component versions.
$Downloads = @{
    "sublime" = @{
        "Url"  = "https://download.sublimetext.com/sublime_text_build_4180_x64.zip"
        "File" = "sublime_text_build_4180_x64.zip"
        "Type" = "Static"
        "Hash" = "A8855CC1834F644CD3B74E5B90B73AE5CDA60F0172284B979B99A6B5A1E0A912"
    }
    "sumatra" = @{
        "Url"  = "https://www.sumatrapdfreader.org/dl/rel/3.5.2/SumatraPDF-3.5.2-64.zip"
        "File" = "SumatraPDF-3.5.2-64.zip"
        "Type" = "Static"
        "Hash" = "66CCB395C9184DCE6822DFBB9970C877383B3EAD6D9417B5106A844AAC512989"
    }
    "texlive" = @{
        "Url"     = "https://mirror.ctan.org/systems/texlive/tlnet/install-tl.zip"
        "HashUrl" = "https://mirror.ctan.org/systems/texlive/tlnet/install-tl.zip.sha512"
        "File"    = "install-tl.zip"
        "Type"    = "Dynamic"
    }
    "pkgctrl" = @{
        # Rolling file (no per-release URL); left unhashed intentionally.
        "Url"  = "https://packagecontrol.io/Package%20Control.sublime-package"
        "File" = "Package Control.sublime-package"
        "Type" = "Skip"
    }
    "latextools" = @{
        # Pinned to a tagged release (NOT the moving master branch) and hashed,
        # so the installer can't run an unverified, ever-changing copy of the
        # third-party Python that Sublime executes. To bump: pick a newer tag at
        # github.com/SublimeText/LaTeXTools/releases, then recompute SHA256 with
        #   Get-FileHash <downloaded zip> -Algorithm SHA256
        # A hash mismatch fails the install closed (won't run unverified bytes);
        # if GitHub regenerates the tag archive, refresh the hash here.
        "Url"  = "https://github.com/SublimeText/LaTeXTools/archive/refs/tags/st4-4.5.12.zip"
        "File" = "latextools.zip"
        "Type" = "Static"
        "Hash" = "3952E9F4825D706DB1A579B52E70663AFA4674C2501A30A8168631424D7AD1B6"
    }
    "regex" = @{
        # LaTeXTools' one build-critical dependency. Its plugin.py imports the
        # whole package at load time, and latextools\utils\analysis.py does a
        # bare `import regex`; with regex absent that import throws, plugin.py
        # fails, NO LaTeXTools command registers (including latextools_make_pdf),
        # and Ctrl+B silently does nothing. Package Control installs this for
        # you -- but we drop LaTeXTools as a raw archive, so we install it too.
        # Sublime Text 4's plugin host is CPython 3.8 (win-amd64), so the
        # cp38-win_amd64 wheel is the correct ABI for every Windows box. To bump:
        # pick a version at pypi.org/project/regex/#files, take the matching
        # cp38-cp38-win_amd64 wheel URL + its SHA256. (mdpopups, the other
        # LaTeXTools dependency, is imported guarded -- previews only -- skipped.)
        "Url"  = "https://files.pythonhosted.org/packages/cf/69/c39e16320400842eb4358c982ef5fc680800866f35ebfd4dd38a22967ce0/regex-2024.11.6-cp38-cp38-win_amd64.whl"
        "File" = "regex.zip"
        "Type" = "Static"
        "Hash" = "BB8F74F2F10DBF13A0BE8DE623BA4F9491FAF58C24064F32B65679B021ED0001"
    }
}

# Folder name inside the pinned LaTeXTools archive (GitHub names it
# "<repo>-<tag>"). Update alongside the latextools tag above.
$LaTeXToolsZipDir = "LaTeXTools-st4-4.5.12"

# The SumatraPDF portable exe is named by version (SumatraPDF-3.5.2-64.exe).
# Derive it ONCE from the pinned zip filename so a version bump only touches the
# $Downloads entry above instead of five scattered string literals.
$SumatraExeName = $Downloads["sumatra"].File -replace '\.zip$', '.exe'


# =============================================================================
# 2. LOGGING
# =============================================================================
# Logs go inside the install dir; if it doesn't exist yet (first run), TEMP.
$EffectiveLogDir = if (Test-Path $BaseDir) { $LogDir } else { "$env:TEMP\TeXLib-Install" }
New-Item -ItemType Directory -Force -Path $EffectiveLogDir | Out-Null
$LogFile = "$EffectiveLogDir\install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile -IncludeInvocationHeader | Out-Null

# (Show-Banner and Stop-Installer are defined near the top of the script, above
# the section-1 user-root junction block that calls Stop-Installer at load time.)


# =============================================================================
# 3. UPDATE CHECKER
# =============================================================================
# Pure, side-effect-free, and deliberately kept as a NAMED function rather than
# inlined: the unit-helpers CI job lifts it out of this file by AST and runs a
# case table against it. Keeping it here (instead of a dot-sourced tools\ lib)
# means install.ps1 gains no runtime dependency that could go missing from a
# release bundle -- the 2026-06-15 flash-and-die was exactly that failure mode.
function Test-IsNewerVersion {
    param([string]$Candidate, [string]$Current)

    if (-not $Candidate) { return $false }
    # Compare numerically, not with -ne: a local build AHEAD of the newest
    # published tag (the normal state while cutting a release) would otherwise
    # be told to "update" to an older version. String comparison also orders
    # 0.6.10 before 0.6.9. Fall back to string inequality only when a side is
    # not a parseable dotted version (e.g. a "1.0.0-beta" tag).
    $cand = $null; $cur = $null
    if ([Version]::TryParse($Candidate, [ref]$cand) -and
        [Version]::TryParse($Current,   [ref]$cur)) {
        return ($cand -gt $cur)
    }
    return ($Candidate -ne $Current)
}

function Test-LatestVersion {
    # Best-effort GitHub API check. Never fatal -- print the result and move on.
    try {
        $resp = Invoke-RestMethod -Uri $ReleasesApi -TimeoutSec 5 -ErrorAction Stop
        $latest = $resp.tag_name -replace '^v', ''
        if (Test-IsNewerVersion -Candidate $latest -Current $InstallerVersion) {
            Write-Host "Update available: v$latest is the latest release (you are on v$InstallerVersion)" -ForegroundColor Yellow
            Write-Host "  Download: $($resp.html_url)" -ForegroundColor Yellow
            Write-Host ""
        } else {
            Write-Host "Update check: you're on the latest version (v$InstallerVersion)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "Update check: could not reach $ReleasesApi (offline?); continuing" -ForegroundColor Gray
    }
}


# =============================================================================
# 4. VERSION INFO MODE
# =============================================================================
function Show-VersionInfo {
    Show-Banner
    Write-Host "Installer version: $InstallerVersion" -ForegroundColor Gray

    $VersionFile = "$BaseDir\VERSION"
    if (Test-Path $VersionFile) {
        Write-Host ""
        Write-Host "Installed version (from $VersionFile):" -ForegroundColor Gray
        Get-Content $VersionFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    } else {
        Write-Host ""
        Write-Host "No installed install found at $BaseDir" -ForegroundColor Yellow
    }

    if (Test-Path $TexLibBundle) {
        $ChangelogPath = Join-Path $TexLibBundle "CHANGELOG.md"
        if (Test-Path $ChangelogPath) {
            $TopVersionLine = (Get-Content $ChangelogPath | Select-String -Pattern '^## \[(?<ver>[^\]]+)\]' | Select-Object -First 1)
            if ($TopVersionLine -and $TopVersionLine.Matches[0].Groups['ver'].Value -ne 'Unreleased') {
                Write-Host ""
                Write-Host "Bundled TeXLib version: $($TopVersionLine.Matches[0].Groups['ver'].Value)" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Stop-Installer 0
}


# =============================================================================
# 5. DOCTOR MODE
# =============================================================================
function Invoke-Doctor {
    Show-Banner
    Write-Host "TeXLib Doctor -- diagnostic report" -ForegroundColor Cyan
    Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')" -ForegroundColor Gray
    Write-Host ""

    $script:DoctorOK = 0
    $script:DoctorWarn = 0
    $script:DoctorFail = 0

    function _Pass { param($M); Write-Host "  [OK]   $M" -ForegroundColor Green; $script:DoctorOK++ }
    function _Warn { param($M); Write-Host "  [WARN] $M" -ForegroundColor Yellow; $script:DoctorWarn++ }
    function _Fail { param($M); Write-Host "  [FAIL] $M" -ForegroundColor Red; $script:DoctorFail++ }

    # 5a. Install location.
    Write-Host "Install location:" -ForegroundColor Cyan
    $VersionFile = "$BaseDir\VERSION"
    if (Test-Path $VersionFile) {
        $InstalledMeta = Get-Content $VersionFile | Out-String
        $InstalledVer = ($InstalledMeta -split "`n" | Where-Object { $_ -match '^installer_version=' } | ForEach-Object { ($_ -split '=')[1].Trim() })
        _Pass "$BaseDir exists (installer v$InstalledVer)"
    } elseif (Test-Path $BaseDir) {
        _Warn "$BaseDir exists but VERSION file missing (partial install?)"
    } else {
        _Fail "$BaseDir does not exist (no install detected at this path)"
        Write-Host ""
        Write-Host "Doctor cannot continue without an install. Run install.bat first." -ForegroundColor Yellow
        Write-Host ""
        Stop-Installer 1
    }
    Write-Host ""

    # 5b. Components.
    Write-Host "Components:" -ForegroundColor Cyan
    if (Test-Path "$SublimeDir\sublime_text.exe") { _Pass "Sublime Text at $SublimeDir" }
    else { _Fail "Sublime Text missing or incomplete at $SublimeDir" }

    $SumExe = Get-ChildItem -Path $SumatraDir -Filter "SumatraPDF*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($SumExe) { _Pass "SumatraPDF at $($SumExe.FullName)" }
    else { _Fail "SumatraPDF missing or incomplete at $SumatraDir" }

    if (Test-Path "$TexBinPath\pdflatex.exe") { _Pass "TeX Live at $TexLiveDir" }
    else { _Fail "TeX Live missing or incomplete at $TexLiveDir" }
    Write-Host ""

    # 5c. LaTeX environment.
    Write-Host "LaTeX environment:" -ForegroundColor Cyan
    $PathPdflatex = Get-Command pdflatex -ErrorAction SilentlyContinue
    # A freshly added user-PATH entry isn't visible to the current process (PATH
    # is read at process start), so Get-Command misses it right after install /
    # in the same session. Check the PERSISTED user PATH (registry) too, not just
    # this process's $env:PATH, before declaring pdflatex missing.
    $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $OnPersistedPath = $UserPath -and (($UserPath -split ';') | Where-Object { $_.TrimEnd('\') -ieq $TexBinPath.TrimEnd('\') })
    if ($PathPdflatex -and ($PathPdflatex.Source -like "$TexBinPath\*")) {
        _Pass "pdflatex on PATH points to this install ($($PathPdflatex.Source))"
    } elseif ($PathPdflatex) {
        _Warn "pdflatex on PATH is from a DIFFERENT install: $($PathPdflatex.Source)"
    } elseif ((Test-Path "$TexBinPath\pdflatex.exe") -and $OnPersistedPath) {
        _Pass "pdflatex installed and on the persisted user PATH (open a new terminal to use it; this session hasn't reloaded PATH)"
    } elseif (Test-Path "$TexBinPath\pdflatex.exe") {
        _Fail "pdflatex.exe is at $TexBinPath but that dir is not on the user PATH; re-run the installer or add it manually"
    } else {
        _Fail "pdflatex not on PATH; reinstall or add $TexBinPath manually"
    }

    # Diagnose the library where THIS machine actually has it. The VERSION stamp
    # is the authority: on a pre-0.6.3 install it still points into Documents,
    # and reporting the 0.6.3 default missing would be a false alarm.
    $DoctorTeXLibDir = if ($PriorTeXLibRoot) { $PriorTeXLibRoot } else { $TeXLibDir }
    if (Test-Path $DoctorTeXLibDir) {
        $CoreFiles = @("course-metadata.sty", "texlib-build.sty", "basic-utilities.sty")
        $MissingCore = $CoreFiles | Where-Object { -not (Test-Path (Join-Path $DoctorTeXLibDir $_)) }
        if ($MissingCore.Count -eq 0) {
            _Pass "TeXLib library at $DoctorTeXLibDir (core .sty files present)"
        } else {
            _Warn "TeXLib library at $DoctorTeXLibDir but missing: $($MissingCore -join ', ')"
        }
    } else {
        _Fail "TeXLib library directory $DoctorTeXLibDir does not exist"
    }
    if ($PriorTeXLibRoot -and ($PriorTeXLibRoot.TrimEnd('\') -ine $TeXLibDir.TrimEnd('\')) -and -not $ExplicitTeXLibPath) {
        _Warn "The library is at the pre-0.6.3 location $PriorTeXLibRoot; 0.6.3+ installs it to $TeXLibDir. Re-run the installer to move it (your Sublime settings come along; the old folder is left for you to delete)."
    }

    # User-root junction (created when the library path contains a space/comma).
    if ($NeedsUserRootJunction) {
        if ($UserRootJunctionState -eq "present") {
            _Pass "User-root junction $UserRootJunction -> $UserRootJunctionTarget (TEXINPUTS-safe)"
        } elseif ($UserRootJunctionState -eq "blocked") {
            _Fail "$UserRootJunction exists but is NOT a junction; TeX commands will fail because $UserRootJunctionTarget contains a space/comma. Move or rename the folder and re-run the installer."
        } else {
            _Fail "The library path contains a space/comma but the $UserRootJunction junction is missing. Re-run the installer to create it."
        }
    } elseif ($UnfixableTeXLibPath) {
        _Warn "$TeXLibDir contains a space or comma and $UserRootJunction cannot alias it (it has one too); kpathsea may not resolve the library. Re-install with -InstallPath set to a path free of spaces and commas."
    }
    if ($StaleUserRootJunction) {
        _Warn "$StaleUserRootJunction is a leftover junction from the pre-0.6.3 library location. Re-run the installer to retire it (its target is preserved)."
    }
    Write-Host ""

    # 5d. Sublime configuration.
    Write-Host "Sublime configuration:" -ForegroundColor Cyan
    $UserPackagesLocal = "$SublimeDir\Data\Packages\User"
    if (Test-Path $UserPackagesLocal) {
        $Item = Get-Item $UserPackagesLocal -Force
        if ($Item.Attributes -match "ReparsePoint") {
            _Pass "User packages folder is a junction (sync enabled)"
        } else {
            _Warn "User packages folder exists but is NOT a junction (sync disabled)"
        }
    } else {
        _Fail "User packages folder $UserPackagesLocal does not exist"
    }

    $BuilderPath = "$UserPackagesLocal\texlib_builder.py"
    if (Test-Path $BuilderPath) { _Pass "texlib_builder.py deployed" }
    else { _Fail "texlib_builder.py missing from $UserPackagesLocal" }

    $LTSettings = "$UserPackagesLocal\LaTeXTools.sublime-settings"
    if (Test-Path $LTSettings) {
        $Content = Get-Content $LTSettings -Raw
        if ($Content -match '"builder"\s*:\s*"texlib"') {
            _Pass "LaTeXTools.sublime-settings has `"builder`": `"texlib`""
        } else {
            _Fail "LaTeXTools.sublime-settings exists but builder is not set to 'texlib'"
        }
    } else {
        _Fail "LaTeXTools.sublime-settings missing from $UserPackagesLocal"
    }

    # LaTeXTools' build-critical `regex` dependency (see $Downloads). Missing =>
    # plugin.py fails to load, latextools_make_pdf never registers, Ctrl+B dead.
    $RegexInit = "$SublimeDir\Data\Lib\python38\regex\__init__.py"
    if (Test-Path $RegexInit) {
        _Pass "LaTeXTools 'regex' dependency present (Ctrl+B build enabled)"
    } else {
        _Fail "LaTeXTools 'regex' dependency missing ($RegexInit); LaTeXTools won't load and Ctrl+B does nothing"
    }

    Write-Host ""

    # 5e. File associations.
    Write-Host "File associations:" -ForegroundColor Cyan
    foreach ($Ext in @(".tex", ".pdf")) {
        $Reg = "HKCU:\Software\Classes\$Ext"
        if (Test-Path $Reg) {
            $ProgID = (Get-ItemProperty -Path $Reg -Name "(default)" -ErrorAction SilentlyContinue)."(default)"
            if ($ProgID -like "TeXLib.*") {
                _Pass "$Ext -> $ProgID"
            } elseif ($ProgID -like "OneTeX.*") {
                _Warn "$Ext -> $ProgID (legacy OneTeX association; re-run installer to refresh)"
            } else {
                _Warn "$Ext -> $ProgID (not a TeXLib association; another app owns this extension)"
            }
        } else {
            _Warn "$Ext has no HKCU association; Right Click -> Open With to set defaults"
        }
    }

    # Leftovers from earlier installs. Each of these is a duplicate row in the
    # "Open with" dialog pointing at an exe that is no longer there -- harmless
    # to the build, baffling to the user. Section 17 clears them on every
    # install, so finding any here means this machine has not been re-installed
    # since 0.6.3.
    $StaleApps = @()
    $AppsKey = "HKCU:\Software\Classes\Applications"
    if (Test-Path $AppsKey) {
        foreach ($App in @(Get-ChildItem $AppsKey -ErrorAction SilentlyContinue)) {
            if ($App.PSChildName -notlike "sublime_text.exe" -and $App.PSChildName -notlike "SumatraPDF*.exe") { continue }
            if (-not (Test-ShellCommandLive "$($App.PSPath)\shell\open\command")) { $StaleApps += $App.PSChildName }
        }
    }
    foreach ($ID in @("TeXLib.SublimeFile", "TeXLib.SumatraPDF", "OneTeX.SublimeFile", "OneTeX.SumatraPDF")) {
        if ((Test-Path "HKCU:\Software\Classes\$ID") -and
            -not (Test-ShellCommandLive "HKCU:\Software\Classes\$ID\shell\open\command")) {
            $StaleApps += $ID
        }
    }
    if ($StaleApps.Count -eq 0) {
        _Pass "No stale 'Open with' registrations"
    } else {
        _Warn "Stale 'Open with' registrations pointing at missing executables: $($StaleApps -join ', '). Re-run the installer to clear them."
    }
    Write-Host ""

    # Summary.
    Write-Host "Summary: $script:DoctorOK OK, $script:DoctorWarn warnings, $script:DoctorFail failures." -ForegroundColor Cyan
    Write-Host ""
    if ($script:DoctorFail -gt 0) {
        Write-Host "If everything in the failed checks should be present, your install is broken." -ForegroundColor Yellow
        Write-Host "Re-running install.bat will repair most issues." -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "Your install looks healthy." -ForegroundColor Green
        Write-Host ""
    }
    Write-Host "If you're still seeing problems, paste this entire output into an issue at" -ForegroundColor Gray
    Write-Host "  $InstallerRepo/issues" -ForegroundColor Gray
    Write-Host ""
    # Exit non-zero when any check failed, so -Doctor works as a scriptable
    # health gate (CI / automation), not just a human-readable report.
    if ($script:DoctorFail -gt 0) { Stop-Installer 1 } else { Stop-Installer 0 }
}


# =============================================================================
# 5b. DOWNLOAD VERIFICATION MODE (-VerifyDownloads)
# =============================================================================
function Invoke-VerifyDownloads {
    # Hash-rot canary: download each pinned non-Skip component to a private
    # scratch dir and verify its hash with the SAME algorithm/expected-hash
    # rules as Get-SourceFile -- without touching the install root, PATH,
    # registry, junction, or needing the texlib bundle.
    #   exit 0  = every STATIC pin matched (and nothing was inconclusive-bad)
    #   exit 20 = a STATIC pinned hash DRIFTED (vendor repackaged; re-pin)
    # Inconclusive (reported [WARN], does NOT fail): a component we couldn't
    # download (mirror outage), OR the Dynamic/rolling texlive component whose
    # freshly-fetched hash and zip disagree (a redirector mirror skew/race, not
    # a re-pinnable repackage). The canary's job is catching drift of the STATIC
    # pins, not mirror availability/consistency, so a daily job won't cry wolf.
    # Fetches retry a few times first.
    $ProgressPreference = "SilentlyContinue"   # WinPS 5.1 progress bar tanks download speed
    Show-Banner
    Write-Host "Verifying pinned component downloads..." -ForegroundColor Cyan
    Write-Host ""
    $ScratchDir = Join-Path $env:TEMP "TeXLib_Verify"
    if (Test-Path $ScratchDir) { Remove-Item $ScratchDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null

    $drift = 0        # STATIC pin mismatch -> re-pin needed
    $unverified = 0   # couldn't fetch, or rolling-file mirror skew -> not drift
    foreach ($Key in $Downloads.Keys) {
        $Info = $Downloads[$Key]
        if ($Info.Type -eq "Skip") {
            Write-Host "  [skip] $($Info.File) (rolling/unhashed by design)" -ForegroundColor Gray
            continue
        }
        # Algorithm + expected-hash resolution mirror Get-SourceFile exactly.
        $Algo = if ($Key -eq "texlive") { "SHA512" } else { "SHA256" }
        $ExpectedHash = $null
        $SrcUrl = $Info.Url
        if ($Info.Type -eq "Static") {
            $ExpectedHash = $Info.Hash
        } elseif ($Info.Type -eq "Dynamic") {
            # Rolling file behind a redirector: resolve ONE concrete mirror and
            # read both the hash and (below) the zip from it, so a redirector
            # re-roll can't pair version N's hash with version N-1's zip.
            try {
                $SrcUrl = (Invoke-WebRequest -Uri $Info.Url -Method Head -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30).BaseResponse.ResponseUri.AbsoluteUri
            } catch { $SrcUrl = $Info.Url }
            $HashUri = if ($SrcUrl -ne $Info.Url) { $SrcUrl + ".sha512" } else { $Info.HashUrl }
            $HashContent = $null
            for ($a = 1; $a -le 3 -and -not $HashContent; $a++) {
                try { $HashContent = (Invoke-WebRequest -Uri $HashUri -UseBasicParsing -TimeoutSec 30).Content }
                catch { if ($a -lt 3) { Start-Sleep -Seconds (5 * $a) } }
            }
            if (-not $HashContent) {
                Write-Host "  [WARN] $($Info.File): could not fetch hash after retries (network, not drift)" -ForegroundColor Yellow
                $unverified++; continue
            }
            if ($HashContent -is [byte[]]) { $HashContent = [System.Text.Encoding]::ASCII.GetString($HashContent) }
            $ExpectedHash = ($HashContent -split "\s+")[0].Trim()
        }
        # Download with retry (mirrors Get-SourceFile's Invoke-DownloadWithRetry),
        # from the same resolved mirror as the hash for the Dynamic component.
        $Dest = Join-Path $ScratchDir $Info.File
        $got = $false
        for ($a = 1; $a -le 3 -and -not $got; $a++) {
            try { Invoke-WebRequest -Uri $SrcUrl -OutFile $Dest -UseBasicParsing -TimeoutSec 120; $got = $true }
            catch {
                if ($a -lt 3) { Start-Sleep -Seconds (5 * $a) }
                else { Write-Host "  [WARN] $($Info.File): download failed after retries (network, not drift): $_" -ForegroundColor Yellow }
            }
        }
        if (-not $got) { $unverified++; continue }
        $Actual = (Get-FileHash $Dest -Algorithm $Algo).Hash
        if ($Actual -eq $ExpectedHash) {
            Write-Host "  [PASS] $($Info.File)" -ForegroundColor Green
        } elseif ($Info.Type -eq "Dynamic") {
            # A rolling file whose freshly-fetched hash and zip still disagree is
            # a mirror race, not a re-pinnable vendor repackage -> inconclusive.
            Write-Host "  [WARN] $($Info.File): rolling-file hash mismatch (mirror skew/race, not drift)" -ForegroundColor Yellow
            $unverified++
        } else {
            Write-Host "  [FAIL] $($Info.File)"           -ForegroundColor Red
            Write-Host "         expected: $ExpectedHash"  -ForegroundColor Red
            Write-Host "         actual:   $Actual"        -ForegroundColor Red
            $drift++
        }
    }

    Remove-Item $ScratchDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ""
    if ($drift -gt 0) {
        Write-Host "$drift STATIC pinned component hash(es) drifted. A vendor likely repackaged an artifact; re-pin in `$Downloads." -ForegroundColor Red
        Stop-Installer 20
    }
    if ($unverified -gt 0) {
        Write-Host "No drift in static pins, but $unverified component(s) were inconclusive (mirror outage/skew)." -ForegroundColor Yellow
        Stop-Installer 0
    }
    Write-Host "All pinned component hashes verified." -ForegroundColor Green
    Stop-Installer 0
}


# =============================================================================
# 6. EARLY-DISPATCH (-VerifyDownloads, -Version, -Doctor)
# =============================================================================
if ($VerifyDownloads) { Invoke-VerifyDownloads }
if ($Version) { Show-VersionInfo }
if ($Doctor)  { Invoke-Doctor }

Show-Banner
Write-Host "Log file:     $LogFile" -ForegroundColor Gray
Write-Host "Install path: $BaseDir" -ForegroundColor Gray
Write-Host "Mode:         " -NoNewline -ForegroundColor Gray
if ($DryRun)     { Write-Host "DRY RUN (no changes will be made)" -ForegroundColor Yellow }
elseif ($OnlyTeXLib) { Write-Host "ONLY TEXLIB (skip Sublime/Sumatra/TeX Live)" -ForegroundColor Yellow }
elseif ($Silent) { Write-Host "Silent" -ForegroundColor Gray }
else             { Write-Host "Interactive" -ForegroundColor Gray }
Write-Host "TeXLib library: $TeXLibDir" -ForegroundColor Gray
if ($Sandbox) {
    Write-Host "Sandbox:      ON -- no user PATH entry, no HKCU file associations, no shortcuts" -ForegroundColor Yellow
    if (-not $InstallPath -and -not $TeXLibPath) {
        # Sandbox only suppresses the three machine-state writes; the component
        # install and the library deploy still go to their real default
        # locations unless redirected. Say so rather than implying full
        # isolation.
        Write-Host "  [warn] -Sandbox without -InstallPath or -TeXLibPath: components still install to" -ForegroundColor Yellow
        Write-Host "         $BaseDir and the library to $TeXLibDir." -ForegroundColor Yellow
    }
}
Write-Host ""


# =============================================================================
# 7. PRE-FLIGHT CHECKS
# =============================================================================
Write-Host "Running pre-flight checks..." -ForegroundColor Cyan

$PreflightFailed = $false

function Add-PreflightFailure { param([string]$M); Write-Host "  [FAIL] $M" -ForegroundColor Red; $script:PreflightFailed = $true }
function Add-PreflightWarning { param([string]$M); Write-Host "  [WARN] $M" -ForegroundColor Yellow }
function Add-PreflightOK      { param([string]$M); Write-Host "  [ OK ] $M" -ForegroundColor Green }
function Add-PreflightNote    { param([string]$M); Write-Host "         $M" -ForegroundColor Gray }

function Get-TeXLibVersion {
    # Read the top [x.y.z] heading from a TeXLib library's CHANGELOG.md.
    # Returns "0.6.0" (raw, no leading v) or $null when unknown/Unreleased/absent.
    param([string]$LibDir)
    $ChangelogPath = Join-Path $LibDir "CHANGELOG.md"
    if (-not (Test-Path $ChangelogPath)) { return $null }
    # First concrete version heading, skipping a leading [Unreleased] section --
    # a live/dev copy (the common reuse case) keeps [Unreleased] at the top.
    $Line = Get-Content $ChangelogPath |
        Select-String -Pattern '^## \[(?<ver>[^\]]+)\]' |
        Where-Object { $_.Matches[0].Groups['ver'].Value -ne 'Unreleased' } |
        Select-Object -First 1
    if ($Line) { return $Line.Matches[0].Groups['ver'].Value }
    return $null
}

# 7a. Windows version (need Windows 10 1809 / build 17763 or newer).
$WinBuild = [System.Environment]::OSVersion.Version.Build
if ($WinBuild -ge 17763) { Add-PreflightOK "Windows build $WinBuild (>= 17763 required)" }
else                     { Add-PreflightFailure "Windows build $WinBuild detected; need 17763 (Windows 10 1809) or newer" }

# 7b. PowerShell version (5.1+).
$PSMajor = $PSVersionTable.PSVersion.Major
$PSMinor = $PSVersionTable.PSVersion.Minor
if ($PSMajor -gt 5 -or ($PSMajor -eq 5 -and $PSMinor -ge 1)) {
    Add-PreflightOK "PowerShell $($PSVersionTable.PSVersion) (>= 5.1 required)"
} else {
    Add-PreflightFailure "PowerShell $($PSVersionTable.PSVersion) detected; need 5.1 or newer"
}

# 7c. Disk space -- skip the 6GB check in -OnlyTeXLib mode (bundle is tiny).
try {
    $Drive = (Get-Item (Split-Path $BaseDir -Qualifier)).PSDrive
    $FreeGB = [math]::Round($Drive.Free / 1GB, 1)
    $Need = if ($OnlyTeXLib) { 0.2 } else { 6 }
    if ($FreeGB -ge $Need) {
        Add-PreflightOK "Free space on $($Drive.Name): ${FreeGB} GB (>= ${Need} GB required)"
    } else {
        Add-PreflightFailure "Only ${FreeGB} GB free on $($Drive.Name); need >= ${Need} GB"
    }
} catch {
    Add-PreflightWarning "Could not determine free disk space; continuing"
}

# 7d. Internet connectivity (skip in -OnlyTeXLib if no downloads needed).
# HEAD request against the CTAN mirror -- confirms TLS reachability without
# pulling any payload. Test-NetConnection would also work but trips
# PSScriptAnalyzer's "hardcoded ComputerName" rule (false positive for a
# public mirror).
if (-not $OnlyTeXLib) {
    # Retry with a longer timeout: mirror.ctan.org is a redirector to regional
    # mirrors and can be briefly slow even when the connection is fine, so a
    # single 5s HEAD was flaky and would hard-fail the whole pre-flight.
    $reachable = $false
    $netErr = $null
    for ($a = 1; $a -le 3 -and -not $reachable; $a++) {
        try {
            $null = Invoke-WebRequest -Uri "https://mirror.ctan.org/" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $reachable = $true
        } catch { $netErr = $_; if ($a -lt 3) { Start-Sleep -Seconds (2 * $a) } }
    }
    if ($reachable) {
        Add-PreflightOK "Internet connectivity to mirror.ctan.org (HTTPS)"
    } else {
        Add-PreflightFailure "Cannot reach https://mirror.ctan.org/ after 3 tries ($($netErr.Exception.Message)); check your internet connection / firewall / VPN"
    }
} else {
    Add-PreflightOK "Skipping internet check (-OnlyTeXLib doesn't download anything)"
}

# 7e. Detect existing TeX Live (or our own prior install).
$OurTex = Get-Command pdflatex -ErrorAction SilentlyContinue
if ($OurTex -and ($OurTex.Source -like "$BaseDir*")) {
    Add-PreflightOK "Existing TeXLib install detected at $($OurTex.Source) (Skip/Reinstall prompt below)"
} else {
    Add-PreflightOK "Will install an isolated TeX Live 2025 under $BaseDir"
}

# 7f. Sublime Text: always an isolated portable copy.
Add-PreflightOK "Installing an isolated portable Sublime Text under $SublimeDir (any existing Sublime is left untouched; our texlib_builder plugin is scoped to it)"

# 7g. SumatraPDF: always a portable copy.
Add-PreflightOK "Installing a portable SumatraPDF (any existing install is left untouched)"

# 7h. Library location.
if ($ExplicitTeXLibPath) {
    Add-PreflightOK "TeXLib library will live at $TeXLibDir (-TeXLibPath)"
} else {
    Add-PreflightOK "TeXLib library will live at $TeXLibDir (inside the install root, alongside the Sublime plugin)"
}
if ($LegacyTeXLibDir) {
    Add-PreflightNote "(found a pre-0.6.3 library at $LegacyTeXLibDir; your Sublime settings carry over, and that folder is left in place for you to delete)"
}
if ($UnfixableTeXLibPath) {
    Add-PreflightWarning "$TeXLibDir contains a space or comma, and $UserRootJunction cannot serve as a clean alias because it has one too. kpathsea may fail to resolve the library; pass -InstallPath with a path free of spaces and commas."
}
if ($NeedsUserRootJunction) {
    switch ($UserRootJunctionState) {
        "present"     { Add-PreflightNote "(using existing junction $UserRootJunction so TeX can resolve the space/comma-bearing library path)" }
        "will-create" { Add-PreflightNote "(will create junction $UserRootJunction so TeX can resolve the space/comma-bearing library path)" }
        "blocked"     { Add-PreflightFailure "$UserRootJunction exists as a real folder, not a junction. Move or rename it and re-run." }
    }
}

# 7i. TeXLib library source. Mirrors how we treat Sublime / Sumatra / TeX Live:
# detect an existing install and reuse it, else deploy our own copy. Three valid
# sources, in priority order:
#   1. bundled snapshot (texlib\, shipped in the release zip) -- deploy it
#   2. a library already at the install location -- reuse it in place
#   3. a pre-0.6.3 library in Documents / OneDrive -- migrate it across
# -OnlyTeXLib exists to PUSH a newer bundle, so it still requires a bundle.
$HaveBundle = Test-Path $TexLibBundle

# An existing library counts only if the core .sty files are actually present.
# We check the physical target ($UserRootJunctionTarget), which is where content
# really lives regardless of whether the TEXINPUTS-safe junction exists yet.
$HaveExistingLibrary = Test-TeXLibLibraryDir $UserRootJunctionTarget

$UseExistingTeXLib = $false
$MigrateFromLegacy = $false

if ($HaveBundle) {
    Add-PreflightOK "TeXLib bundle found at $TexLibBundle"
} elseif ($HaveExistingLibrary -and -not $OnlyTeXLib) {
    # No bundle in this installer copy (e.g. running from a source checkout, or
    # a copy synced without its dist\ folder), but this machine already has the
    # library where we want it. Reuse it, exactly like a detected TeX
    # distribution -- no bundle needed, and no deploy copy in section 13.
    $UseExistingTeXLib = $true
    $ExistingVer = Get-TeXLibVersion $UserRootJunctionTarget
    $VerNote = if ($ExistingVer) { " (TeXLib $ExistingVer)" } else { "" }
    Add-PreflightOK "Existing TeXLib library detected at $UserRootJunctionTarget$VerNote; will use it (no bundle needed)"
    Add-PreflightNote "(this installer copy ships no texlib\ bundle; reusing the library already in place, like a detected TeX distribution)"
} elseif ($LegacyTeXLibDir -and -not $OnlyTeXLib) {
    # No bundle and nothing at the new location, but this machine has a
    # pre-0.6.3 library sitting in Documents / OneDrive. Copy it across rather
    # than failing: for a returning user with a source checkout of the
    # installer, their existing library IS the only available source.
    $MigrateFromLegacy = $true
    $ExistingVer = Get-TeXLibVersion $LegacyTeXLibDir
    $VerNote = if ($ExistingVer) { " (TeXLib $ExistingVer)" } else { "" }
    Add-PreflightOK "Pre-0.6.3 TeXLib library detected at $LegacyTeXLibDir$VerNote; will copy it to $UserRootJunctionTarget"
    Add-PreflightNote "(the original is left untouched -- delete it yourself once you have confirmed the new install works)"
} else {
    # Neither a bundle nor an existing library: nothing to install from. The #1
    # cause is grabbing the source tree ("Code -> Download ZIP", or the release
    # page's "Source code (zip)") instead of a release asset. Detect that (the
    # source tree carries tools\make-release.ps1, .github\, or .git\, none of
    # which ride in a release zip) and say so plainly.
    $looksLikeSource = (Test-Path (Join-Path $ScriptDir "tools\make-release.ps1")) -or
                       (Test-Path (Join-Path $ScriptDir ".github")) -or
                       (Test-Path (Join-Path $ScriptDir ".git"))
    if ($OnlyTeXLib) {
        Add-PreflightFailure "-OnlyTeXLib refreshes the library FROM a bundled texlib\ snapshot, but none is present next to install.ps1. Use a release zip (it contains texlib\), or run a normal install without -OnlyTeXLib to reuse an already-synced library."
    } elseif ($looksLikeSource) {
        Add-PreflightFailure "TeXLib bundle is missing because this is the GitHub SOURCE download, which does not include the TeXLib library, and no existing TeXLib library was found at $UserRootJunctionTarget to reuse. Do NOT use 'Code -> Download ZIP' or the release page's 'Source code (zip)'. Download the release zip (TeXLib-Installer-v<version>.zip) from $InstallerRepo/releases, extract it, and run install.bat from inside THAT folder."
    } else {
        Add-PreflightFailure "TeXLib bundle not found at $TexLibBundle and no existing TeXLib library found at $UserRootJunctionTarget; the download looks incomplete. Re-download the release zip from $InstallerRepo/releases, extract it fully, and run install.bat from the extracted folder."
    }
}

if ($PreflightFailed) {
    Write-Host ""
    Write-Host "Pre-flight checks failed. Fix the issues above and re-run." -ForegroundColor Red
    Stop-Installer 1
}

Write-Host ""


# =============================================================================
# 8. UPDATE CHECK (after pre-flight so we know internet is up)
# =============================================================================
if (-not $OnlyTeXLib) {
    Test-LatestVersion
}


# =============================================================================
# 9. DRY-RUN: print plan and exit
# =============================================================================
if ($DryRun) {
    Write-Host "DRY RUN -- would do:" -ForegroundColor Yellow
    if ($NeedsUserRootJunction) {
        if ($UserRootJunctionState -eq "present") {
            Write-Host "  * Reuse existing user-root junction $UserRootJunction -> $UserRootJunctionTarget" -ForegroundColor Gray
        } elseif ($UserRootJunctionState -eq "blocked") {
            Write-Host "  * ABORT: $UserRootJunction exists but is not a junction (would block install)" -ForegroundColor Yellow
        } else {
            Write-Host "  * Create user-root junction $UserRootJunction -> $UserRootJunctionTarget (TEXINPUTS-safe path)" -ForegroundColor Gray
        }
    }
    $TeXLibPlan = if ($UseExistingTeXLib) {
        "Reuse existing TeXLib library at $TeXLibDir (no bundle to deploy)"
    } elseif ($MigrateFromLegacy) {
        "Copy the pre-0.6.3 TeXLib library from $LegacyTeXLibDir to $TeXLibDir (original left in place)"
    } else {
        "Deploy TeXLib bundle from $TexLibBundle to $TeXLibDir"
    }
    if ($LegacyTeXLibDir -and -not $MigrateFromLegacy) {
        Write-Host "  * Carry Sublime settings over from $LegacyTeXLibDir\Sublime (original left in place)" -ForegroundColor Gray
    }
    if ($StaleUserRootJunction) {
        Write-Host "  * Retire the leftover user-root junction $StaleUserRootJunction (target preserved)" -ForegroundColor Gray
    }
    if ($OnlyTeXLib) {
        Write-Host "  * $TeXLibPlan" -ForegroundColor Gray
        Write-Host "  * Refresh texlib_builder.py + TeXLib.sublime-build in Packages\User" -ForegroundColor Gray
        Write-Host "  * Write $BaseDir\VERSION" -ForegroundColor Gray
    } else {
        Write-Host "  * Install Sublime Text to $SublimeDir" -ForegroundColor Gray
        Write-Host "  * Install SumatraPDF to $SumatraDir"   -ForegroundColor Gray
        Write-Host "  * Install TeX Live to $TexLiveDir (30-60 min)" -ForegroundColor Gray
        Write-Host "  * $TeXLibPlan" -ForegroundColor Gray
        if ($Sandbox) {
            Write-Host "  * SKIP (sandbox): user PATH entry" -ForegroundColor DarkGray
        } else {
            Write-Host "  * Add $TexBinPath to user PATH" -ForegroundColor Gray
        }
        Write-Host "  * Junction $SublimeDir\Data\Packages\User -> $SublimeUserSync" -ForegroundColor Gray
        Write-Host "  * Write LaTeXTools / Preferences / SumatraPDF settings" -ForegroundColor Gray
        if ($Sandbox) {
            Write-Host "  * SKIP (sandbox): .tex .cls .sty .bib .pdf file associations (HKCU)" -ForegroundColor DarkGray
            Write-Host "  * SKIP (sandbox): Desktop + Start Menu shortcuts" -ForegroundColor DarkGray
        } else {
            Write-Host "  * Register .tex .cls .sty .bib .pdf file associations (HKCU)" -ForegroundColor Gray
            Write-Host "  * Create Desktop + Start Menu shortcuts" -ForegroundColor Gray
        }
        Write-Host "  * Compile a verification document" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "No changes made. Re-run without -DryRun to install." -ForegroundColor Yellow
    Stop-Installer 0
}


# =============================================================================
# 10. HELPER FUNCTIONS (install-mode only)
# =============================================================================
function Invoke-DownloadWithRetry {
    # Download $Uri to $OutFile, retrying transient failures with backoff.
    # University Wi-Fi blips on a multi-hundred-MB TeX Live download otherwise
    # hard-fail the whole install with no recourse but a from-scratch re-run.
    param([string]$Uri, [string]$OutFile, [int]$Retries = 3)
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
            return
        } catch {
            if ($attempt -ge $Retries) {
                throw "Download failed after $Retries attempt(s): $Uri`n$_"
            }
            $wait = 5 * $attempt
            Write-Host "  [retry] download attempt $attempt failed; retrying in $wait s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $wait
        }
    }
}

function Get-SourceFile {
    param ($Key, $DestPath)
    $Info = $Downloads[$Key]
    $LocalPath = "$ScriptDir\$($Info.File)"
    $ExpectedHash = $null
    $ResolvedUrl  = $null

    if ($Info.Type -eq "Static") {
        $ExpectedHash = $Info.Hash
    } elseif ($Info.Type -eq "Dynamic") {
        Write-Host "Fetching latest hash for $($Info.File)..." -ForegroundColor Cyan
        # install-tl.zip is a ROLLING file and mirror.ctan.org is a redirector,
        # so fetching the .zip and its .sha512 in separate requests can land on
        # two out-of-sync mirrors -> a false hash mismatch that aborts the whole
        # install. Resolve ONE concrete mirror up front and pull both the hash
        # (here) and the zip (below) from it. Best-effort: if resolution fails,
        # fall back to the redirector URLs (original behaviour, no regression).
        try {
            $ResolvedUrl = (Invoke-WebRequest -Uri $Info.Url -Method Head -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30).BaseResponse.ResponseUri.AbsoluteUri
        } catch { $ResolvedUrl = $null }
        $HashUri = if ($ResolvedUrl) { $ResolvedUrl + ".sha512" } else { $Info.HashUrl }
        try {
            $HashContent = (Invoke-WebRequest -Uri $HashUri -UseBasicParsing -TimeoutSec 30).Content
            # Some CTAN mirrors serve the .sha512 with Content-Type application/zip,
            # so Invoke-WebRequest hands back a byte[] instead of a string; decode
            # it before splitting or the "expected hash" becomes garbage ("50"...).
            if ($HashContent -is [byte[]]) { $HashContent = [System.Text.Encoding]::ASCII.GetString($HashContent) }
            $ExpectedHash = ($HashContent -split "\s+")[0].Trim()
        } catch {
            Write-Host "  [FAIL] Could not fetch hash for $($Info.File): $_" -ForegroundColor Red
            throw "Hash fetch failed (no fallback for dynamic-hash component)."
        }
    }

    $Algo = if ($Key -eq "texlive") { "SHA512" } else { "SHA256" }

    if (Test-Path $LocalPath) {
        Write-Host "Found pre-staged file: $($Info.File)" -ForegroundColor Cyan
        if ($Info.Type -ne "Skip") {
            $CurrentHash = (Get-FileHash $LocalPath -Algorithm $Algo).Hash
            if ($CurrentHash -eq $ExpectedHash) {
                Write-Host "  [OK] Hash verified" -ForegroundColor Green
                Copy-Item $LocalPath $DestPath
                return
            } else {
                Write-Host "  [WARN] Hash mismatch on pre-staged copy; downloading fresh" -ForegroundColor Yellow
            }
        } else {
            Copy-Item $LocalPath $DestPath
            return
        }
    }

    Write-Host "Downloading $($Info.File)..." -ForegroundColor Yellow
    # For the Dynamic component, download from the SAME concrete mirror the hash
    # was read from (resolved above) so a redirector re-roll can't hand us a
    # different rolling build than the one we just hashed.
    $DownloadUri = if ($ResolvedUrl) { $ResolvedUrl } else { $Info.Url }
    Invoke-DownloadWithRetry -Uri $DownloadUri -OutFile $DestPath

    if ($Info.Type -ne "Skip" -and $ExpectedHash) {
        $NewHash = (Get-FileHash $DestPath -Algorithm $Algo).Hash
        # A rolling Dynamic component (texlive) can mismatch because the zip and
        # its .sha512 came from mirrors at slightly different sync states. Re-roll
        # the redirector to a fresh concrete mirror and re-pull both, a few times,
        # before giving up, so a transient skew self-heals instead of aborting a
        # perfectly good install. (A Static pin never retries: a mismatch there is
        # real drift to be re-pinned.)
        $tries = 0
        while ($NewHash -ne $ExpectedHash -and $Info.Type -eq "Dynamic" -and $tries -lt 3) {
            $tries++
            Write-Host "  [retry] $($Info.File) hash mismatch (likely CTAN mirror skew); re-resolving mirror (attempt $tries)..." -ForegroundColor Yellow
            Start-Sleep -Seconds (3 * $tries)
            try {
                $ResolvedUrl = (Invoke-WebRequest -Uri $Info.Url -Method Head -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30).BaseResponse.ResponseUri.AbsoluteUri
            } catch { $ResolvedUrl = $null }
            $RetryHashUri = if ($ResolvedUrl) { $ResolvedUrl + ".sha512" } else { $Info.HashUrl }
            try {
                $rc = (Invoke-WebRequest -Uri $RetryHashUri -UseBasicParsing -TimeoutSec 30).Content
                if ($rc -is [byte[]]) { $rc = [System.Text.Encoding]::ASCII.GetString($rc) }
                $ExpectedHash = ($rc -split "\s+")[0].Trim()
            } catch { continue }
            $RetryDownloadUri = if ($ResolvedUrl) { $ResolvedUrl } else { $Info.Url }
            Invoke-DownloadWithRetry -Uri $RetryDownloadUri -OutFile $DestPath
            $NewHash = (Get-FileHash $DestPath -Algorithm $Algo).Hash
        }
        if ($NewHash -ne $ExpectedHash) {
            Write-Host "  [FAIL] Hash mismatch for $($Info.File)" -ForegroundColor Red
            Write-Host "         expected: $ExpectedHash" -ForegroundColor Red
            Write-Host "         actual:   $NewHash"      -ForegroundColor Red
            throw "Hash mismatch on $($Info.File); aborting install to avoid running unverified bytes."
        }
        Write-Host "  [OK] Hash verified" -ForegroundColor Green
    }
}

function Read-SkipOrReinstall {
    param ([string]$ComponentName, [string]$ReinstallNote = "")
    if ($Silent) {
        Write-Host "  [silent] Skipping reinstall of $ComponentName" -ForegroundColor Gray
        return $false
    }
    $msg = "  [S]kip or [R]einstall"
    if ($ReinstallNote) { $msg += " ($ReinstallNote)" }
    $msg += "? (Default: S)"
    $Choice = Read-Host $msg
    return ($Choice -eq "R" -or $Choice -eq "r")
}

function Backup-SublimeSettings {
    # ZIP $SublimeUserSync (the user's settings folder) to a timestamped archive
    # before any destructive operation. Cheap insurance against accidental
    # wipes. Returns the path of the backup ZIP, or $null if nothing to back up.
    if (-not (Test-Path $SublimeUserSync)) { return $null }
    if (-not (Test-Path $LogDir))          { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    $BackupZip = "$LogDir\sublime-user-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
    try {
        Compress-Archive -Path "$SublimeUserSync\*" -DestinationPath $BackupZip -CompressionLevel Fastest -ErrorAction Stop
        Write-Host "  Backed up Sublime user settings to $BackupZip" -ForegroundColor Gray
        return $BackupZip
    } catch {
        Write-Host "  [warn] Sublime settings backup failed: $_ (continuing)" -ForegroundColor Yellow
        return $null
    }
}

function Wait-WithHeartbeat {
    # Block until $Process exits, printing one heartbeat line every $IntervalSec
    # seconds so the user knows it's still running.
    param(
        [Parameter(Mandatory=$true)]$Process,
        [int]$IntervalSec = 30,
        [string]$Label = "working"
    )
    $start = Get-Date
    while (-not $Process.HasExited) {
        Start-Sleep -Seconds $IntervalSec
        if (-not $Process.HasExited) {
            $elapsed = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
            Write-Host "  [$Label] still going... $elapsed min elapsed" -ForegroundColor Gray
        }
    }
    $elapsed = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
    Write-Host "  [$Label] finished after $elapsed min" -ForegroundColor Gray
}


# =============================================================================
# 11. PREPARE DIRECTORIES
# =============================================================================
Write-Host "Setting up TeXLib..." -ForegroundColor Cyan

try {
    foreach ($d in @($BaseDir, $TempDir, $ScriptsDir, $LogDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    if (-not (Test-Path $TeXLibDir)) {
        Write-Host "Creating the TeXLib library folder at $TeXLibDir..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $TeXLibDir | Out-Null
    }

    # Stash the installer scripts so the user can re-run / uninstall / doctor
    # later. They are siblings of THIS file in tools\, not of $ScriptDir.
    Copy-Item "$PSScriptRoot\install.ps1" "$ScriptsDir\install.ps1" -Force
    if (Test-Path "$PSScriptRoot\uninstall.ps1") {
        Copy-Item "$PSScriptRoot\uninstall.ps1" "$ScriptsDir\uninstall.ps1" -Force
    }
} catch {
    Write-Host "Failed to prepare directories: $_" -ForegroundColor Red
    Stop-Installer 2
}

# Backup whatever's already in TeXLib\Sublime before we touch anything.
Backup-SublimeSettings | Out-Null


# =============================================================================
# 11b. MIGRATE A PRE-0.6.3 LIBRARY LOCATION
# =============================================================================
# Through 0.6.2 the library -- and with it Packages\User, meaning every Sublime
# setting the user ever changed -- lived in Documents / OneDrive. Now that it
# lives in the install root, an upgrade has to carry those settings across or
# the user silently loses their keymaps, snippets, and spell-check word lists.
#
# Two shapes, both non-destructive; the old folder is never deleted or edited:
#   * $MigrateFromLegacy -- no bundle and nothing at the new location, so the
#     old library IS the only install source. Copy the whole tree.
#   * otherwise -- a bundle (or a library already in place) supplies the
#     library, so only the user-owned Sublime\ settings come across, and only
#     when the destination has none yet. Section 13 then lays the current
#     builder files on top of them.
if ($LegacyTeXLibDir) {
    Write-Host ""
    try {
        if ($MigrateFromLegacy) {
            Write-Host "Migrating TeXLib library from $LegacyTeXLibDir..." -ForegroundColor Cyan
            Copy-Item "$LegacyTeXLibDir\*" $TeXLibDir -Recurse -Force -Exclude ".git", ".github"
            Write-Host "  Copied to $TeXLibDir" -ForegroundColor Green
        } elseif (-not (Test-Path $SublimeUserSync)) {
            $LegacySublime = Join-Path $LegacyTeXLibDir "Sublime"
            if (Test-Path $LegacySublime) {
                Write-Host "Carrying Sublime settings over from $LegacySublime..." -ForegroundColor Cyan
                New-Item -ItemType Directory -Force -Path $SublimeUserSync | Out-Null
                Copy-Item "$LegacySublime\*" $SublimeUserSync -Recurse -Force
                Write-Host "  Settings copied to $SublimeUserSync" -ForegroundColor Green
            }
        }
    } catch {
        # Non-fatal by design. A fresh library is still a working install, and
        # aborting here would strand a mid-upgrade user with nothing to run.
        Write-Host "  [WARN] Could not migrate from $LegacyTeXLibDir : $_" -ForegroundColor Yellow
        Write-Host "  [WARN] Your old library is untouched; copy anything you need across by hand." -ForegroundColor Yellow
    }
    Write-Host "  Your previous library is still at $LegacyTeXLibDir -- nothing there was" -ForegroundColor Gray
    Write-Host "  modified. Delete it yourself once the new install checks out." -ForegroundColor Gray
}

# Retire the user-root junction a pre-0.6.3 install created for the old
# location. Directory::Delete(path, $false) removes the link entry only and
# never follows it into the target, so whatever it pointed at is untouched.
if ($StaleUserRootJunction) {
    Write-Host ""
    Write-Host "Retiring the leftover user-root junction $StaleUserRootJunction..." -ForegroundColor Cyan
    try {
        [System.IO.Directory]::Delete($StaleUserRootJunction, $false)
        Write-Host "  Removed (its target was not touched)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Could not remove $StaleUserRootJunction : $_" -ForegroundColor Yellow
    }
}


# =============================================================================
# 12. INSTALL PROGRAMS (skipped in -OnlyTeXLib)
# =============================================================================
if (-not $OnlyTeXLib) {

    # ---- Sublime Text ----
    $InstallSublime = $true
    if (Test-Path $SublimeDir) {
        Write-Host ""
        Write-Host "Sublime Text is already installed." -ForegroundColor Yellow
        # Note: re-install wipes Sublime\Data\Packages\LaTeXTools + Installed
        # Packages, but the user's actual settings (in TeXLib\Sublime via the
        # junction) are preserved.
        if (Read-SkipOrReinstall -ComponentName "Sublime Text" -ReinstallNote "preserves your settings via the TeXLib junction; only re-fetches the binary + LaTeXTools") {
            Write-Host "  Removing old version..." -ForegroundColor Red
            Remove-Item $SublimeDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $InstallSublime = $false
            Write-Host "  Skipping Sublime Text" -ForegroundColor Green
        }
    }

    if ($InstallSublime) {
        try {
            $ZipPath = "$TempDir\sublime.zip"
            Get-SourceFile -Key "sublime" -DestPath $ZipPath
            Expand-Archive -Path $ZipPath -DestinationPath $SublimeDir

            $InstalledPkgsDir = "$SublimeDir\Data\Installed Packages"
            New-Item -ItemType Directory -Force -Path $InstalledPkgsDir | Out-Null
            Get-SourceFile -Key "pkgctrl" -DestPath "$InstalledPkgsDir\Package Control.sublime-package"
        } catch {
            Write-Host "Sublime Text install failed: $_" -ForegroundColor Red
            Stop-Installer 3
        }
    }

    # ---- SumatraPDF ----
    $InstallSumatra = $true
    if (Test-Path $SumatraDir) {
        Write-Host ""
        Write-Host "SumatraPDF is already installed." -ForegroundColor Yellow
        if (Read-SkipOrReinstall -ComponentName "SumatraPDF") {
            Remove-Item $SumatraDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $InstallSumatra = $false
            Write-Host "  Skipping SumatraPDF" -ForegroundColor Green
        }
    }

    if ($InstallSumatra) {
        try {
            $ZipPath = "$TempDir\sumatra.zip"
            Get-SourceFile -Key "sumatra" -DestPath $ZipPath
            Expand-Archive -Path $ZipPath -DestinationPath $SumatraDir
        } catch {
            Write-Host "SumatraPDF install failed: $_" -ForegroundColor Red
            Stop-Installer 4
        }
    }

    # ---- TeX Live ----
    $InstallTeX = $true
    if (Test-Path "$TexLiveDir\bin\windows") {
        Write-Host ""
        Write-Host "TeX Live is already installed." -ForegroundColor Yellow
        if (Read-SkipOrReinstall -ComponentName "TeX Live" -ReinstallNote "takes 30+ minutes") {
            Remove-Item "$BaseDir\TexLive" -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $InstallTeX = $false
            Write-Host "  Skipping TeX Live" -ForegroundColor Green
        }
    }

    if ($InstallTeX) {
        try {
            $ZipPath = "$TempDir\install-tl.zip"
            Get-SourceFile -Key "texlive" -DestPath $ZipPath
            Expand-Archive -Path $ZipPath -DestinationPath "$TempDir\texlive_installer"
            $InstallerRoot = Get-ChildItem "$TempDir\texlive_installer\install-tl-*" | Select-Object -ExpandProperty FullName

            $TexDirFwd          = $BaseDir.Replace("\", "/") + "/TexLive/$TexLiveYear"
            $TexMfLocalFwd      = $BaseDir.Replace("\", "/") + "/TexLive/texmf-local"
            $TexMfSysConfigFwd  = $BaseDir.Replace("\", "/") + "/TexLive/$TexLiveYear/texmf-config"
            $TexMfSysVarFwd     = $BaseDir.Replace("\", "/") + "/TexLive/$TexLiveYear/texmf-var"

            $ProfileContent = @"
selected_scheme scheme-full
TEXDIR $TexDirFwd
TEXMFLOCAL $TexMfLocalFwd
TEXMFSYSCONFIG $TexMfSysConfigFwd
TEXMFSYSVAR $TexMfSysVarFwd
portable 1
option_doc 0
option_src 0
"@
            Set-Content -Path "$InstallerRoot\texlive.profile" -Value $ProfileContent -Encoding ASCII

            Write-Host "STARTING TEX LIVE INSTALL (30-60 mins; grab a coffee)..." -ForegroundColor Cyan
            $TLProc = Start-Process -FilePath "$InstallerRoot\install-tl-windows.bat" `
                -ArgumentList "-no-gui -profile texlive.profile" `
                -WorkingDirectory $InstallerRoot -PassThru
            Wait-WithHeartbeat -Process $TLProc -IntervalSec 30 -Label "TeX Live"
            # Don't trust "it finished" -- verify install-tl actually succeeded.
            # Without this, a dropped connection mid-install reports success and
            # the broken tree is only caught (as a non-fatal WARN) much later.
            if ($TLProc.ExitCode -ne 0) {
                throw "install-tl exited with code $($TLProc.ExitCode); TeX Live did not install cleanly."
            }
            if (-not (Test-Path "$TexBinPath\pdflatex.exe")) {
                throw "install-tl finished but pdflatex.exe is missing at $TexBinPath."
            }
        } catch {
            Write-Host "TeX Live install failed: $_" -ForegroundColor Red
            Stop-Installer 5
        }
    }
}


# =============================================================================
# 13. DEPLOY TEXLIB BUNDLE TO ONEDRIVE / DOCUMENTS
# =============================================================================
Write-Host ""
if ($UseExistingTeXLib) {
    Write-Host "Using existing TeXLib library at $TeXLibDir (no bundle to deploy)." -ForegroundColor Cyan
} elseif ($MigrateFromLegacy) {
    Write-Host "TeXLib library already in place at $TeXLibDir (migrated in step 11b)." -ForegroundColor Cyan
} else {
    Write-Host "Deploying TeXLib library..." -ForegroundColor Cyan
    try {
        # Mirror the bundle into the library folder. We don't delete extra files
        # here (a migration may have put the user's settings there ahead of us),
        # only overwrite the library bits.
        Copy-Item "$TexLibBundle\*" $TeXLibDir -Recurse -Force -Exclude ".git", ".github"
        Write-Host "  Library deployed to $TeXLibDir" -ForegroundColor Green
    } catch {
        Write-Host "TeXLib deploy failed: $_" -ForegroundColor Red
        Stop-Installer 7
    }
}


# =============================================================================
# 14. CONFIGURE ENVIRONMENT (skipped in -OnlyTeXLib / -Sandbox)
# =============================================================================
if ($WriteMachineState) {
    Write-Host ""
    Write-Host "Configuring environment..." -ForegroundColor Cyan

    try {
        $CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($CurrentPath -notlike "*$TexBinPath*") {
            $NewPath = if ($CurrentPath) { "$CurrentPath;$TexBinPath" } else { $TexBinPath }
            [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
            Write-Host "  Added $TexBinPath to user PATH" -ForegroundColor Green
        } else {
            Write-Host "  $TexBinPath already on PATH" -ForegroundColor Gray
        }
    } catch {
        Write-Host "PATH update failed: $_" -ForegroundColor Red
        Stop-Installer 8
    }
}


# =============================================================================
# 15. SYNC SUBLIME SETTINGS (skipped in -OnlyTeXLib)
# =============================================================================
if (-not $OnlyTeXLib) {
    Write-Host ""
    Write-Host "Wiring up Sublime settings sync..." -ForegroundColor Cyan

    try {
        $UserPackagesLocal = "$SublimeDir\Data\Packages\User"
        $PackagesDir = "$SublimeDir\Data\Packages"
        if (-not (Test-Path $PackagesDir)) { New-Item -ItemType Directory -Force -Path $PackagesDir | Out-Null }

        # Zombie check: the sync target may exist as a stale junction.
        if (Test-Path $SublimeUserSync) {
            $Item = Get-Item $SublimeUserSync -Force
            if ($Item.Attributes -match "ReparsePoint") {
                Write-Host "  [fix] Removing stale junction at sync target" -ForegroundColor Yellow
                Remove-Item $SublimeUserSync -Force -Recurse
            }
        }

        if (Test-Path $SublimeUserSync) {
            Write-Host "  Found existing TeXLib\Sublime; junctioning Packages\User to it" -ForegroundColor Green
            if (Test-Path $UserPackagesLocal) { Remove-Item $UserPackagesLocal -Recurse -Force }
            New-Item -ItemType Junction -Path $UserPackagesLocal -Target $SublimeUserSync | Out-Null
        } else {
            Write-Host "  Creating new sync folder at $SublimeUserSync" -ForegroundColor Cyan
            if (-not (Test-Path $UserPackagesLocal)) { New-Item -ItemType Directory -Force -Path $UserPackagesLocal | Out-Null }
            # Back up the existing Packages\User BEFORE the destructive move, so a
            # crash between the move and the junction can't lose the user's
            # settings. (Backup-SublimeSettings only covers $SublimeUserSync,
            # which doesn't exist yet on a first install -- this is the gap.)
            $ExistingUserItems = @(Get-ChildItem -Path $UserPackagesLocal -Force -ErrorAction SilentlyContinue)
            if ($ExistingUserItems.Count -gt 0) {
                if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
                $PkgBackup = "$LogDir\packages-user-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
                try {
                    Compress-Archive -Path "$UserPackagesLocal\*" -DestinationPath $PkgBackup -CompressionLevel Fastest -ErrorAction Stop
                    Write-Host "  Backed up existing Packages\User to $PkgBackup" -ForegroundColor Gray
                } catch {
                    Write-Host "  [warn] Packages\User backup failed: $_ (continuing)" -ForegroundColor Yellow
                }
            }
            New-Item -ItemType Directory -Force -Path $SublimeUserSync | Out-Null
            Get-ChildItem -Path $UserPackagesLocal -Force | Move-Item -Destination $SublimeUserSync -Force
            Remove-Item $UserPackagesLocal -Recurse -Force
            New-Item -ItemType Junction -Path $UserPackagesLocal -Target $SublimeUserSync | Out-Null
        }
    } catch {
        Write-Host "Sublime sync setup failed: $_" -ForegroundColor Red
        Stop-Installer 9
    }
}


# =============================================================================
# 16. CONFIGURE PROGRAMS  (always -- -OnlyTeXLib still refreshes builder files)
# =============================================================================
Write-Host ""
Write-Host "Writing program configurations..." -ForegroundColor Cyan

try {
    $UserDir = $SublimeUserSync
    $PackagesDir = "$SublimeDir\Data\Packages"
    $LaTeXToolsDir = "$PackagesDir\LaTeXTools"

    # 16a. Install LaTeXTools (skipped in -OnlyTeXLib if already present).
    if (-not $OnlyTeXLib -and -not (Test-Path $LaTeXToolsDir)) {
        $ZipPath = "$TempDir\latextools.zip"
        Get-SourceFile -Key "latextools" -DestPath $ZipPath
        Expand-Archive -Path $ZipPath -DestinationPath "$TempDir\lt_extract"
        Move-Item -Path "$TempDir\lt_extract\$LaTeXToolsZipDir" -Destination $LaTeXToolsDir
    }

    # 16a-2. Install LaTeXTools' `regex` dependency into Sublime's ST4 library
    # path. Without it LaTeXTools' plugin.py fails to import, latextools_make_pdf
    # never registers, and Ctrl+B does nothing. ST4's plugin host loads libraries
    # from <Data>\Lib\python38. Not gated on the LaTeXTools install above, so a
    # re-run repairs a machine whose regex is missing. Idempotent.
    if (-not $OnlyTeXLib) {
        $SublimeLibDir = "$SublimeDir\Data\Lib\python38"
        $RegexPkgDir   = "$SublimeLibDir\regex"
        if (-not (Test-Path "$RegexPkgDir\__init__.py")) {
            $RegexZip     = "$TempDir\regex.zip"
            $RegexExtract = "$TempDir\regex_extract"
            Get-SourceFile -Key "regex" -DestPath $RegexZip   # a wheel is a zip
            if (Test-Path $RegexExtract) { Remove-Item $RegexExtract -Recurse -Force }
            Expand-Archive -Path $RegexZip -DestinationPath $RegexExtract
            New-Item -ItemType Directory -Force -Path $SublimeLibDir | Out-Null
            if (Test-Path $RegexPkgDir) { Remove-Item $RegexPkgDir -Recurse -Force }
            Move-Item -Path "$RegexExtract\regex" -Destination $RegexPkgDir
            Write-Host "  Installed LaTeXTools dependency 'regex' to $SublimeLibDir" -ForegroundColor Green
        }
    }

    # 16b. Deploy the TeXLib custom builder + bundled spell-check dictionary.
    # Source of truth is the bundle; when reusing an already-synced library (no
    # bundle in this installer copy), pull the same files from the library's own
    # Sublime\ subfolder, which a prior install deployed there. LaTeX.sublime-
    # settings is a syntax-scoped settings file shipping curated math added_words
    # / ignored_words; it stacks on top of the user's global
    # Preferences.sublime-settings so personal proper nouns (collaborators, lab
    # jargon) still apply.
    # When reusing an already-synced library, the source IS the destination:
    # $SublimeUserSync is "$TeXLibDir\Sublime" and Packages\User is junctioned to
    # it, so Copy-Item would be asked to overwrite each file with itself and
    # throws "Cannot overwrite the item ... with itself" -- fatal (exit 10) even
    # though the files are already exactly where they belong. Skip the deploy
    # when both sides resolve to the same directory.
    $BundledSublimeDir = if ($HaveBundle) { Join-Path $TexLibBundle "Sublime" } else { Join-Path $TeXLibDir "Sublime" }
    $SameSublimeDir = [IO.Path]::GetFullPath($BundledSublimeDir).TrimEnd('\') -ieq
                      [IO.Path]::GetFullPath($UserDir).TrimEnd('\')
    if ($SameSublimeDir) {
        Write-Host "  Builder files already live in $UserDir (settings sync folder); nothing to copy" -ForegroundColor Gray
    } elseif (Test-Path $BundledSublimeDir) {
        foreach ($f in @("texlib_builder.py", "TeXLib.sublime-build", "Default.sublime-commands", "LaTeX.sublime-settings")) {
            $src = Join-Path $BundledSublimeDir $f
            if (Test-Path $src) { Copy-Item $src $UserDir -Force }
        }
    }

    # 16c-16e: skipped in -OnlyTeXLib (configs already point at correct paths).
    if (-not $OnlyTeXLib) {
        # 16c. LaTeXTools settings.
        $LaTeXToolsTpl = "$ScriptDir\templates\LaTeXTools.sublime-settings"
        if (Test-Path $LaTeXToolsTpl) {
            $JsonSumatra = "$SumatraDir\$($SumatraExeName)".Replace("\", "\\")
            $JsonSublime = "$SublimeDir\sublime_text.exe".Replace("\", "\\")
            $JsonTexPath = "$TexBinPath;$TexLiveDir\tlpkg\tlperl\bin;`$PATH".Replace("\", "\\")
            $JsonTexLib  = $TeXLibDir.Replace("\", "\\")

            $Content = Get-Content $LaTeXToolsTpl -Raw
            $Content = $Content.Replace("{{SUMATRA_EXE}}", $JsonSumatra)
            $Content = $Content.Replace("{{SUBLIME_EXE}}", $JsonSublime)
            $Content = $Content.Replace("{{TEX_PATH}}",    $JsonTexPath)
            $Content = $Content.Replace("{{TEX_LIB}}",     $JsonTexLib)
            Set-Content -Path "$UserDir\LaTeXTools.sublime-settings" -Value $Content -Encoding UTF8
        }

        # 16d. Sublime editor preferences.
        $PrefsTpl = "$ScriptDir\templates\Preferences.sublime-settings"
        if (Test-Path $PrefsTpl) {
            Copy-Item $PrefsTpl "$UserDir\Preferences.sublime-settings" -Force
        }

        # 16e. SumatraPDF settings.
        $SumatraTpl = "$ScriptDir\templates\SumatraPDF-settings.txt"
        if (Test-Path $SumatraTpl) {
            $TxtSublime = "$SublimeDir\sublime_text.exe".Replace("\", "\\")
            $Content = Get-Content $SumatraTpl -Raw
            $Content = $Content.Replace("{{SUBLIME_EXE}}", $TxtSublime)
            Set-Content -Path "$SumatraDir\SumatraPDF-settings.txt" -Value $Content -Encoding UTF8
        }
    }
} catch {
    Write-Host "Program config write failed: $_" -ForegroundColor Red
    Stop-Installer 10
}


# =============================================================================
# 17. REGISTER FILE ASSOCIATIONS (skipped in -OnlyTeXLib / -Sandbox)
# =============================================================================
if ($WriteMachineState) {
    Write-Host ""
    Write-Host "Registering file associations..." -ForegroundColor Cyan

    # Every extension we claim and every ProgID we have ever used (TeXLib.* now,
    # OneTeX.* before the rename). One list drives both the stale-entry purge
    # and the registration below; uninstall.ps1 carries the same lists.
    $SublimeExts   = @(".txt", ".tex", ".cls", ".sty", ".bib", ".sublime-project", ".sublime-workspace")
    $ManagedExts   = $SublimeExts + @(".pdf")
    $ManagedProgIDs = @("TeXLib.SublimeFile", "TeXLib.SumatraPDF",
                        "OneTeX.SublimeFile", "OneTeX.SumatraPDF")

    # Helpers below report through this counter rather than by returning a count:
    # a stray object escaping any of the cmdlets they call would otherwise turn
    # an integer return into an array and quietly break the tally.
    $script:StaleCleared = 0

    function Test-OwnedAndDead {
        # Is this Open With entry OURS (one of our exe names or ProgIDs) AND
        # DEAD (the exe behind it is gone)? Both halves matter: an association
        # the user set to some other app must never be touched, and one of ours
        # that still resolves is the entry we are about to refresh.
        #
        # Resolution goes through HKEY_CLASSES_ROOT, not HKCU, because that is
        # the merged view Explorer itself uses. A user with their own Sublime in
        # C:\Program Files registers it under HKLM\Software\Classes; looking only
        # at HKCU would call their perfectly live install "dead" and strip it out
        # of every Open With list we touch.
        param([string]$Name, [string[]]$ExePatterns, [string[]]$ProgIDs)
        if (-not $Name) { return $false }
        foreach ($p in $ExePatterns) {
            if ($Name -like $p) {
                return (-not (Test-ShellCommandLive "Registry::HKEY_CLASSES_ROOT\Applications\$Name\shell\open\command"))
            }
        }
        if ($ProgIDs -contains $Name) {
            return (-not (Test-ShellCommandLive "Registry::HKEY_CLASSES_ROOT\$Name\shell\open\command"))
        }
        return $false
    }

    function Unregister-StaleAppEntry {
        # HKCU\Software\Classes\Applications\<exe> is what puts an app in the
        # "Open with" list under its own name. The key is named after the EXE, so
        # every SumatraPDF version bump (SumatraPDF-3.5.2-64.exe ->
        # SumatraPDF-3.6-64.exe) mints a new one, and every install that moves or
        # is uninstalled leaves the old one behind pointing into thin air. Drop
        # the ones whose exe is gone; leave anything still on disk alone, since
        # it may be a Sublime the user installed themselves.
        param([string[]]$ExePatterns)
        $AppsKey = "HKCU:\Software\Classes\Applications"
        if (-not (Test-Path $AppsKey)) { return }
        foreach ($App in @(Get-ChildItem $AppsKey -ErrorAction SilentlyContinue)) {
            $IsOurs = $false
            foreach ($p in $ExePatterns) { if ($App.PSChildName -like $p) { $IsOurs = $true; break } }
            if (-not $IsOurs) { continue }
            if (Test-ShellCommandLive "$($App.PSPath)\shell\open\command") { continue }
            Remove-Item -Path $App.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [stale] removed Applications\$($App.PSChildName)" -ForegroundColor Gray
            $script:StaleCleared++
        }
    }

    function Clear-StaleOpenWithEntry {
        # Purge one extension's leftovers from the three places Explorer builds
        # its "Open with" list out of:
        #   HKCU\...\Explorer\FileExts\<ext>\OpenWithList     (MRU of exe names)
        #   HKCU\...\Explorer\FileExts\<ext>\OpenWithProgids
        #   HKCU\Software\Classes\<ext>\OpenWith{List,Progids}
        # plus UserChoice, which pins a default and will happily pin a ProgID
        # that no longer resolves -- the "double-click does nothing" flavour of
        # this bug. Only entries that are OURS (our exe names, our ProgIDs) and
        # DEAD (exe missing / ProgID key gone) are touched; an association the
        # user set to some other app is never disturbed.
        param([string]$Ext, [string[]]$ExePatterns, [string[]]$ProgIDs)
        $FileExts = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext"
        $ClassExt = "HKCU:\Software\Classes\$Ext"
        # The provider bolts these onto every Get-ItemProperty result; they are
        # not registry values and must never be treated as Open With entries.
        $ProviderProps = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')

        # --- OpenWithList: lettered values (a, b, c, ...) plus an MRUList that
        # orders them. Drop the dead ones, then re-letter what survives so the
        # MRUList stays consistent (a hole in the sequence shows up as a blank
        # row in the Open With dialog).
        foreach ($ListKey in @("$FileExts\OpenWithList", "$ClassExt\OpenWithList")) {
            if (-not (Test-Path $ListKey)) { continue }
            $Props = Get-ItemProperty -Path $ListKey -ErrorAction SilentlyContinue
            if (-not $Props) { continue }
            $Order = @()
            $MRU = $Props.MRUList
            if ($MRU) { $Order = $MRU.ToCharArray() | ForEach-Object { "$_" } }
            foreach ($p in $Props.PSObject.Properties) {
                if ($ProviderProps -contains $p.Name -or $p.Name -eq 'MRUList') { continue }
                if ($Order -notcontains $p.Name) { $Order += $p.Name }
            }
            $Survivors = @()
            foreach ($Slot in $Order) {
                $Val = $Props.$Slot
                if (-not $Val) { continue }
                # A row here is an exe file name, an AppX AUMID (contains '!')
                # or a CLSID-relative path (contains '\'). A value with none of
                # those cannot resolve to any app -- it is corruption, and it
                # renders as a blank line in the Open With dialog. Applied only
                # to this key: an OpenWithProgids NAME legitimately has no dot
                # (`txtfile`), so the same test there would delete real entries.
                if ($Val -notmatch '[.!\\]') {
                    Write-Host "  [stale] $Ext -> '$Val' (malformed entry)" -ForegroundColor Gray
                    $script:StaleCleared++
                    continue
                }
                if (Test-OwnedAndDead -Name $Val -ExePatterns $ExePatterns -ProgIDs $ProgIDs) {
                    Write-Host "  [stale] $Ext -> $Val (exe gone)" -ForegroundColor Gray
                    $script:StaleCleared++
                    continue
                }
                $Survivors += $Val
            }
            foreach ($p in $Props.PSObject.Properties) {
                if ($ProviderProps -contains $p.Name) { continue }
                Remove-ItemProperty -Path $ListKey -Name $p.Name -Force -ErrorAction SilentlyContinue
            }
            $Letters = ""
            for ($i = 0; $i -lt $Survivors.Count; $i++) {
                $L = [char]([int][char]'a' + $i)
                New-ItemProperty -Path $ListKey -Name "$L" -Value $Survivors[$i] -PropertyType String -Force | Out-Null
                $Letters += $L
            }
            if ($Letters) {
                New-ItemProperty -Path $ListKey -Name "MRUList" -Value $Letters -PropertyType String -Force | Out-Null
            }
        }

        # --- OpenWithProgids: value NAMES are ProgIDs (the data is empty).
        foreach ($ProgKey in @("$FileExts\OpenWithProgids", "$ClassExt\OpenWithProgids")) {
            if (-not (Test-Path $ProgKey)) { continue }
            $Props = Get-ItemProperty -Path $ProgKey -ErrorAction SilentlyContinue
            if (-not $Props) { continue }
            foreach ($p in $Props.PSObject.Properties) {
                if ($ProviderProps -contains $p.Name) { continue }
                if (Test-OwnedAndDead -Name $p.Name -ExePatterns $ExePatterns -ProgIDs $ProgIDs) {
                    Remove-ItemProperty -Path $ProgKey -Name $p.Name -Force -ErrorAction SilentlyContinue
                    Write-Host "  [stale] $Ext -> ProgID $($p.Name) (no longer resolves)" -ForegroundColor Gray
                    $script:StaleCleared++
                }
            }
        }

        # --- UserChoice: Explorer's pinned default. Windows guards this key, so
        # the delete can legitimately fail; that is a [stale] entry we could not
        # clear, not an install failure.
        $UserChoice = "$FileExts\UserChoice"
        if (Test-Path $UserChoice) {
            $Pinned = $null
            try { $Pinned = (Get-ItemProperty -Path $UserChoice -ErrorAction SilentlyContinue).ProgId } catch { $Pinned = $null }
            if ($Pinned -and (Test-OwnedAndDead -Name $Pinned -ExePatterns $ExePatterns -ProgIDs $ProgIDs)) {
                try {
                    Remove-Item -Path $UserChoice -Recurse -Force -ErrorAction Stop
                    Write-Host "  [stale] $Ext default was pinned to $Pinned; cleared" -ForegroundColor Gray
                    $script:StaleCleared++
                } catch {
                    Write-Host "  [warn] $Ext is pinned to the dead ProgID $Pinned and Windows would not let us clear it." -ForegroundColor Yellow
                    Write-Host "         Right Click -> Open With -> Choose Another App to reset it." -ForegroundColor Yellow
                }
            }
        }
    }

    function Register-TeXLibAssociation {
        param ($Ext, $ProgID, $Desc, $Exe, $Icon)
        $RegPath = "HKCU:\Software\Classes"
        if (-not (Test-Path "$RegPath\$ProgID")) { New-Item -Path "$RegPath\$ProgID" -Force | Out-Null }
        Set-ItemProperty -Path "$RegPath\$ProgID" -Name "(default)" -Value $Desc
        # FriendlyAppName is what the Open With dialog actually labels the entry
        # with. Without it Windows falls back to the exe's own version-info name,
        # which is how two different installs both end up reading "Sublime Text"
        # with nothing to tell them apart.
        Set-ItemProperty -Path "$RegPath\$ProgID" -Name "FriendlyAppName" -Value $Desc
        if ($Icon) {
            if (-not (Test-Path "$RegPath\$ProgID\DefaultIcon")) { New-Item -Path "$RegPath\$ProgID\DefaultIcon" -Force | Out-Null }
            Set-ItemProperty -Path "$RegPath\$ProgID\DefaultIcon" -Name "(default)" -Value $Icon
        }
        if (-not (Test-Path "$RegPath\$ProgID\shell\open\command")) { New-Item -Path "$RegPath\$ProgID\shell\open\command" -Force | Out-Null }
        Set-ItemProperty -Path "$RegPath\$ProgID\shell\open\command" -Name "(default)" -Value "`"$Exe`" `"%1`""
        if (-not (Test-Path "$RegPath\$Ext")) { New-Item -Path "$RegPath\$Ext" -Force | Out-Null }
        Set-ItemProperty -Path "$RegPath\$Ext" -Name "(default)" -Value $ProgID
        # Offer the ProgID in the Open With list for this extension, so the entry
        # we just (re)pointed at the current exe is the one Windows shows.
        $OpenWith = "$RegPath\$Ext\OpenWithProgids"
        if (-not (Test-Path $OpenWith)) { New-Item -Path $OpenWith -Force | Out-Null }
        New-ItemProperty -Path $OpenWith -Name $ProgID -Value "" -PropertyType String -Force | Out-Null
    }

    # NOTE: we deliberately do NOT write HKCU\Software\Classes\Applications\
    # sublime_text.exe. That key is named after the EXE, not after us, and HKCU
    # shadows HKLM in the merged view Explorer reads -- so pointing it at our
    # portable copy would silently hijack the Open With entry (and any UserChoice
    # referencing it) belonging to a Sublime the user installed in Program Files.
    # Our entries reach the dialog through the TeXLib.* ProgIDs instead, which
    # are namespaced, carry their own FriendlyAppName, and collide with nothing.

    function Sync-ShellAssociationCache {
        # Explorer caches the association data it has already read, so without
        # this the Open With list keeps showing the entries we just deleted until
        # the next sign-out. SHCNE_ASSOCCHANGED (0x08000000) tells it to reread.
        if (-not ("TeXLib.Shell" -as [type])) {
            Add-Type -Namespace TeXLib -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@ -ErrorAction SilentlyContinue
        }
        try { [TeXLib.Shell]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero) } catch { $null = $_ }
    }

    try {
        $SublExe  = "$SublimeDir\sublime_text.exe"
        $SublIcon = "$SublExe,0"
        $SumExe   = "$SumatraDir\$($SumatraExeName)"
        $SumIcon  = "$SumExe,0"

        # Purge first, register second: a stale entry pointing at a previous
        # install root is the thing users actually see, and re-registering on top
        # of it just leaves two entries with the same name in the list.
        $ExePatterns = @("sublime_text.exe", "SumatraPDF*.exe")
        $script:StaleCleared = 0
        Unregister-StaleAppEntry -ExePatterns $ExePatterns
        foreach ($Ext in $ManagedExts) {
            Clear-StaleOpenWithEntry -Ext $Ext -ExePatterns $ExePatterns -ProgIDs $ManagedProgIDs
        }
        if ($script:StaleCleared -gt 0) {
            $Plural = if ($script:StaleCleared -eq 1) { "entry" } else { "entries" }
            Write-Host "  Cleared $($script:StaleCleared) stale 'Open with' $Plural" -ForegroundColor Green
        } else {
            Write-Host "  No stale 'Open with' entries found" -ForegroundColor Gray
        }

        foreach ($Ext in $SublimeExts) {
            Register-TeXLibAssociation -Ext $Ext -ProgID "TeXLib.SublimeFile" -Desc "Sublime Text (TeXLib)" -Exe $SublExe -Icon $SublIcon
        }
        Register-TeXLibAssociation -Ext ".pdf" -ProgID "TeXLib.SumatraPDF" -Desc "SumatraPDF (TeXLib)" -Exe $SumExe -Icon $SumIcon
        Sync-ShellAssociationCache
        Write-Host "  Registered .tex .cls .sty .bib .pdf and friends" -ForegroundColor Green
    } catch {
        Write-Host "File-association registration failed: $_" -ForegroundColor Red
        Write-Host "  (Non-fatal; you can set defaults manually via Right Click -> Open With.)" -ForegroundColor Yellow
    }
}

# =============================================================================
# 18. SHORTCUTS (skipped in -OnlyTeXLib / -Sandbox)
# =============================================================================
if ($WriteMachineState) {
    Write-Host ""
    Write-Host "Creating shortcuts..." -ForegroundColor Cyan

    function New-DesktopAndStartMenuShortcut {
        param ($SourceExe, $ShortcutName)
        try {
            $WS = New-Object -ComObject WScript.Shell
            # GetFolderPath returns "" when the shell folder can't be resolved
            # (redirected/roaming profiles, some service contexts). Unguarded,
            # "$DesktopPath\$ShortcutName.lnk" collapses to "\Sublime.lnk",
            # which resolves to the DRIVE ROOT -- C:\Sublime.lnk. That fails
            # noisily where the root isn't writable and succeeds silently where
            # it is, littering C:\ instead of creating shortcuts. Skip the
            # folder we couldn't resolve rather than guessing.
            $Targets = @()
            $DesktopPath = [Environment]::GetFolderPath("Desktop")
            if ($DesktopPath) { $Targets += "$DesktopPath\$ShortcutName.lnk" }
            else { Write-Host "  [warn] Desktop folder unresolvable; skipping Desktop shortcut for '$ShortcutName'" -ForegroundColor Yellow }

            $StartMenuRoot = [Environment]::GetFolderPath("StartMenu")
            if ($StartMenuRoot) { $Targets += "$StartMenuRoot\Programs\$ShortcutName.lnk" }
            else { Write-Host "  [warn] Start Menu folder unresolvable; skipping Start Menu shortcut for '$ShortcutName'" -ForegroundColor Yellow }

            foreach ($Target in $Targets) {
                $Sc = $WS.CreateShortcut($Target)
                $Sc.TargetPath = $SourceExe
                $Sc.Save()
            }
        } catch {
            Write-Host "  [warn] Could not create shortcut '$ShortcutName': $_" -ForegroundColor Yellow
        }
    }

    New-DesktopAndStartMenuShortcut -SourceExe "$SublimeDir\sublime_text.exe"          -ShortcutName "Sublime"
    New-DesktopAndStartMenuShortcut -SourceExe "$SumatraDir\$($SumatraExeName)"   -ShortcutName "Sumatra"
}


# =============================================================================
# 19. WRITE VERSION STAMP
# =============================================================================
$VersionFile = "$BaseDir\VERSION"
$VersionContent = @"
installer_version=$InstallerVersion
installed_at=$(Get-Date -Format 'o')
texlib_root=$TeXLibDir
sublime_dir=$SublimeDir
sumatra_dir=$SumatraDir
texlive_dir=$TexLiveDir
using_onedrive=$UsingOneDrive
last_mode=$(if ($OnlyTeXLib) { 'only-texlib' } else { 'full' })
"@
Set-Content -Path $VersionFile -Value $VersionContent -Encoding UTF8
Write-Host "  Wrote $VersionFile" -ForegroundColor Gray


# =============================================================================
# 20. END-OF-INSTALL VERIFICATION (skipped in -OnlyTeXLib)
# =============================================================================
if (-not $OnlyTeXLib) {
    Write-Host ""
    Write-Host "Verifying install with a tiny LaTeX compile..." -ForegroundColor Cyan

    try {
        $VerifyDir = "$TempDir\verify"
        New-Item -ItemType Directory -Force -Path $VerifyDir | Out-Null
        $VerifyTex = "$VerifyDir\hello.tex"
        @"
\documentclass{article}
\usepackage[T1]{fontenc}
\begin{document}
TeXLib install verified -- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').
\end{document}
"@ | Set-Content -Path $VerifyTex -Encoding ASCII

        Push-Location $VerifyDir
        try {
            $PdfLatex = "$TexBinPath\pdflatex.exe"
            if (-not (Test-Path $PdfLatex)) {
                Write-Host "  [WARN] pdflatex.exe not found at $PdfLatex; skipping verification" -ForegroundColor Yellow
            } else {
                & $PdfLatex -interaction=nonstopmode hello.tex | Out-Null
                if (Test-Path "$VerifyDir\hello.pdf") {
                    Write-Host "  [OK] hello.pdf produced -- LaTeX works" -ForegroundColor Green
                } else {
                    Write-Host "  [FAIL] pdflatex produced no PDF" -ForegroundColor Red
                    Write-Host "         See $VerifyDir\hello.log for details." -ForegroundColor Yellow
                }
            }
        } finally {
            Pop-Location
        }

        # Sublime build readiness: LaTeXTools' plugin.py won't load without its
        # `regex` dependency, and then Ctrl+B silently does nothing. Confirm the
        # library landed where ST4's plugin host looks for it.
        $RegexInit = "$SublimeDir\Data\Lib\python38\regex\__init__.py"
        if (Test-Path $RegexInit) {
            Write-Host "  [OK] LaTeXTools 'regex' dependency present -- Ctrl+B build enabled" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] LaTeXTools 'regex' dependency missing ($RegexInit)." -ForegroundColor Yellow
            Write-Host "         LaTeXTools will not load and Ctrl+B will do nothing. Re-run the installer." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] Verification step failed: $_" -ForegroundColor Yellow
    }
}


# =============================================================================
# 21. CLEANUP
# =============================================================================
Write-Host ""
Write-Host "Cleaning up temp files..." -ForegroundColor Yellow
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}


# =============================================================================
# 22. COMPLETION
# =============================================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
if ($OnlyTeXLib) {
    Write-Host "   TeXLib library refreshed (installer v$InstallerVersion)   " -ForegroundColor Green
} else {
    Write-Host "   TeXLib v$InstallerVersion installation complete!  " -ForegroundColor Green
}
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Install location:   $BaseDir"  -ForegroundColor Gray
Write-Host "TeXLib library:     $TeXLibDir" -ForegroundColor Gray
Write-Host "Log file:           $LogFile"   -ForegroundColor Gray
Write-Host ""
if (-not $OnlyTeXLib) {
    Write-Host "First-launch notes:" -ForegroundColor Yellow
    Write-Host "  1. Open a NEW terminal -- the updated PATH is not visible to this one." -ForegroundColor Gray
    Write-Host "  2. Sublime Text may show a Package Control loading message on first run;" -ForegroundColor Gray
    Write-Host "     just restart Sublime once and it goes away." -ForegroundColor Gray
    Write-Host "  3. If .tex / .pdf don't open with the right app, Right Click -> Open With" -ForegroundColor Gray
    Write-Host "     -> Choose Another App -> 'Always use this app'. Windows sometimes" -ForegroundColor Gray
    Write-Host "     refuses to honor the registry defaults on the first try. The TeXLib" -ForegroundColor Gray
    Write-Host "     entries are the ones labelled 'Sublime Text (TeXLib)' and" -ForegroundColor Gray
    Write-Host "     'SumatraPDF (TeXLib)'." -ForegroundColor Gray
    Write-Host ""
}
Write-Host "Troubleshooting:    install.bat -Doctor"            -ForegroundColor Cyan
Write-Host "Issues:             $InstallerRepo/issues"          -ForegroundColor Cyan
Write-Host ""

Stop-Installer 0
