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

.PARAMETER Repair
    Re-apply configuration to an existing install and nothing else: the Sublime
    settings junction, the builder files, the TeXLib Sublime package, the
    LaTeXTools / Preferences / SumatraPDF settings, the file associations (with
    the stale "Open with" purge), and the shortcuts. Downloads nothing, installs
    no components, and does not touch the library -- so it takes seconds and
    works offline. This is the answer to "my file associations went weird" or
    "Sublime stopped seeing the builder", which would otherwise need a full
    re-run. Needs an existing install to repair.

.PARAMETER Update
    Fetch the latest release from GitHub, verify it against the release's
    SHA256SUMS, and re-run the newer installer in place of this one. Every other
    argument you pass is forwarded to it, so `install-console.bat -Update -Silent`
    an unattended update. Without this, a newer release means downloading and
    extracting a ZIP by hand.

.PARAMETER TexLiveScheme
    Which TeX Live scheme to install: full (default, ~6 GB), medium (~2.5 GB),
    or basic (~0.6 GB). full is what TeXLib is tested against and what avoids
    "missing package" surprises months later.

    A smaller scheme saves disk reliably. It saves LESS time than the sizes
    suggest, because the install is dominated by downloading from whichever
    CTAN mirror you are handed -- measured here, scheme-basic took ~12 minutes
    on a fast connection. And basic is not viable for TeXLib regardless: it is
    missing 30 of the 50 packages the library requires. Run `-Doctor` after any
    non-full install; it names exactly what is absent and prints the tlmgr line
    to fix it.

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

.PARAMETER Reinstall
    Replace the named components even though they are already installed, without
    being asked: Sublime, SumatraPDF, TeXLive, or All. Anything not named keeps
    the existing default of being left alone.

    This is what makes a partial reinstall possible without a human at the
    keyboard. -Silent alone skips EVERY already-installed component, so there
    was no way to say "replace Sublime, keep the 6 GB TeX Live tree" from a
    script -- or from the GUI, which drives -Silent and so could not offer the
    choice the interactive console prompt has always had.

      tools\install-console.bat -Silent -Reinstall Sublime
      tools\install-console.bat -Silent -Reinstall Sublime,SumatraPDF

    Reinstalling Sublime preserves your settings (they live in the library via
    the Packages\User junction); it re-fetches the binary and LaTeXTools.
    Reinstalling TeXLive re-downloads several GB from CTAN.

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

.PARAMETER Verify
    Check an EXISTING install against the manifest written when it was made:
    report files that changed, went missing, or appeared. Answers "is this
    install still what the installer put there?" -- the question behind a build
    that used to work and now doesn't. Exit 0 when everything matches, 22 when
    anything differs. TeX Live is excluded from the manifest (100k+ files, and
    tlmgr legitimately rewrites them); everything this installer authored is in.

.NOTES
    Configuration file:
      Drop a texlib.config.json next to install.bat to preset any of the above,
      so a lab deployment is "hand someone the folder" rather than a command
      line to retype. Anything passed on the command line always wins.

          { "InstallPath": "D:\\TeXLib", "TexLiveScheme": "medium",
            "Silent": true }

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
    [switch]$Repair,
    [switch]$Update,
    [string]$InstallPath = "",
    [string]$TeXLibPath = "",
    [ValidateSet('full', 'medium', 'basic')]
    [string]$TexLiveScheme = 'full',
    [switch]$Sandbox,
    [switch]$HideJunction,
    [switch]$VerifyDownloads,
    [switch]$Verify,
    # A comma-separated STRING, not a [string[]] with a ValidateSet, because
    # this script is reached three different ways and only a plain string
    # behaves the same through all of them. `powershell.exe -File install.ps1
    # -Reinstall Sublime,TeXLive` tokenises the value as ONE string -- -File
    # mode does no array parsing -- so a [string[]] parameter receives
    # "Sublime,TeXLive" as a single element and ValidateSet rejects it. That is
    # exactly how install-gui.ps1 invokes it. Parsed and validated by hand
    # below, which also lets the error name the bad token.
    [string]$Reinstall = ""
)

# =============================================================================
# 0. INSTALLER METADATA
# =============================================================================
$InstallerVersion = "0.11.0"
$InstallerRepo    = "https://github.com/landonfox00/TeXLib-Installer"
$ReleasesApi      = "https://api.github.com/repos/landonfox00/TeXLib-Installer/releases/latest"

# Captured at script scope because $PSBoundParameters inside a function refers to
# THAT function's parameters -- so -Update, which forwards the caller's own
# arguments to the newer installer, cannot read it from in there.
$ScriptBoundParameters = $PSBoundParameters

# --- texlib.config.json ------------------------------------------------------
# Optional presets living next to install.bat, so handing a lab a configured
# folder beats handing them a command line to retype (and mistype). Read here,
# before section 1 turns any of these into paths.
#
# Explicitly-passed arguments always win: $ScriptBoundParameters is exactly the
# set the caller named, so a key is applied only when it is absent from that.
# Silently overriding what someone typed would be a genuinely nasty surprise.
$ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) "texlib.config.json"
if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $Applied = @()
        foreach ($Entry in $Config.PSObject.Properties) {
            $Name = $Entry.Name
            if ($ScriptBoundParameters.ContainsKey($Name)) { continue }   # caller wins
            if (-not (Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue)) {
                Write-Host "  [warn] texlib.config.json: '$Name' is not an installer option; ignoring." -ForegroundColor Yellow
                continue
            }
            $Value = $Entry.Value
            # JSON has no switch type; accept true/false for them.
            if ((Get-Variable -Name $Name -Scope Script).Value -is [switch]) {
                $Value = [switch]([bool]$Value)
            }
            Set-Variable -Name $Name -Scope Script -Value $Value
            $Applied += "$Name=$($Entry.Value)"
        }
        if ($Applied.Count -gt 0) {
            Write-Host ""
            Write-Host "Using texlib.config.json: $($Applied -join ', ')" -ForegroundColor Cyan
        }
    } catch {
        Write-Host ""
        Write-Host "  [warn] texlib.config.json could not be read ($($_.Exception.Message)); ignoring it." -ForegroundColor Yellow
    }
}

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
    # The download scratch holds install-tl's working directory and its own
    # logs. Clearing it on SUCCESS is right -- it can be multi-GB and is then
    # worthless. Clearing it on FAILURE, which is what happened until 0.9.2,
    # destroys the evidence at exactly the moment someone needs it: a
    # scheme-medium run died 37 minutes in and left nothing to diagnose from.
    # So: keep it when we are exiting non-zero, and say where it is.
    # ($TempDir is $null on the very early junction failure paths -> guarded.)
    if ($TempDir -and (Test-Path $TempDir)) {
        if ($ExitCode -eq 0) {
            Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host ""
            Write-Host "Kept the download scratch for diagnosis: $TempDir" -ForegroundColor Yellow
            Write-Host "  It may be large. Delete it once you no longer need it." -ForegroundColor Gray
        }
    }
    # Launched via tools\install-console.bat -> boot_wrapper.ps1, the wrapper
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

# What each scheme costs. SIZE is quoted rather than a time estimate, because
# time is not a property of the scheme: the install is dominated by downloading
# from whichever CTAN mirror the redirector hands you, and measurement bears
# that out -- scheme-basic took ~12 minutes on a fast connection against an
# advertised "2-5", and scheme-medium ran past the advertised "5-15". Quoting a
# number the installer cannot control just makes it a liar. Disk usage, by
# contrast, is stable and worth stating.
#
# medium's figure is MEASURED: a completed scheme-medium install came to 1.3 GB
# on disk. The 2.5 GB previously quoted here was invented, and being caught
# shipping one made-up number while fixing another is a good reason to mark
# which is which. full and basic are still upstream approximations -- neither
# has been measured here, hence the "about".
#
# The free-space requirement stays deliberately above the installed size:
# install-tl needs room for downloads and unpacking on the way, and refusing an
# install for want of headroom beats dying two thirds of the way through one.
$SchemeDiskGB = @{ 'full' = 6;            'medium' = 2.5;              'basic' = 1 }
$SchemeSize   = @{ 'full' = 'about 6 GB'; 'medium' = '1.3 GB measured'; 'basic' = 'about 0.6 GB' }
$SublimeDir = "$BaseDir\Sublime Text"
$SumatraDir = "$BaseDir\Sumatra"
$TexLiveDir = "$BaseDir\TexLive\$TexLiveYear"
$TexBinPath = "$TexLiveDir\bin\windows"

# Where the TeXLib library is copied FROM.
#
# Through 0.10.x the release ZIP carried a `texlib\` snapshot and this pointed
# at it. 0.11.0 downloads the library instead (see the "texlib" entry in
# $Downloads), so this is filled in at fetch time with the extracted tree.
#
# A `texlib\` directory next to the release root still wins if one is there.
# That covers three real cases for free: an older release folder being re-run,
# an air-gapped machine where someone dropped the tree in deliberately, and a
# maintainer testing an unreleased library without cutting a TeXLib tag.
$ShippedTexLibBundle = Join-Path $ScriptDir "texlib"
$TexLibBundle        = if (Test-Path $ShippedTexLibBundle) { $ShippedTexLibBundle } else { $null }
$HaveShippedBundle   = [bool]$TexLibBundle

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
# exactly those three and nothing else. -Repair very much wants them: fixing the
# associations is most of the point of it.
$WriteMachineState = (-not $OnlyTeXLib) -and (-not $Sandbox)

# --- Mode flags --------------------------------------------------------------
# -Repair re-applies configuration to an install that already exists. It differs
# from -OnlyTeXLib in both directions: it does NOT touch the library (that is
# -OnlyTeXLib's whole job), and it DOES rewrite the associations and shortcuts
# (which -OnlyTeXLib deliberately leaves alone). The two are not combinable.
if ($Repair -and $OnlyTeXLib) {
    Write-Host ""
    Write-Host "FATAL: -Repair and -OnlyTeXLib do opposite things (-Repair re-applies config" -ForegroundColor Red
    Write-Host "       and leaves the library alone; -OnlyTeXLib refreshes the library and" -ForegroundColor Red
    Write-Host "       leaves config alone). Pick one." -ForegroundColor Red
    Write-Host ""
    Stop-Installer 14
}
$InstallComponents = (-not $OnlyTeXLib) -and (-not $Repair)   # section 12
$DeployLibrary     = (-not $Repair)                           # section 13

# What must never ride along when this installer copies a library tree it did
# not build -- a legacy migration, or the Sublime settings carry-over. A release
# bundle is already filtered by make-release.ps1, but these paths copy a folder
# straight off the user's disk, and that folder's Sublime\ becomes Packages\User
# through the settings junction. The author's dev-only test suite living there
# is what killed plugin_host-3.8 in 0.9.5; section 16b-1b purges it afterwards,
# but not copying it in the first place is better than cleaning up after.
$LibraryCopyExclude = @(".git", ".github", "__pycache__", "test_*.py", "_testkit.py")

function Copy-LibraryTree {
    # Copy a library tree, dropping anything matching $LibraryCopyExclude at ANY
    # depth, and report what it dropped.
    #
    # `Copy-Item -Recurse -Exclude` does NOT do this. Its filter applies to the
    # items it enumerates at the top level, so a test_*.py sitting in Sublime\
    # rides straight through -- which is exactly the directory that becomes
    # Packages\User through the settings junction, and exactly the file class
    # that killed plugin_host-3.8 twice (0.8.0's Package Control state, 0.9.5's
    # test suite: nine of those modules replace sys.modules['sublime_plugin'] at
    # import, three end in a bare sys.exit()).
    #
    # It was survivable while make-release.ps1 curated the bundle. From 0.11.0
    # the library arrives as a raw GitHub tag archive carrying the whole repo --
    # .github\ and eighteen test_*.py / _testkit.py under Sublime\ -- so the
    # filter has to be real. Section 16b-1b still purges as a backstop.
    param([string]$Source, [string]$Destination)

    $SrcRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
    $Copied = 0
    $Skipped = 0
    foreach ($Item in (Get-ChildItem -LiteralPath $SrcRoot -Recurse -Force -ErrorAction SilentlyContinue)) {
        $Rel = $Item.FullName.Substring($SrcRoot.Length).TrimStart('\')
        if (-not $Rel) { continue }
        # Excluded if ANY path segment matches -- a directory match takes its
        # whole subtree with it.
        $Excluded = $false
        foreach ($Part in ($Rel -split '\\')) {
            foreach ($Pat in $LibraryCopyExclude) {
                if ($Part -like $Pat) { $Excluded = $true; break }
            }
            if ($Excluded) { break }
        }
        if ($Excluded) {
            if (-not $Item.PSIsContainer) { $Skipped++ }
            continue
        }
        $Target = Join-Path $Destination $Rel
        if ($Item.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $Target)) {
                New-Item -ItemType Directory -Force -Path $Target | Out-Null
            }
        } else {
            $ParentDir = Split-Path $Target -Parent
            if (-not (Test-Path -LiteralPath $ParentDir)) {
                New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
            }
            Copy-Item -LiteralPath $Item.FullName -Destination $Target -Force
            $Copied++
        }
    }
    return [PSCustomObject]@{ Copied = $Copied; Skipped = $Skipped }
}

function Get-ReinstallList {
    # Split -Reinstall on commas / semicolons / whitespace and canonicalise the
    # case, so "sublime, texlive" and "Sublime,TeXLive" mean the same thing.
    # Returns $null for an unrecognised token so the caller can name it.
    param([string]$Raw)
    $Valid = @('Sublime', 'SumatraPDF', 'TeXLive', 'All')
    $Out = @()
    foreach ($Tok in ($Raw -split '[,;\s]+')) {
        if (-not $Tok) { continue }
        $Match = $Valid | Where-Object { $_ -ieq $Tok }
        if (-not $Match) { return @{ Error = $Tok; Valid = $Valid } }
        $Out += $Match
    }
    return @{ List = $Out; Valid = $Valid }
}

function Test-ReinstallRequested {
    # Does -Reinstall name this component? Matching is on the SHORT token the
    # parameter accepts, not the display name the prompt uses, so the two can
    # differ ("TeXLive" vs "TeX Live") without the caller having to know.
    # 'All' matches everything.
    param([string]$ComponentName)
    if (-not $ReinstallList) { return $false }
    if ($ReinstallList -contains 'All') { return $true }
    $Token = switch -Regex ($ComponentName) {
        '^Sublime'  { 'Sublime';    break }
        '^Sumatra'  { 'SumatraPDF'; break }
        '^TeX Live' { 'TeXLive';    break }
        default     { $null }
    }
    if (-not $Token) { return $false }
    return ($ReinstallList -contains $Token)
}

# Parse -Reinstall HERE, immediately below the function that does it: an
# earlier home (up with the -Repair/-OnlyTeXLib conflict check, where it reads
# more naturally) runs before the function is defined, and PowerShell executes
# top to bottom, so it died with "Get-ReinstallList is not recognized".
$ReinstallList = @()
if ($Reinstall) {
    $Parsed = Get-ReinstallList $Reinstall
    if ($Parsed.Error) {
        Write-Host ""
        Write-Host "FATAL: -Reinstall does not know '$($Parsed.Error)'." -ForegroundColor Red
        Write-Host "       Valid components: $($Parsed.Valid -join ', ')" -ForegroundColor Red
        Write-Host "       Example: tools\install-console.bat -Silent -Reinstall Sublime,SumatraPDF" -ForegroundColor Red
        Write-Host ""
        Stop-Installer 14
    }
    $ReinstallList = $Parsed.List
}

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

function Get-ManifestPath {
    # Which files the manifest covers, as paths relative to the install root.
    #
    # Excluded, each for a reason:
    #   TexLive  -- 100k+ files, and tlmgr rewrites them legitimately, so both
    #               hashing it and flagging its changes would be noise.
    #   Logs     -- written during the very run that would hash them.
    #   MANIFEST -- cannot contain its own hash.
    # Reparse points are skipped rather than followed: Packages\User is a
    # junction into the library, so following it would hash the same files twice
    # and report every library edit under two different names.
    param([string]$Root)
    if (-not $Root -or -not (Test-Path $Root)) { return @() }
    $Skip = @('TexLive', 'Logs')
    $Results = @()
    foreach ($Top in @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)) {
        if ($Top.PSIsContainer) {
            if ($Skip -contains $Top.Name) { continue }
            if ($Top.Attributes -match 'ReparsePoint') { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $Top.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)) {
                # A file reached THROUGH a junction still has to be skipped, so
                # test each directory on the way rather than trusting the top.
                if ($f.Attributes -match 'ReparsePoint') { continue }
                $Results += $f.FullName.Substring($Root.TrimEnd('\').Length + 1)
            }
        } elseif ($Top.Name -ne 'MANIFEST') {
            $Results += $Top.Name
        }
    }
    return $Results
}

function Get-MissingTexPackage {
    # Which of $Wanted did kpsewhich fail to resolve?
    #
    # Kept as a NAMED, pure function so the unit-helpers CI job can lift it out
    # by AST and run a case table against it -- because the only interesting
    # input is the one a healthy machine never produces. kpsewhich emits a path
    # per file it finds and an EMPTY LINE per file it does not, and that empty
    # line is what broke the original: `Split-Path "" -Leaf` throws, the
    # script-wide $ErrorActionPreference = "Stop" made it terminating, and the
    # catch reported all 50 packages missing on a perfectly good install. A full
    # TeX Live resolves everything, so no blank lines, so CI could never have
    # seen it -- the check only misbehaved when it had something to report.
    param([string[]]$KpsewhichOutput, [string[]]$Wanted)
    $found = @()
    foreach ($line in $KpsewhichOutput) {
        if (-not $line) { continue }                 # the missing-file marker
        $trimmed = "$line".Trim()
        if (-not $trimmed) { continue }
        # kpsewhich reports forward slashes on Windows; take the last segment
        # without Split-Path, which is fussy about separators and empties.
        $leaf = ($trimmed -split '[\\/]')[-1]
        if ($leaf) { $found += $leaf }
    }
    return @($Wanted | Where-Object { $found -notcontains $_ } | ForEach-Object { $_ -replace '\.sty$', '' })
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
$LegacyRepoCheckout = $null
if (-not $ExplicitTeXLibPath) {
    $LegacyCandidates = @()
    if ($PriorTeXLibRoot) { $LegacyCandidates += $PriorTeXLibRoot }
    if ($OneDrivePath)    { $LegacyCandidates += "$OneDrivePath\Documents\TeXLib" }
    $LegacyCandidates += "$env:USERPROFILE\Documents\TeXLib"
    $LegacyCandidates += "$env:USERPROFILE\TeXLib"
    foreach ($Candidate in $LegacyCandidates) {
        if ($Candidate.TrimEnd('\') -ieq $TeXLibDir.TrimEnd('\')) { continue }
        if (-not (Test-TeXLibLibraryDir $Candidate)) { continue }
        # A git working copy is NOT a pre-0.6.3 deployed library, however much
        # it looks like one -- Test-TeXLibLibraryDir only asks whether the core
        # .sty files are present, and the library's own source repo obviously
        # has them. Documents\TeXLib is the default checkout location AND the
        # default pre-0.6.3 install location, so on a maintainer's machine the
        # two collide exactly.
        #
        # Migrating a checkout is the wrong thing in both directions: the copy
        # is a detached snapshot, so later commits never reach the install and
        # edits to the install never reach the repo -- and it drags the whole
        # working tree across, dev-only tests included. Skip it, keep looking,
        # and say so; -TeXLibPath is how you deliberately point an install at a
        # checkout.
        if (Test-Path (Join-Path $Candidate ".git")) {
            if (-not $LegacyRepoCheckout) { $LegacyRepoCheckout = $Candidate }
            continue
        }
        $LegacyTeXLibDir = $Candidate; break
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
        # Bumped 4180 -> 4200 in 0.9.5. The pin exists so the installer knows
        # exactly which bytes it ran, NOT because TeXLib needs an old build: 4200
        # still ships plugin_host-3.8.exe + python38.dll, so LaTeXTools'
        # .python-version = 3.8 and the cp38 regex wheel below are unaffected.
        # Verified before pinning, per 0.6.4: the archive really contains build
        # 4200 (sublime_text.exe FileVersion 4200) and the hash is stable across
        # repeated downloads, so this is a real bump and not a repackage.
        "Url"  = "https://download.sublimetext.com/sublime_text_build_4200_x64.zip"
        "File" = "sublime_text_build_4200_x64.zip"
        "Type" = "Static"
        "Hash" = "D20456BBEFCD626C7C89A4A2E95C326A0C570DF2FD7626FC35091E43AE5BFF9F"
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
    # NOTE: Package Control is deliberately NOT installed -- see section 12.
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
    "texlib" = @{
        # The TeXLib library itself. Downloaded like every other component as of
        # 0.11.0 -- before that it was bundled INTO the release zip, which tied
        # the library's release cadence to the installer's: a library fix meant
        # cutting an installer release, and every installer release had to
        # decide which snapshot of a separate repo to freeze. They are different
        # projects with different reasons to ship; now the installer just
        # fetches the last published TeXLib.
        #
        # To bump: pick a newer tag at github.com/landonfox00/TeXLib/tags, then
        #   Get-FileHash <downloaded zip> -Algorithm SHA256
        # and update $TeXLibZipDir below to match (GitHub names the folder
        # inside "<repo>-<tag without the leading v>").
        "Url"  = "https://github.com/landonfox00/TeXLib/archive/refs/tags/v0.5.0.zip"
        "File" = "texlib.zip"
        "Type" = "Static"
        "Hash" = "6B1E45B7CF51E0F330AEF1E02B3AC9B27BE25BBE9CFD2EFAE88BF23CC50E20FB"
    }
}

# Folder name inside the pinned LaTeXTools archive (GitHub names it
# "<repo>-<tag>"). Update alongside the latextools tag above.
$LaTeXToolsZipDir = "LaTeXTools-st4-4.5.12"

# Same for TeXLib. Note GitHub drops the leading "v" from the tag here:
# tag v0.5.0 -> folder TeXLib-0.5.0. Update alongside the texlib pin above.
$TeXLibZipDir  = "TeXLib-0.5.0"
$TeXLibVersion = "v0.5.0"   # what -Version reports as the library it installs

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

    # Which library a normal install would put on this machine. -Version is the
    # fast, offline mode, so this reports the PIN rather than reaching out to
    # GitHub -- and a local texlib\ tree, which overrides the pin, is read from
    # its own CHANGELOG so the answer matches what would actually be deployed.
    if ($HaveShippedBundle) {
        $ChangelogPath = Join-Path $TexLibBundle "CHANGELOG.md"
        if (Test-Path $ChangelogPath) {
            $TopVersionLine = (Get-Content $ChangelogPath | Select-String -Pattern '^## \[(?<ver>[^\]]+)\]' | Select-Object -First 1)
            if ($TopVersionLine -and $TopVersionLine.Matches[0].Groups['ver'].Value -ne 'Unreleased') {
                Write-Host ""
                Write-Host "TeXLib library (local texlib\ tree): $($TopVersionLine.Matches[0].Groups['ver'].Value)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host ""
        Write-Host "TeXLib library (downloaded on install): $TeXLibVersion" -ForegroundColor Gray
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
    # Every LaTeX package TeXLib's .sty/.cls files \RequirePackage, minus TeXLib's
    # own. Derived by grepping the library, so it tracks what documents actually
    # need rather than what a scheme happens to ship. This is what makes
    # -TexLiveScheme medium/basic a diagnosable choice instead of a gamble: a
    # thin scheme shows up here by name, months before it would surface as
    # "! LaTeX Error: File `tabularray.sty' not found" in the middle of a build.
    $RequiredTexPackages = @(
        "adjustbox", "amsfonts", "amsmath", "amssymb", "amsthm", "array", "atbegshi",
        "biblatex", "booktabs", "calc", "cancel", "caption", "changepage", "cleveref",
        "colortbl", "enumitem", "environ", "etoolbox", "expl3", "fancyhdr", "fontenc",
        "fontspec", "geometry", "graphicx", "hyperref", "ifthen", "keyval", "lastpage",
        "lmodern", "luacode", "makecell", "mathrsfs", "mathtools", "multicol", "multirow",
        "needspace", "pdfpages", "pgfplots", "qrcode", "siunitx", "subfigure",
        "tabularray", "tasks", "tcolorbox", "tikz", "tikz-cd", "tocloft", "xcolor",
        "xparse", "xstring"
    )
    $Kpsewhich = "$TexBinPath\kpsewhich.exe"
    if (Test-Path $Kpsewhich) {
        # One kpsewhich call, not fifty.
        $Wanted = $RequiredTexPackages | ForEach-Object { "$_.sty" }
        $KpseOut = @()
        # kpsewhich exits 1 when ANY requested file is missing -- which is the
        # normal case this check exists to measure, not a failure to react to.
        # Relax the script-wide "Stop" for the call so a non-zero exit and any
        # stderr chatter cannot turn into a terminating error.
        $PrevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $KpseOut = @(& $Kpsewhich @Wanted) } catch { $KpseOut = @() } finally { $ErrorActionPreference = $PrevEap }
        $MissingPkgs = Get-MissingTexPackage -KpsewhichOutput $KpseOut -Wanted $Wanted
        if ($MissingPkgs.Count -eq 0) {
            _Pass "All $($RequiredTexPackages.Count) LaTeX packages TeXLib requires are installed"
        } else {
            $InstalledScheme = Get-StampedValue -VersionFile $VersionFile -Key "texlive_scheme"
            $SchemeNote = if ($InstalledScheme -and $InstalledScheme -ne 'full') { " (this install used scheme-$InstalledScheme)" } else { "" }
            _Fail "$($MissingPkgs.Count) LaTeX package(s) TeXLib requires are missing$($SchemeNote): $($MissingPkgs -join ', ')"
            Write-Host "         Install them with:  tlmgr install $($MissingPkgs -join ' ')" -ForegroundColor Yellow
            Write-Host "         Or re-run the installer with the default -TexLiveScheme full." -ForegroundColor Yellow
        }
    } else {
        _Warn "kpsewhich not found at $Kpsewhich; cannot check TeXLib's LaTeX package requirements"
    }

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

    # The native TeXLib package (command palette, menu, snippets, texlib_*
    # modules). Sublime only loads .py at the top level of a package directory,
    # so this has to be its own Packages\TeXLib entry -- being visible at
    # Packages\User\texlib\ through the settings junction does nothing.
    $PluginLinkPath = "$SublimeDir\Data\Packages\TeXLib"
    $PluginLibrary  = "$TeXLibDir\Sublime\texlib"
    if (Test-Path "$PluginLinkPath\texlib.py") {
        $PluginItem = Get-Item $PluginLinkPath -Force
        if ($PluginItem.Attributes -match 'ReparsePoint') {
            _Pass "TeXLib Sublime package deployed (junction to the library's Sublime\texlib)"
        } else {
            _Warn "TeXLib Sublime package at $PluginLinkPath is a real folder, not a junction; it will not track library updates"
        }
    } elseif (Test-Path $PluginLibrary) {
        _Fail "TeXLib Sublime package not deployed. The library has it at $PluginLibrary but Sublime cannot load it from there; re-run the installer (or tools\install-console.bat -Repair) to create $PluginLinkPath"
    } else {
        _Warn "This library ships no Sublime\texlib package; only the LaTeXTools builder is available (upgrade the library to get the command palette, snippets, and texlib_* tools)"
    }

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
            } elseif (-not $ProgID) {
                # The key exists with no default value -- common, and reading
                # "$Ext ->  (not a TeXLib association)" with a hole in it invites
                # the reader to wonder what got lost.
                _Warn "$Ext has an HKCU key but no default app set; Right Click -> Open With to set one"
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
# 5b-2. INTEGRITY MODE (-Verify)
# =============================================================================
function Invoke-VerifyInstall {
    # Compare the install against the manifest written when it was made.
    # Three kinds of difference, and they mean different things, so they are
    # reported separately rather than as one "corrupt" verdict:
    #   changed -- content differs. Edited settings live here, and that is
    #              normal and expected; so does actual corruption.
    #   missing -- the installer put it there and it is gone. Usually the
    #              interesting one.
    #   extra   -- new since install. Almost always the user's own work, which
    #              is why it is listed last and never called a problem.
    Show-Banner
    Write-Host "Verifying install integrity at $BaseDir" -ForegroundColor Cyan
    Write-Host ""

    $ManifestFile = "$BaseDir\MANIFEST"
    if (-not (Test-Path $ManifestFile)) {
        Write-Host "No manifest at $ManifestFile." -ForegroundColor Yellow
        if (Test-Path $BaseDir) {
            Write-Host "This install predates -Verify (manifests arrived in 0.9.0)." -ForegroundColor Gray
            Write-Host "Run tools\install-console.bat -Repair to write one, then -Verify again." -ForegroundColor Gray
        } else {
            Write-Host "Nothing is installed at $BaseDir." -ForegroundColor Gray
        }
        Write-Host ""
        Stop-Installer 22
    }

    $Expected = @{}
    foreach ($Line in (Get-Content $ManifestFile -ErrorAction SilentlyContinue)) {
        if (-not $Line) { continue }
        # "<hash>  <relative path>" -- the path may contain spaces, so split on
        # the FIRST run of whitespace only.
        if ($Line -match '^(\S+)\s\s?(.+)$') { $Expected[$Matches[2]] = $Matches[1] }
    }
    Write-Host "Manifest: $($Expected.Count) files" -ForegroundColor Gray

    $Actual = @{}
    foreach ($Rel in (Get-ManifestPath -Root $BaseDir)) {
        try {
            $Actual[$Rel] = (Get-FileHash -LiteralPath (Join-Path $BaseDir $Rel) -Algorithm SHA256 -ErrorAction Stop).Hash
        } catch { $null = $_ }
    }

    $Changed = @(); $Missing = @(); $Extra = @()
    foreach ($Rel in $Expected.Keys) {
        if (-not $Actual.ContainsKey($Rel)) { $Missing += $Rel }
        elseif ($Actual[$Rel] -ne $Expected[$Rel]) { $Changed += $Rel }
    }
    foreach ($Rel in $Actual.Keys) { if (-not $Expected.ContainsKey($Rel)) { $Extra += $Rel } }

    function Show-VerifyGroup {
        param([string]$Label, [string[]]$Items, [string]$Colour, [int]$Limit = 20)
        if ($Items.Count -eq 0) { return }
        Write-Host ""
        Write-Host "$Label ($($Items.Count)):" -ForegroundColor $Colour
        foreach ($i in ($Items | Sort-Object | Select-Object -First $Limit)) { Write-Host "  $i" -ForegroundColor Gray }
        if ($Items.Count -gt $Limit) { Write-Host "  ... and $($Items.Count - $Limit) more" -ForegroundColor Gray }
    }

    Show-VerifyGroup -Label "Missing since install" -Items $Missing -Colour Red
    Show-VerifyGroup -Label "Changed since install" -Items $Changed -Colour Yellow
    Show-VerifyGroup -Label "Added since install"   -Items $Extra   -Colour Gray

    Write-Host ""
    if ($Missing.Count -eq 0 -and $Changed.Count -eq 0) {
        Write-Host "Everything the installer wrote is present and unmodified." -ForegroundColor Green
        if ($Extra.Count -gt 0) {
            Write-Host "($($Extra.Count) file(s) added since -- your own work, most likely.)" -ForegroundColor Gray
        }
        Write-Host ""
        Stop-Installer 0
    }

    Write-Host "Edited settings show up as 'changed' and are perfectly normal." -ForegroundColor Gray
    Write-Host "Anything missing, or changes you did not make, are repaired by:" -ForegroundColor Gray
    Write-Host "  tools\install-console.bat -Repair   (config only, no downloads)" -ForegroundColor Cyan
    Write-Host "  install.bat                         (full re-install, graphical)" -ForegroundColor Cyan
    Write-Host ""
    Stop-Installer 22
}


# =============================================================================
# 5c. SELF-UPDATE MODE (-Update)
# =============================================================================
function Invoke-DownloadWithRetry {
    # Download $Uri to $OutFile, retrying transient failures with backoff.
    # University Wi-Fi blips on a multi-hundred-MB TeX Live download otherwise
    # hard-fail the whole install with no recourse but a from-scratch re-run.
    # Defined HERE rather than with the other install-mode helpers in section 10
    # because -Update dispatches in section 6, before section 10 has run.
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

function Invoke-SelfUpdate {
    # Fetch the newest release, verify it, and hand off to its installer.
    #
    # The pieces were all here already -- the releases API call the update
    # notice uses, Invoke-WebRequest with retry, and hash verification -- but a
    # user who saw "Update available" still had to open a browser, find the
    # asset, download, extract, and re-run. This closes that loop.
    #
    # The downloaded ZIP is verified against the release's own SHA256SUMS before
    # a single line of it executes. That file is served by the same GitHub
    # release over TLS, so it is not an independent trust root -- it is a
    # corruption and truncation check, not a signature. Say so rather than
    # implying more.
    Show-Banner
    Write-Host "Checking for a newer release..." -ForegroundColor Cyan

    try {
        $Release = Invoke-RestMethod -Uri $ReleasesApi -UseBasicParsing -TimeoutSec 30 `
                                     -Headers @{ "User-Agent" = "TeXLib-Installer" }
    } catch {
        Write-Host "Could not reach the GitHub releases API: $_" -ForegroundColor Red
        Write-Host "Check your connection, or download the ZIP yourself from" -ForegroundColor Yellow
        Write-Host "  $InstallerRepo/releases" -ForegroundColor Yellow
        Stop-Installer 21
    }

    $Latest = "$($Release.tag_name)" -replace '^v', ''
    if (-not $Latest) {
        Write-Host "The releases API returned no tag; nothing to update to." -ForegroundColor Red
        Stop-Installer 21
    }
    Write-Host "  Installed: v$InstallerVersion" -ForegroundColor Gray
    Write-Host "  Latest:    v$Latest" -ForegroundColor Gray
    # -Candidate, not -Latest. Test-IsNewerVersion is a SIMPLE function (no
    # CmdletBinding), and those silently sweep unrecognised arguments into
    # $args instead of erroring -- so `-Latest $x` left $Candidate null, the
    # first guard returned $false, and -Update reported "already on the latest
    # release" no matter how far behind you were. It failed safe, which is why
    # it took an end-to-end test to notice at all.
    if (-not (Test-IsNewerVersion -Candidate $Latest -Current $InstallerVersion)) {
        Write-Host ""
        Write-Host "Already on the latest release. Nothing to do." -ForegroundColor Green
        Write-Host "(Re-run without -Update to re-install or repair this version.)" -ForegroundColor Gray
        Write-Host ""
        Stop-Installer 0
    }

    $ZipAsset  = $Release.assets | Where-Object { $_.name -like 'TeXLib-Installer-v*.zip' } | Select-Object -First 1
    $SumsAsset = $Release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if (-not $ZipAsset) {
        Write-Host "Release v$Latest has no TeXLib-Installer-v*.zip asset to download." -ForegroundColor Red
        Write-Host "Grab it manually from $InstallerRepo/releases" -ForegroundColor Yellow
        Stop-Installer 21
    }

    $UpdateDir = Join-Path $env:TEMP "TeXLib_Update"
    if (Test-Path $UpdateDir) { Remove-Item $UpdateDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $UpdateDir | Out-Null
    $ZipPath = Join-Path $UpdateDir $ZipAsset.name

    try {
        Write-Host ""
        Write-Host "Downloading $($ZipAsset.name)..." -ForegroundColor Yellow
        Invoke-DownloadWithRetry -Uri $ZipAsset.browser_download_url -OutFile $ZipPath
    } catch {
        Write-Host "Download failed: $_" -ForegroundColor Red
        Stop-Installer 21
    }

    if ($SumsAsset) {
        try {
            $SumsText = (Invoke-WebRequest -Uri $SumsAsset.browser_download_url -UseBasicParsing -TimeoutSec 30).Content
            if ($SumsText -is [byte[]]) { $SumsText = [System.Text.Encoding]::ASCII.GetString($SumsText) }
            $Expected = ($SumsText -split "`n" |
                         Where-Object { $_ -match [regex]::Escape($ZipAsset.name) } |
                         Select-Object -First 1) -split '\s+' | Select-Object -First 1
            $Actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
            if (-not $Expected) {
                Write-Host "  [WARN] SHA256SUMS has no line for $($ZipAsset.name); cannot verify." -ForegroundColor Yellow
            } elseif ($Actual -ne $Expected.Trim().ToUpperInvariant() -and $Actual -ne $Expected.Trim()) {
                Write-Host "  [FAIL] Hash mismatch on the downloaded release." -ForegroundColor Red
                Write-Host "         expected: $Expected" -ForegroundColor Red
                Write-Host "         actual:   $Actual"   -ForegroundColor Red
                Write-Host "Refusing to run unverified bytes. Try again, or download manually." -ForegroundColor Red
                Stop-Installer 21
            } else {
                Write-Host "  [OK] SHA256 verified against the release's SHA256SUMS" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [WARN] Could not fetch SHA256SUMS ($_); continuing unverified." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARN] Release v$Latest ships no SHA256SUMS; cannot verify the download." -ForegroundColor Yellow
    }

    Write-Host "Extracting..." -ForegroundColor Yellow
    $ExtractDir = Join-Path $UpdateDir "extracted"
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    } catch {
        Write-Host "Could not extract the release ZIP: $_" -ForegroundColor Red
        Stop-Installer 21
    }

    # Release ZIPs put everything at the archive root; tolerate a single
    # wrapping folder in case that ever changes.
    $NewInstaller = Join-Path $ExtractDir "tools\install.ps1"
    if (-not (Test-Path $NewInstaller)) {
        $Inner = Get-ChildItem $ExtractDir -Directory | Select-Object -First 1
        if ($Inner) { $NewInstaller = Join-Path $Inner.FullName "tools\install.ps1" }
    }
    if (-not (Test-Path $NewInstaller)) {
        Write-Host "The downloaded release has no tools\install.ps1; not running it." -ForegroundColor Red
        Write-Host "Extracted to $ExtractDir if you want to look." -ForegroundColor Yellow
        Stop-Installer 21
    }

    # Forward everything the caller gave us EXCEPT -Update, so the newer
    # installer runs the install they actually asked for and cannot loop.
    $Forward = @{}
    foreach ($p in $ScriptBoundParameters.GetEnumerator()) {
        if ($p.Key -eq 'Update') { continue }
        $Forward[$p.Key] = $p.Value
    }
    $ArgLine = @()
    foreach ($p in $Forward.GetEnumerator()) {
        if ($p.Value -is [switch] -or $p.Value -is [bool]) {
            if ($p.Value) { $ArgLine += "-$($p.Key)" }
        } else {
            $ArgLine += "-$($p.Key)"; $ArgLine += "$($p.Value)"
        }
    }

    Write-Host ""
    Write-Host "Handing off to the v$Latest installer..." -ForegroundColor Cyan
    Write-Host "  $NewInstaller $($ArgLine -join ' ')" -ForegroundColor Gray
    Write-Host ""
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $NewInstaller @ArgLine
    $Rc = $LASTEXITCODE
    if ($null -eq $Rc) { $Rc = 0 }

    Write-Host ""
    Write-Host "The v$Latest installer exited with code $Rc." -ForegroundColor Gray
    Write-Host "Its files are at $ExtractDir" -ForegroundColor Gray
    Write-Host "Copy that folder somewhere permanent if you want to keep using it --" -ForegroundColor Gray
    Write-Host "otherwise just run -Update again next time; %TEMP% is cleared eventually." -ForegroundColor Gray
    exit $Rc
}


# =============================================================================
# 6. EARLY-DISPATCH (-VerifyDownloads, -Version, -Doctor, -Verify, -Update)
# =============================================================================
if ($VerifyDownloads) { Invoke-VerifyDownloads }
if ($Version) { Show-VersionInfo }
if ($Doctor)  { Invoke-Doctor }
if ($Verify)  { Invoke-VerifyInstall }
if ($Update)  { Invoke-SelfUpdate }

Show-Banner
Write-Host "Log file:     $LogFile" -ForegroundColor Gray
Write-Host "Install path: $BaseDir" -ForegroundColor Gray
Write-Host "Mode:         " -NoNewline -ForegroundColor Gray
if ($DryRun)     { Write-Host "DRY RUN (no changes will be made)" -ForegroundColor Yellow }
elseif ($Repair) { Write-Host "REPAIR (re-apply config only; no downloads, library untouched)" -ForegroundColor Yellow }
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

# 7c. Disk space. -OnlyTeXLib and -Repair need almost none (no downloads), and
# the requirement otherwise tracks the TeX Live scheme being installed.
try {
    $Drive = (Get-Item (Split-Path $BaseDir -Qualifier)).PSDrive
    $FreeGB = [math]::Round($Drive.Free / 1GB, 1)
    $Need = if ($OnlyTeXLib -or $Repair) { 0.2 } else { $SchemeDiskGB[$TexLiveScheme] }
    if ($FreeGB -ge $Need) {
        Add-PreflightOK "Free space on $($Drive.Name): ${FreeGB} GB (>= ${Need} GB required)"
    } else {
        Add-PreflightFailure "Only ${FreeGB} GB free on $($Drive.Name); need >= ${Need} GB"
    }
} catch {
    Add-PreflightWarning "Could not determine free disk space; continuing"
}

# 7d. Internet connectivity. HEAD request -- confirms TLS reachability without
# pulling any payload. Test-NetConnection would also work but trips
# PSScriptAnalyzer's "hardcoded ComputerName" rule (false positive for a
# public host).
#
# ONLY -Repair skips this. -OnlyTeXLib used to skip it too, on the grounds that
# it "doesn't download anything" -- true while the library shipped inside the
# release zip, and false since 0.11.0, which fetches it. Skipping the check in
# the one mode whose entire job is a download meant an offline -OnlyTeXLib
# sailed through pre-flight and died at exit 7 half way through, having already
# announced that connectivity was fine.
#
# The host checked is the one that mode actually needs: -OnlyTeXLib pulls the
# library from GitHub and never touches CTAN, so failing it on a CTAN outage
# would be a false negative.
if (-not $Repair) {
    $NetCheckUrl = if ($OnlyTeXLib) { "https://github.com/" } else { "https://mirror.ctan.org/" }
    $NetCheckHost = ([Uri]$NetCheckUrl).Host
    # Retry with a longer timeout: mirror.ctan.org is a redirector to regional
    # mirrors and can be briefly slow even when the connection is fine, so a
    # single 5s HEAD was flaky and would hard-fail the whole pre-flight.
    $reachable = $false
    $netErr = $null
    for ($a = 1; $a -le 3 -and -not $reachable; $a++) {
        try {
            $null = Invoke-WebRequest -Uri $NetCheckUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $reachable = $true
        } catch { $netErr = $_; if ($a -lt 3) { Start-Sleep -Seconds (2 * $a) } }
    }
    if ($reachable) {
        Add-PreflightOK "Internet connectivity to $NetCheckHost (HTTPS)"
    } else {
        Add-PreflightFailure "Cannot reach $NetCheckUrl after 3 tries ($($netErr.Exception.Message)); check your internet connection / firewall / VPN"
    }
} else {
    Add-PreflightOK "Skipping internet check (-Repair downloads nothing)"
}

# 7d-2. -Repair needs something to repair. Without this it would sail through
# and "configure" an install that isn't there, junctioning Packages\User into a
# Sublime directory that doesn't exist.
if ($Repair) {
    if ((Test-Path "$BaseDir\VERSION") -or (Test-Path "$SublimeDir\sublime_text.exe")) {
        Add-PreflightOK "Existing install found at $BaseDir to repair"
        Add-PreflightNote "(re-applies config only: settings junction, builder + plugin, app settings, associations, shortcuts)"
    } else {
        Add-PreflightFailure "-Repair needs an existing install to repair, and none was found at $BaseDir. Run install.bat without -Repair first (or pass -InstallPath if you installed elsewhere)."
    }
}

# 7e-7g. Components. Only meaningful when we are actually going to install them:
# -Repair and -OnlyTeXLib touch no component, and saying "will install TeX Live"
# in those modes is a plain untruth in the middle of a report people read to
# decide whether to continue.
if ($InstallComponents) {
    # 7e. Detect existing TeX Live (or our own prior install).
    $OurTex = Get-Command pdflatex -ErrorAction SilentlyContinue
    if ($OurTex -and ($OurTex.Source -like "$BaseDir*")) {
        Add-PreflightOK "Existing TeXLib install detected at $($OurTex.Source) (Skip/Reinstall prompt below)"
    } else {
        Add-PreflightOK "Will install an isolated TeX Live 2025 (scheme-$TexLiveScheme) under $BaseDir"
    }
    if ($TexLiveScheme -ne 'full') {
        Add-PreflightWarning "scheme-$TexLiveScheme is smaller and much faster than scheme-full, but TeXLib is tested against full. A package it needs may be absent."
        Add-PreflightNote "(tools\install-console.bat -Doctor checks every package TeXLib requires, so a gap shows up as a named missing package rather than a cryptic build error)"
    }

    # 7f. Sublime Text: always an isolated portable copy.
    Add-PreflightOK "Installing an isolated portable Sublime Text under $SublimeDir (any existing Sublime is left untouched; our texlib_builder plugin is scoped to it)"

    # 7g. SumatraPDF: always a portable copy.
    Add-PreflightOK "Installing a portable SumatraPDF (any existing install is left untouched)"
}

# 7h. Library location.
if ($ExplicitTeXLibPath) {
    Add-PreflightOK "TeXLib library will live at $TeXLibDir (-TeXLibPath)"
} else {
    Add-PreflightOK "TeXLib library will live at $TeXLibDir (inside the install root, alongside the Sublime plugin)"
}
if ($LegacyRepoCheckout) {
    Add-PreflightNote "(ignoring the TeXLib git checkout at $LegacyRepoCheckout -- it looks like a library because it is one, but copying a working tree would detach it from the install. Pass -TeXLibPath `"$LegacyRepoCheckout`" to install AGAINST it deliberately.)"
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
# it is a component we fetch. Sources, in priority order:
#   1. a local texlib\ tree next to the release root -- deploy it (older release
#      folders, air-gapped machines, a maintainer testing an unreleased library)
#   2. the pinned TeXLib release, downloaded in section 12b
#   3. a pre-0.6.3 library in Documents / OneDrive -- only when the download is
#      not an option, i.e. -Repair, which never touches the library anyway
#
# Through 0.10.x source (1) was the ONLY source, because the library shipped
# inside the release zip. That is why this block used to end in three different
# ways of saying "you downloaded the wrong zip": without a bundle there was
# nothing to install from. There always is now, so those failures are gone --
# and a source checkout of the installer works exactly like a release.
# An existing library counts only if the core .sty files are actually present.
# We check the physical target ($UserRootJunctionTarget), which is where content
# really lives regardless of whether the TEXINPUTS-safe junction exists yet.
$HaveExistingLibrary = Test-TeXLibLibraryDir $UserRootJunctionTarget

# NEVER write a release over a git work tree.
#
# -TeXLibPath aimed at a live checkout is the documented maintainer workflow --
# pre-flight itself suggests it ("Pass -TeXLibPath ... to install AGAINST it
# deliberately"). Through 0.10.x that was safe: with no bundle to deploy the
# checkout was used in place. 0.11.0 made the library a download, so there was
# always something to deploy, and the suggested command silently overwrote
# tracked files with the pinned release -- measured, on a checkout carrying
# uncommitted work. Nothing warned, and the run exited 0.
#
# `.git` is tested with Test-Path rather than as a directory on purpose: a
# linked worktree or a submodule has a .git FILE, and those are working trees
# with uncommitted work in them just the same.
$TeXLibDirIsWorkTree = (Test-Path $TeXLibDir) -and (Test-Path (Join-Path $TeXLibDir ".git"))

$DownloadTeXLib   = $false
$UseTeXLibInPlace = $false

if ($Repair) {
    # -Repair never touches the library, so it needs no source at all -- only
    # somewhere for Packages\User to point at.
    if ($HaveExistingLibrary) {
        Add-PreflightOK "TeXLib library present at $UserRootJunctionTarget (left untouched by -Repair)"
    } else {
        Add-PreflightWarning "No TeXLib library at $UserRootJunctionTarget. -Repair will re-apply config, but builds will fail until you run a normal install to deploy the library."
    }
} elseif ($TeXLibDirIsWorkTree) {
    # Use it exactly as it is, and write nothing into it. The maintainer pointed
    # the installer at their checkout so the install would track that checkout;
    # replacing it with a release is the one thing they cannot have meant.
    $UseTeXLibInPlace = $true
    Add-PreflightOK "TeXLib library at $TeXLibDir is a git work tree; it will be used in place and never written to"
    Add-PreflightNote "(so this run deploys no library: the checkout IS the library, and $TeXLibVersion is not copied over it)"
    if (-not (Test-TeXLibLibraryDir $TeXLibDir)) {
        Add-PreflightWarning "$TeXLibDir is a work tree but is missing the core .sty files (course-metadata / texlib-build / basic-utilities); builds will fail until that checkout is complete."
    }
} elseif ($HaveShippedBundle) {
    Add-PreflightOK "TeXLib library will come from the local tree at $TexLibBundle (overrides the pinned download)"
} else {
    $DownloadTeXLib = $true
    Add-PreflightOK "TeXLib library $TeXLibVersion will be downloaded from GitHub and hash-verified"
    if ($HaveExistingLibrary) {
        $ExistingVer = Get-TeXLibVersion $UserRootJunctionTarget
        $VerNote = if ($ExistingVer) { " (currently TeXLib $ExistingVer)" } else { "" }
        Add-PreflightNote "(a library is already at $UserRootJunctionTarget$VerNote; the download refreshes it, and your Sublime settings live alongside it and are preserved)"
    }
    if ($LegacyTeXLibDir) {
        Add-PreflightNote "(a pre-0.6.3 library at $LegacyTeXLibDir is left untouched; its Sublime settings are carried over)"
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
    $TeXLibPlan = if ($UseTeXLibInPlace) {
        "Use the git work tree at $TeXLibDir as the library, in place -- NOTHING is written to it"
    } elseif ($DownloadTeXLib) {
        "Download TeXLib $TeXLibVersion from GitHub (hash-verified) and deploy it to $TeXLibDir"
    } else {
        "Deploy the local TeXLib tree at $TexLibBundle to $TeXLibDir"
    }
    if ($LegacyTeXLibDir) {
        Write-Host "  * Carry Sublime settings over from $LegacyTeXLibDir\Sublime (original left in place)" -ForegroundColor Gray
    }
    if ($StaleUserRootJunction) {
        Write-Host "  * Retire the leftover user-root junction $StaleUserRootJunction (target preserved)" -ForegroundColor Gray
    }
    if ($Repair) {
        Write-Host "  * Re-junction $SublimeDir\Data\Packages\User -> $SublimeUserSync" -ForegroundColor Gray
        Write-Host "  * Refresh the builder files and the TeXLib Sublime package junction" -ForegroundColor Gray
        Write-Host "  * Rewrite LaTeXTools / Preferences / SumatraPDF settings" -ForegroundColor Gray
        Write-Host "  * Purge stale 'Open with' entries and re-register file associations" -ForegroundColor Gray
        Write-Host "  * Recreate Desktop + Start Menu shortcuts" -ForegroundColor Gray
        Write-Host "  * Write $BaseDir\VERSION" -ForegroundColor Gray
        Write-Host "  * NOT touched: the library, and every component already installed" -ForegroundColor DarkGray
    } elseif ($OnlyTeXLib) {
        Write-Host "  * $TeXLibPlan" -ForegroundColor Gray
        Write-Host "  * Refresh texlib_builder.py + TeXLib.sublime-build in Packages\User" -ForegroundColor Gray
        Write-Host "  * Write $BaseDir\VERSION" -ForegroundColor Gray
    } else {
        Write-Host "  * Install Sublime Text to $SublimeDir" -ForegroundColor Gray
        Write-Host "  * Install SumatraPDF to $SumatraDir"   -ForegroundColor Gray
        Write-Host "  * Install TeX Live to $TexLiveDir (scheme-$TexLiveScheme, $($SchemeSize[$TexLiveScheme]))" -ForegroundColor Gray
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
function Get-FileHashCompat {
    # SHA256/SHA512 of a file, without depending on Get-FileHash resolving.
    #
    # Get-FileHash lives in Microsoft.PowerShell.Utility, which is normally
    # autoloaded -- but a Windows PowerShell 5.1 child launched through
    # `cmd /c` from a PowerShell 7 parent inherits a PSModulePath that can
    # leave it unresolvable, and then every download in this installer dies on
    # "The term 'Get-FileHash' is not recognized" AFTER the bytes are already
    # on disk. Observed in CI on the one path where no other cmdlet from that
    # module runs first, which is exactly the shape of failure a user in an
    # unusual shell would hit and have no way to diagnose.
    #
    # [System.Security.Cryptography] needs no module. Output matches
    # Get-FileHash's .Hash: uppercase hex, no separators.
    param([string]$Path, [string]$Algorithm = "SHA256")
    $Algo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    if (-not $Algo) { throw "Unsupported hash algorithm: $Algorithm" }
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        try { return ([BitConverter]::ToString($Algo.ComputeHash($Stream)) -replace '-', '') }
        finally { $Stream.Dispose() }
    } finally { $Algo.Dispose() }
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
            $CurrentHash = Get-FileHashCompat -Path $LocalPath -Algorithm $Algo
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
        $NewHash = Get-FileHashCompat -Path $DestPath -Algorithm $Algo
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
            $NewHash = Get-FileHashCompat -Path $DestPath -Algorithm $Algo
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
    # -Reinstall names components to replace without being asked. It exists
    # because -Silent was all-or-nothing skip, which left no way to say
    # "replace Sublime, keep the 6 GB TeX Live tree" from a script -- or from
    # the GUI, which drives -Silent and so could not offer the choice the
    # interactive console has always had.
    if ($ReinstallList -and (Test-ReinstallRequested $ComponentName)) {
        Write-Host "  [-Reinstall] Reinstalling $ComponentName as requested" -ForegroundColor Yellow
        return $true
    }
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
# Non-destructive; the old folder is never deleted or edited. ONLY the
# user-owned Sublime\ settings come across, and only when the destination has
# none yet -- section 13 supplies the library itself and then lays the current
# builder files on top.
#
# Before 0.11.0 there was a second shape here: with no bundle and nothing at the
# new location, the old library WAS the only available install source, so the
# whole tree got copied. The library is downloaded now, so there is always a
# better source than a years-old copy of it, and that branch is gone.
if ($LegacyTeXLibDir -and -not $Repair) {
    Write-Host ""
    try {
        if (-not (Test-Path $SublimeUserSync)) {
            $LegacySublime = Join-Path $LegacyTeXLibDir "Sublime"
            if (Test-Path $LegacySublime) {
                Write-Host "Carrying Sublime settings over from $LegacySublime..." -ForegroundColor Cyan
                New-Item -ItemType Directory -Force -Path $SublimeUserSync | Out-Null
                # Copy-LibraryTree, not Copy-Item -Exclude. This destination IS
                # Packages\User via the settings junction, and the source is a
                # library an OLD installer deployed -- which through 0.9.4
                # included the author's test suite. -Exclude would have filtered
                # only the top level and let Sublime\test_*.py through, which is
                # the plugin_host-3.8 killer landing in the exact folder that
                # loads it. Section 16b-1b purges afterwards; not copying them
                # is still better than cleaning up.
                $SetStats = Copy-LibraryTree -Source $LegacySublime -Destination $SublimeUserSync
                Write-Host "  Settings copied to $SublimeUserSync ($($SetStats.Copied) files, $($SetStats.Skipped) dev-only held back)" -ForegroundColor Green
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
if ($StaleUserRootJunction -and -not $Repair) {
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
# 12. INSTALL PROGRAMS (skipped in -OnlyTeXLib / -Repair)
# =============================================================================
if ($InstallComponents) {

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
        } catch {
            Write-Host "Sublime Text install failed: $_" -ForegroundColor Red
            Stop-Installer 3
        }
    }

    # Package Control is deliberately NOT installed (dropped in 0.8.0).
    #
    # This installer already does Package Control's job, and does it with
    # pinned, hash-verified artifacts: LaTeXTools comes from a tagged release,
    # its `regex` library from a specific wheel, and the TeXLib plugin from the
    # bundled library. Running both managers over the same Packages tree is not
    # redundancy, it is a race -- and it bit for real. On first launch Package
    # Control read the shipped `installed_packages` list, decided LaTeXTools'
    # declared libraries were missing (our hand-placed regex carried no
    # .dist-info, so it was invisible to it), and reinstalled `regex` on top of
    # `_regex.cp38-win_amd64.pyd` while the 3.8 plugin host had it loaded. That
    # is what "plugin_host-3.8 has exited unexpectedly" was.
    #
    # Anyone who wants Package Control can install it themselves the usual way;
    # nothing here interferes with that. An existing copy is left strictly
    # alone -- by the time someone re-runs the installer it may be managing
    # packages of their own.

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
selected_scheme scheme-$TexLiveScheme
TEXDIR $TexDirFwd
TEXMFLOCAL $TexMfLocalFwd
TEXMFSYSCONFIG $TexMfSysConfigFwd
TEXMFSYSVAR $TexMfSysVarFwd
portable 1
option_doc 0
option_src 0
"@
            Set-Content -Path "$InstallerRoot\texlive.profile" -Value $ProfileContent -Encoding ASCII

            Write-Host "STARTING TEX LIVE INSTALL (scheme-$TexLiveScheme, $($SchemeSize[$TexLiveScheme]))..." -ForegroundColor Cyan
            Write-Host "  Most of this is download time, so it depends on the CTAN mirror you get" -ForegroundColor Gray
            Write-Host "  more than on the scheme. Progress is reported every 30 seconds." -ForegroundColor Gray
            # Capture install-tl's own output. This is the longest and by far the
            # most failure-prone step -- it downloads gigabytes from a CTAN
            # mirror chosen by a redirector -- and until 0.9.2 every word it said
            # was thrown away, so a failure produced exactly one line: "exited
            # with code 1". Nothing to act on, nothing to paste into a bug
            # report, and the scratch directory holding its own logs was deleted
            # on the way out (see Stop-Installer). Observed for real on a
            # scheme-medium run that died 37 minutes in.
            $TLLog    = "$LogDir\texlive-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
            $TLErrLog = "$TLLog.err"
            Write-Host "  install-tl output -> $TLLog" -ForegroundColor Gray
            # -NoNewWindow, or this step puts a console window on screen for the
            # whole TeX Live install -- minutes to the better part of an hour,
            # sitting in front of the GUI that is already reporting progress.
            # It is the ONLY window the installer opens: everything else it
            # spawns goes through the call operator, which does not allocate a
            # console. -WindowStyle Hidden is not the fix and never was --
            # -RedirectStandardOutput forces UseShellExecute=$false, under which
            # WindowStyle is silently ignored. -NoNewWindow sets CreateNoWindow,
            # which is the flag that actually suppresses it (measured: with the
            # parent itself started CreateNoWindow, as install-gui.ps1 starts
            # this script, the child reports a visible console window without
            # this switch and no console at all with it).
            #
            # Nothing is lost by hiding it: stdout and stderr are already going
            # to $TLLog, Wait-WithHeartbeat prints progress every 30s, and
            # install-tl-windows.bat only runs `perl install-tl` in-place under
            # -no-gui, so its whole child tree inherits this same hidden console
            # rather than opening windows of its own.
            $TLProc = Start-Process -FilePath "$InstallerRoot\install-tl-windows.bat" `
                -ArgumentList "-no-gui -profile texlive.profile" `
                -WorkingDirectory $InstallerRoot -PassThru -NoNewWindow `
                -RedirectStandardOutput $TLLog -RedirectStandardError $TLErrLog
            Wait-WithHeartbeat -Process $TLProc -IntervalSec 30 -Label "TeX Live"

            # Fold stderr into the main log so a bug report needs one file, and
            # surface the tail immediately -- the reason is nearly always in the
            # last few lines, and asking a user to go open a log to find out why
            # their 40-minute install died is a poor way to treat them.
            if ((Test-Path $TLErrLog) -and (Get-Item $TLErrLog).Length -gt 0) {
                Add-Content -Path $TLLog -Value "`r`n--- stderr ---"
                Get-Content $TLErrLog | Add-Content -Path $TLLog
            }
            Remove-Item $TLErrLog -Force -ErrorAction SilentlyContinue

            # Judge the install by its OUTCOME. The exit code is not available.
            #
            # Measured, not assumed: once -RedirectStandardOutput is in play,
            # the object Start-Process -PassThru hands back reports ExitCode as
            # $null -- always, on success as well as failure, and calling
            # WaitForExit() first does NOT change that. A bare `-ne 0` therefore
            # reads every run as failed, which is precisely what v0.9.2 shipped:
            # it turned a perfectly good 25-minute TeX Live install into "did
            # not install cleanly".
            #
            # So the presence of pdflatex.exe is the criterion. It is the thing
            # the install exists to produce, it cannot be null, and it is true
            # exactly when the install is usable. The exit code is reported only
            # if some future PowerShell starts supplying one.
            $TLProc.WaitForExit()   # ensures the tree is fully flushed before we look
            $TLExit = $null
            try { $TLExit = $TLProc.ExitCode } catch { $TLExit = $null }
            $TLExitText = if ($null -eq $TLExit) { "unknown" } else { "$TLExit" }

            if (-not (Test-Path "$TexBinPath\pdflatex.exe")) {
                Write-Host ""
                Write-Host "  install-tl said (last 20 lines of $TLLog):" -ForegroundColor Yellow
                Get-Content $TLLog -Tail 20 -ErrorAction SilentlyContinue |
                    ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
                Write-Host ""
                throw "install-tl finished (exit code $TLExitText) but pdflatex.exe is missing at $TexBinPath; TeX Live did not install cleanly. Full log: $TLLog"
            }
            if ($null -ne $TLExit -and $TLExit -ne 0) {
                # Installed what we need, but grumbled on the way out. Worth
                # saying; not worth throwing away a working install over.
                Write-Host "  [warn] install-tl exited $TLExit but pdflatex.exe is present, so the install looks good." -ForegroundColor Yellow
                Write-Host "         If something misbehaves later, the log is at $TLLog" -ForegroundColor Gray
            }
        } catch {
            Write-Host "TeX Live install failed: $_" -ForegroundColor Red
            Stop-Installer 5
        }
    }
}


# =============================================================================
# 12b. RESOLVE THE SUMATRAPDF EXE THAT IS ACTUALLY ON DISK
# =============================================================================
# SumatraPDF's executable is named by version (SumatraPDF-3.5.2-64.exe), and the
# pinned name is only correct when THIS run installed it. Answer "Skip" to the
# reinstall prompt after a version bump -- or run -Repair / -OnlyTeXLib against
# an older install -- and the pinned name names a file that is not there. All
# three consumers would then point into thin air: the LaTeXTools viewer path
# (16e), the .pdf association (17) and the Start Menu shortcut (18). Nothing
# reads any of them until the user double-clicks a PDF, so it fails silently and
# late, and the Doctor would not catch it either: it resolves the real exe and
# reports [OK] while everything else disagrees with it.
#
# Newest-first, so a directory that somehow holds two versions picks the one the
# rest of the install is most likely to want.
$SumatraOnDisk = Get-ChildItem -Path $SumatraDir -Filter "SumatraPDF*.exe" -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
if ($SumatraOnDisk) {
    if ($SumatraOnDisk.Name -ne $SumatraExeName) {
        Write-Host ""
        Write-Host "  [note] Using the SumatraPDF already installed here ($($SumatraOnDisk.Name))" -ForegroundColor Gray
        Write-Host "         rather than the pinned $SumatraExeName." -ForegroundColor Gray
    }
    $SumatraExeName = $SumatraOnDisk.Name
}


# =============================================================================
# 13. FETCH AND DEPLOY THE TEXLIB LIBRARY
# =============================================================================
Write-Host ""
if (-not $DeployLibrary) {
    Write-Host "Leaving the TeXLib library at $TeXLibDir alone (-Repair)." -ForegroundColor Cyan
} elseif ($UseTeXLibInPlace) {
    Write-Host "Using the TeXLib work tree at $TeXLibDir in place." -ForegroundColor Cyan
    Write-Host "  Nothing was written to it -- your checkout, including uncommitted work, is untouched." -ForegroundColor Gray
    Write-Host "  Run git pull there to update the library; the installer will not do it for you." -ForegroundColor Gray
} else {
    # 13a. Fetch it, unless a local texlib\ tree already stood in for the pin.
    if ($DownloadTeXLib) {
        Write-Host "Downloading the TeXLib library ($TeXLibVersion)..." -ForegroundColor Cyan
        try {
            $TexLibZip     = "$TempDir\texlib.zip"
            $TexLibExtract = "$TempDir\texlib_extract"
            Get-SourceFile -Key "texlib" -DestPath $TexLibZip
            if (Test-Path $TexLibExtract) { Remove-Item $TexLibExtract -Recurse -Force }
            Expand-Archive -Path $TexLibZip -DestinationPath $TexLibExtract
            $ExtractedRoot = Join-Path $TexLibExtract $TeXLibZipDir
            if (-not (Test-Path $ExtractedRoot)) {
                # The pinned tag and $TeXLibZipDir disagree -- almost always a
                # bump where one was updated and the other was not. Name what is
                # actually in there, so the fix is obvious rather than a bare
                # "path not found" three lines later.
                $FoundDirs = @(Get-ChildItem $TexLibExtract -Directory -ErrorAction SilentlyContinue |
                               Select-Object -ExpandProperty Name)
                throw "Expected '$TeXLibZipDir' inside the TeXLib archive, found: $($FoundDirs -join ', '). The `$TeXLibZipDir constant does not match the pinned tag."
            }
            $TexLibBundle = $ExtractedRoot
            Write-Host "  TeXLib $TeXLibVersion downloaded and verified" -ForegroundColor Green
        } catch {
            Write-Host "TeXLib download failed: $_" -ForegroundColor Red
            Stop-Installer 7
        }
    }

    # 13b. Copy it into the library folder. We don't delete extra files here
    # (a migration, or a previous install's settings, may be there ahead of us),
    # only overwrite the library bits.
    Write-Host "Deploying TeXLib library..." -ForegroundColor Cyan
    try {
        $CopyStats = Copy-LibraryTree -Source $TexLibBundle -Destination $TeXLibDir
        Write-Host "  Library deployed to $TeXLibDir ($($CopyStats.Copied) files)" -ForegroundColor Green
        if ($CopyStats.Skipped -gt 0) {
            Write-Host "  Held back $($CopyStats.Skipped) dev-only file(s) that must never reach Packages\User" -ForegroundColor Gray
        }
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

    # 16a. Install LaTeXTools. -Repair is offline by contract, so it reports a
    # missing LaTeXTools rather than quietly turning into a download.
    if ($Repair -and -not (Test-Path $LaTeXToolsDir)) {
        Write-Host "  [WARN] LaTeXTools is missing from $LaTeXToolsDir." -ForegroundColor Yellow
        Write-Host "         -Repair does not download; run install.bat without it to fetch LaTeXTools." -ForegroundColor Yellow
    }
    if ($InstallComponents -and -not (Test-Path $LaTeXToolsDir)) {
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
    if ($Repair -and -not (Test-Path "$SublimeDir\Data\Lib\python38\regex\__init__.py")) {
        Write-Host "  [WARN] LaTeXTools' 'regex' dependency is missing; Ctrl+B will do nothing." -ForegroundColor Yellow
        Write-Host "         -Repair does not download; run install.bat without it to fetch it." -ForegroundColor Yellow
    }
    if ($InstallComponents) {
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
            # Keep the wheel's .dist-info alongside the package. It is how any
            # Python tooling -- Package Control included, if a user installs it
            # later -- recognises regex as already present. Moving only regex\
            # left an unregistered copy that Package Control cheerfully
            # reinstalled over, while the plugin host had the .pyd loaded.
            foreach ($Dist in @(Get-ChildItem -Path $RegexExtract -Directory -Filter '*.dist-info' -ErrorAction SilentlyContinue)) {
                $DistDest = Join-Path $SublimeLibDir $Dist.Name
                if (Test-Path $DistDest) { Remove-Item $DistDest -Recurse -Force }
                Move-Item -Path $Dist.FullName -Destination $DistDest
            }
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
    # $TexLibBundle is the tree the library came from this run (a downloaded
    # archive, or a local texlib\ override); $null when nothing was fetched.
    $BundledSublimeDir = if ($TexLibBundle) { Join-Path $TexLibBundle "Sublime" } else { Join-Path $TeXLibDir "Sublime" }
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

    # 16b-1. Defuse a shipped Package Control settings file.
    #
    # The library's Sublime\ folder has historically carried a
    # `Package Control.sublime-settings` holding a snapshot of the AUTHOR's
    # personal setup -- "installed_packages": [LaTeXTools, Package Control,
    # PowerShell, UnitTesting]. That folder becomes Packages\User via the
    # settings junction, so the file is live for every coworker who installs.
    # If Package Control is ever present, it reads that list on startup and
    # starts installing: PowerShell and UnitTesting, which have nothing to do
    # with TeXLib, and LaTeXTools' declared libraries on top of the copies this
    # installer placed by hand.
    #
    # 0.8.0+ release bundles no longer contain the file, but a library deployed
    # by an older installer still has it sitting there. Remove it -- UNLESS
    # Package Control is actually installed, in which case the file is now its
    # own live state and deleting it would make it re-resolve everything.
    $PkgCtrlSettings = Join-Path $SublimeUserSync "Package Control.sublime-settings"
    $PkgCtrlInstalled = Test-Path "$SublimeDir\Data\Installed Packages\Package Control.sublime-package"
    if ((Test-Path $PkgCtrlSettings) -and -not $PkgCtrlInstalled) {
        Remove-Item $PkgCtrlSettings -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed a stale Package Control settings file (Package Control is not installed)" -ForegroundColor Gray
    } elseif ($PkgCtrlInstalled) {
        Write-Host "  [note] Package Control is installed here; leaving it and its settings alone." -ForegroundColor Gray
    }

    # 16b-1b. Purge the library's dev-only test suite from Packages\User.
    #
    # Same shape of bug as 16b-1, different file. The library's Sublime\ folder
    # is the AUTHOR's working directory: alongside the four deployables it holds
    # `_testkit.py` and seventeen `test_*.py`. deploy.ps1 copies an explicit
    # allowlist, so the author's own machine never sees them in Packages\User --
    # but make-release bundles Sublime\ wholesale (git archive of HEAD), and the
    # settings junction makes that folder Packages\User verbatim. Sublime loads
    # every top-level .py in Packages\User as a plugin, so on a bundle install
    # the test suite runs inside plugin_host-3.8. Two ways it dies there:
    #   - 9 of them call _testkit.stub_sublime() at module scope, which does
    #     sys.modules["sublime"] = <stub> and sys.modules["sublime_plugin"] =
    #     <stub> -- replacing, in the live host, the very module Sublime
    #     dispatches commands and event listeners through.
    #   - test_texlib_build / _runner / _texam end in a module-scope sys.exit().
    #     SystemExit is a BaseException, so the plugin loader's `except
    #     Exception` never sees it and it takes the host process with it.
    # That is "plugin_host-3.8 has exited unexpectedly" -- the same symptom
    # 0.8.0 chased to Package Control, from the same folder, still armed.
    #
    # 0.9.5+ bundles carry no test suite. This purge is for libraries an older
    # installer already deployed; the pattern is the signature, and it leaves a
    # user's own plugins in Packages\User alone.
    $DevOnlyPy = @(Get-ChildItem -Path $SublimeUserSync -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like "test_*.py" -or $_.Name -eq "_testkit.py" })
    if ($DevOnlyPy.Count -gt 0) {
        foreach ($f in $DevOnlyPy) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
        Write-Host "  Removed $($DevOnlyPy.Count) dev-only test file(s) from Packages\User (they crash plugin_host-3.8)" -ForegroundColor Gray
    }

    # 16b-2. Deploy the native TeXLib Sublime package.
    # The library carries a real Sublime package in Sublime\texlib\ -- the
    # command palette entries, Main.sublime-menu, snippets, the TeXLib Build
    # Output syntax, and the texlib_* Python modules (doctor, scaffold, bank,
    # texam, complete, locate, ...). It ships inside every release bundle, and
    # through 0.6.4 the installer never deployed any of it: installed users got
    # the four flat builder files in Packages\User and nothing else, while a
    # developer running the library's own deploy-plugin.ps1 got the lot.
    #
    # It cannot simply live where it already sits. Packages\User is junctioned
    # to <library>\Sublime, so the package IS physically present at
    # Packages\User\texlib\ -- but Sublime only loads .py at the TOP level of a
    # package directory, so a nested folder is inert. It needs its own package
    # directory, which is what deploy-plugin.ps1 creates as Packages\TeXLib.
    #
    # A junction rather than a copy, for the same reason that script uses one:
    # the package then tracks the library it came from, so an -OnlyTeXLib
    # refresh updates the plugin with no extra step.
    $PluginSource = Join-Path $SublimeUserSync "texlib"
    $PluginLink   = Join-Path $PackagesDir "TeXLib"
    if (-not (Test-Path $PackagesDir)) {
        # No Sublime here to deploy into -- e.g. -OnlyTeXLib on a machine that
        # has the library but not the editor. New-Item -ItemType Junction does
        # not create missing parents, so without this the whole of section 16
        # would abort (exit 10) over an optional step.
        Write-Host "  [note] No Sublime packages folder at $PackagesDir; skipping plugin deploy." -ForegroundColor Gray
    } elseif (Test-Path $PluginSource) {
        if (Test-Path $PluginLink) {
            $LinkItem = Get-Item $PluginLink -Force
            if ($LinkItem.Attributes -match 'ReparsePoint') {
                # Re-point it: a prior install may have linked an older location.
                [System.IO.Directory]::Delete($PluginLink, $false)
            } else {
                # A real directory here is someone's hand-installed package.
                # Refusing is right -- clobbering it would lose their work -- but
                # it is not worth failing an otherwise good install over.
                Write-Host "  [warn] $PluginLink is a real folder, not a junction; leaving it alone." -ForegroundColor Yellow
                Write-Host "         The bundled TeXLib plugin was NOT deployed. Move that folder and re-run." -ForegroundColor Yellow
                $PluginLink = $null
            }
        }
        if ($PluginLink) {
            New-Item -ItemType Junction -Path $PluginLink -Target $PluginSource | Out-Null
            Write-Host "  Deployed the TeXLib Sublime package to $PluginLink" -ForegroundColor Green
        }
    } else {
        Write-Host "  [note] No Sublime\texlib package in this library; skipping plugin deploy." -ForegroundColor Gray
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

        # 16c-2. Native TeXLib plugin settings (texinputs).
        #
        # Ctrl+B on a .tex file runs the NATIVE `texlib_build` command -- the
        # TeXLib package's own keymap has bound it since the 2026-07-10 cutover
        # -- NOT LaTeXTools. The native command takes its TEXINPUTS from
        # `texinputs` in TeXLib.sublime-settings, and the package default ships
        # that key COMMENTED OUT ("leave unset to inherit the process
        # environment"). Sublime inherits no TEXINPUTS and the library is
        # deliberately outside every TEXMF tree, so through 0.10.1 a fresh
        # install left the primary build path unable to resolve a single TeXLib
        # class: every document died at \documentclass with "File
        # `didactic.cls' not found". The LaTeXTools settings written just above
        # carry a correct TEXINPUTS, but only the legacy Tools > Build With
        # path reads them -- which is why this survived so long, and why the
        # end-of-install smoke test (a plain `article`, no TeXLib class) still
        # reported "LaTeX works". Section 20 now builds a real TeXLib class.
        $TeXLibSettingsTpl = "$ScriptDir\templates\TeXLib.sublime-settings"
        $TeXLibSettingsOut = "$UserDir\TeXLib.sublime-settings"
        $TeXLibSettingsMark = "written by TeXLib-Installer"
        $TeXLibTexInputsEnv = $null   # set below; read by section 20's verification
        if (Test-Path $TeXLibSettingsTpl) {
            # Ours to (re)write when absent, or when the file still carries the
            # marker saying we authored it -- a re-install that moved the
            # library must not leave stale paths behind. A file the user has
            # taken over is never touched.
            $ExistingTeXLibSettings = if (Test-Path $TeXLibSettingsOut) { Get-Content $TeXLibSettingsOut -Raw } else { $null }
            $OursToWrite = (-not $ExistingTeXLibSettings) -or ($ExistingTeXLibSettings -match [regex]::Escape($TeXLibSettingsMark))

            if ($OursToWrite) {
                # Explicit, non-recursive segment list: the library root plus
                # each immediate subdirectory actually holding a class/package/
                # engine file. Generated rather than hardcoded, so a new module
                # directory in the library needs no installer release. Forward
                # slashes throughout -- kpathsea takes them on Windows and they
                # need no JSON escaping.
                $TexLibFs = $TeXLibDir.Replace("\", "/").TrimEnd("/")
                $Segments = New-Object System.Collections.Generic.List[string]
                $Segments.Add(".")
                $Segments.Add($TexLibFs)
                foreach ($Sub in @(Get-ChildItem -LiteralPath $TeXLibDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
                    # Sublime\ is the settings sync folder (Packages\User), not
                    # a TeX module; dot-dirs and __pycache__ never hold classes.
                    if ($Sub.Name -eq "Sublime" -or $Sub.Name -eq "__pycache__" -or $Sub.Name -like ".*") { continue }
                    $TeXFiles = @(Get-ChildItem -LiteralPath $Sub.FullName -File -ErrorAction SilentlyContinue |
                                  Where-Object { $_.Extension -eq ".sty" -or $_.Extension -eq ".cls" -or $_.Extension -eq ".lua" })
                    if ($TeXFiles.Count -gt 0) { $Segments.Add("$TexLibFs/$($Sub.Name)") }
                }
                # Load-bearing empty segment -- see the template's own comment.
                $Segments.Add("")
                $JsonSegments = ($Segments | ForEach-Object {
                    '"' + $_.Replace('\', '\\').Replace('"', '\"') + '"'
                }) -join ", "
                # Kept for section 20, which verifies these paths actually
                # resolve the classes instead of taking it on trust.
                $TeXLibTexInputsEnv = ($Segments -join ';')

                $Content = Get-Content $TeXLibSettingsTpl -Raw
                $Content = $Content.Replace("{{TEXINPUTS_SEGMENTS}}", $JsonSegments)
                Set-Content -Path $TeXLibSettingsOut -Value $Content -Encoding UTF8
                Write-Host "  Wrote $TeXLibSettingsOut (texinputs: $($Segments.Count - 1) search paths)" -ForegroundColor Green
            } elseif ($ExistingTeXLibSettings -notmatch '(?m)^\s*"texinputs"\s*:') {
                # Their file, so it stays -- but it has no active texinputs, and
                # that is exactly the state in which nothing builds. Say so, and
                # hand them the line to paste rather than making them derive it.
                $TexLibFs = $TeXLibDir.Replace("\", "/").TrimEnd("/")
                Write-Host "  [warn] $TeXLibSettingsOut is yours (no installer marker) and sets no `"texinputs`"." -ForegroundColor Yellow
                Write-Host "         Ctrl+B builds will not resolve the TeXLib classes until it does. Add:" -ForegroundColor Yellow
                Write-Host "           `"texinputs`": [`".`", `"$TexLibFs`", ... , `"`"]" -ForegroundColor Gray
            } else {
                Write-Host "  Left your own $TeXLibSettingsOut alone (it sets texinputs)" -ForegroundColor Gray
            }
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

    # Helpers below report through these rather than by returning a count: a
    # stray object escaping any of the cmdlets they call would otherwise turn an
    # integer return into an array and quietly break the tally.
    $script:StaleCleared = 0
    $script:StillPinned  = @()   # extensions whose UserChoice Windows would not let us clear

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
        param([string]$Ext, [string[]]$ExePatterns, [string[]]$ProgIDs, [string[]]$AboutToRegister = @())
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

        # --- UserChoice: Explorer's pinned default.
        #
        # A ProgID this run is ABOUT TO REGISTER is not stale, however dead it
        # looks right now. Re-installing over a previous uninstall reaches here
        # with .pdf still pinned to TeXLib.SumatraPDF and that ProgID's key
        # already deleted -- so the naive test called it dead and warned, while
        # section 17 was thirty lines from making that exact pin correct again.
        # The warning was not just noise; it told the user to go undo something
        # the installer wanted.
        $UserChoice = "$FileExts\UserChoice"
        if (Test-Path $UserChoice) {
            $Pinned = $null
            try { $Pinned = (Get-ItemProperty -Path $UserChoice -ErrorAction SilentlyContinue).ProgId } catch { $Pinned = $null }
            if ($Pinned -and ($AboutToRegister -notcontains $Pinned) -and
                (Test-OwnedAndDead -Name $Pinned -ExePatterns $ExePatterns -ProgIDs $ProgIDs)) {
                try {
                    Remove-Item -Path $UserChoice -Recurse -Force -ErrorAction Stop
                    Write-Host "  [stale] $Ext default was pinned to $Pinned; cleared" -ForegroundColor Gray
                    $script:StaleCleared++
                } catch {
                    # Windows guards this key and some builds refuse the delete
                    # outright. Collected for one coherent line at the end rather
                    # than four near-identical yellow blocks mid-run.
                    $script:StillPinned += $Ext
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
        # The ProgIDs this run is about to (re-)register, so the purge does not
        # treat them as dead in the window before they exist again.
        $WillRegister = @("TeXLib.SublimeFile", "TeXLib.SumatraPDF")
        $script:StaleCleared = 0
        $script:StillPinned  = @()
        Unregister-StaleAppEntry -ExePatterns $ExePatterns
        foreach ($Ext in $ManagedExts) {
            Clear-StaleOpenWithEntry -Ext $Ext -ExePatterns $ExePatterns `
                                     -ProgIDs $ManagedProgIDs -AboutToRegister $WillRegister
        }
        if ($script:StaleCleared -gt 0) {
            $Plural = if ($script:StaleCleared -eq 1) { "entry" } else { "entries" }
            Write-Host "  Cleared $($script:StaleCleared) stale 'Open with' $Plural" -ForegroundColor Green
        } elseif ($script:StillPinned.Count -eq 0) {
            Write-Host "  No stale 'Open with' entries found" -ForegroundColor Gray
        }
        if ($script:StillPinned.Count -gt 0) {
            # Reported here, once, instead of a four-line yellow block per
            # extension in the middle of the run -- and never alongside "No
            # stale entries found", which is what it used to contradict.
            Write-Host "  [note] Windows would not let us clear the pinned default app for" -ForegroundColor Yellow
            Write-Host "         $($script:StillPinned -join ', ')" -ForegroundColor Yellow
            Write-Host "         Each points at an entry that no longer exists, so Windows will ask" -ForegroundColor Gray
            Write-Host "         which app to use the next time you open one. To settle it now:" -ForegroundColor Gray
            Write-Host "         Right Click -> Open With -> Choose Another App -> 'Always use this app'." -ForegroundColor Gray
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

    # GetFolderPath returns "" when a shell folder can't be resolved (redirected
    # or roaming profiles, some service contexts). Unguarded, "$Dir\$Name.lnk"
    # collapses to "\Sublime.lnk", which resolves to the DRIVE ROOT --
    # C:\Sublime.lnk. That fails noisily where the root isn't writable and
    # succeeds silently where it is, littering C:\ instead of creating
    # shortcuts. Skip a folder we couldn't resolve rather than guessing.
    $DesktopPath   = [Environment]::GetFolderPath("Desktop")
    $StartMenuRoot = [Environment]::GetFolderPath("StartMenu")
    if (-not $DesktopPath)   { Write-Host "  [warn] Desktop folder unresolvable; skipping Desktop shortcuts" -ForegroundColor Yellow }
    if (-not $StartMenuRoot) { Write-Host "  [warn] Start Menu folder unresolvable; skipping Start Menu shortcuts" -ForegroundColor Yellow }

    # One "TeXLib" Start Menu folder rather than loose entries scattered among
    # every other program: the three things belong together, and it gives
    # Doctor somewhere to live that isn't "find the folder you extracted the
    # installer into, months ago".
    $StartMenuGroup = if ($StartMenuRoot) { "$StartMenuRoot\Programs\TeXLib" } else { $null }
    if ($StartMenuGroup -and -not (Test-Path $StartMenuGroup)) {
        New-Item -ItemType Directory -Force -Path $StartMenuGroup | Out-Null
    }

    function New-TeXLibShortcut {
        param(
            [string]$Path,
            [string]$TargetPath,
            [string]$Arguments = "",
            [string]$Description = "",
            [string]$IconLocation = ""
        )
        if (-not $Path) { return }
        try {
            $WS = New-Object -ComObject WScript.Shell
            $Sc = $WS.CreateShortcut($Path)
            $Sc.TargetPath = $TargetPath
            if ($Arguments)    { $Sc.Arguments = $Arguments }
            if ($Description)  { $Sc.Description = $Description }
            if ($IconLocation) { $Sc.IconLocation = $IconLocation }
            $Sc.Save()
        } catch {
            Write-Host "  [warn] Could not create shortcut '$Path': $_" -ForegroundColor Yellow
        }
    }

    $SublimeExe = "$SublimeDir\sublime_text.exe"
    $SumatraExe = "$SumatraDir\$($SumatraExeName)"

    function Test-OurShortcut {
        # Does this .lnk point INTO the install root? A name is not ownership.
        param([string]$Path, [string]$Root)
        try { $t = (New-Object -ComObject WScript.Shell).CreateShortcut($Path).TargetPath }
        catch { return $false }
        if (-not $t -or -not $Root) { return $false }
        return $t.ToLowerInvariant().StartsWith($Root.TrimEnd('\').ToLowerInvariant() + '\')
    }

    # Desktop keeps the two apps only -- a desktop is not a place for a
    # diagnostic tool.
    #
    # Named to match the Start Menu group rather than the bare "Sublime.lnk" /
    # "Sumatra.lnk" of earlier releases. Those names are generic enough that a
    # user with their own Desktop shortcut to a Sublime in Program Files had it
    # SILENTLY OVERWRITTEN by this section -- CreateShortcut happily rewrites an
    # existing file. The suffixed names cannot collide, and they say which
    # Sublime this is, which is the same reason the ProgIDs carry it.
    if ($DesktopPath) {
        New-TeXLibShortcut -Path "$DesktopPath\Sublime Text (TeXLib).lnk" -TargetPath $SublimeExe -Description "Sublime Text, configured for TeXLib"
        New-TeXLibShortcut -Path "$DesktopPath\SumatraPDF (TeXLib).lnk"   -TargetPath $SumatraExe -Description "SumatraPDF, configured for TeXLib"

        # Retire the pre-0.8.1 names, but only where they are demonstrably ours.
        # Deleting by name here would repeat the very mistake above.
        foreach ($Old in @("Sublime.lnk", "Sumatra.lnk")) {
            $OldPath = Join-Path $DesktopPath $Old
            if ((Test-Path $OldPath) -and (Test-OurShortcut -Path $OldPath -Root $BaseDir)) {
                Remove-Item $OldPath -Force -ErrorAction SilentlyContinue
                Write-Host "  Replaced the pre-0.8.1 Desktop shortcut $Old" -ForegroundColor Gray
            }
        }
    }

    if ($StartMenuGroup) {
        New-TeXLibShortcut -Path "$StartMenuGroup\Sublime Text (TeXLib).lnk" -TargetPath $SublimeExe -Description "Sublime Text, configured for TeXLib"
        New-TeXLibShortcut -Path "$StartMenuGroup\SumatraPDF (TeXLib).lnk"   -TargetPath $SumatraExe -Description "SumatraPDF, configured for TeXLib"
        # Doctor runs from the copy stashed in <BaseDir>\Scripts (section 11),
        # so it keeps working after the extracted installer folder is deleted --
        # which is exactly when someone needs to diagnose something.
        $StashedInstaller = "$ScriptsDir\install.ps1"
        if (Test-Path $StashedInstaller) {
            New-TeXLibShortcut -Path "$StartMenuGroup\TeXLib Doctor.lnk" `
                -TargetPath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                -Arguments "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$StashedInstaller`" -Doctor" `
                -Description "Diagnose this TeXLib install and print a pass/warn/fail report" `
                -IconLocation "$env:SystemRoot\System32\imageres.dll,76"
        }
        Write-Host "  Start Menu group: $StartMenuGroup" -ForegroundColor Green
    }

    # Loose Programs\*.lnk from installs before 0.7.0, now superseded by the
    # group above. Left behind they are duplicate entries pointing at the same
    # two exes.
    if ($StartMenuRoot) {
        foreach ($Old in @("Sublime.lnk", "Sumatra.lnk")) {
            $OldPath = "$StartMenuRoot\Programs\$Old"
            if (Test-Path $OldPath) {
                Remove-Item $OldPath -Force -ErrorAction SilentlyContinue
                Write-Host "  Removed the pre-0.7.0 loose Start Menu entry $Old" -ForegroundColor Gray
            }
        }
    }
}


# =============================================================================
# 18b. REGISTER IN "INSTALLED APPS" (skipped in -OnlyTeXLib / -Sandbox)
# =============================================================================
# Until 0.9.0 TeXLib was invisible to Windows' own Installed Apps list, so
# uninstalling meant remembering where you extracted a ZIP months ago -- or
# finding <InstallPath>\Scripts, which nobody knows about. A per-user Uninstall
# key costs nothing and puts it where every other program is.
#
# HKCU, not HKLM: the whole install is per-user and needs no admin, and an entry
# under HKLM would advertise it to users who do not have it.
if ($WriteMachineState) {
    Write-Host ""
    Write-Host "Registering in Installed Apps..." -ForegroundColor Cyan
    try {
        $ArpKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TeXLib"
        if (-not (Test-Path $ArpKey)) { New-Item -Path $ArpKey -Force | Out-Null }

        $PSExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $StashedUninstall = "$ScriptsDir\uninstall.ps1"
        $StashedInstall   = "$ScriptsDir\install.ps1"

        Set-ItemProperty -Path $ArpKey -Name "DisplayName"     -Value "TeXLib (Sublime Text, SumatraPDF, TeX Live)"
        Set-ItemProperty -Path $ArpKey -Name "DisplayVersion"  -Value $InstallerVersion
        Set-ItemProperty -Path $ArpKey -Name "Publisher"       -Value "TeXLib"
        Set-ItemProperty -Path $ArpKey -Name "InstallLocation" -Value $BaseDir
        Set-ItemProperty -Path $ArpKey -Name "URLInfoAbout"    -Value $InstallerRepo
        Set-ItemProperty -Path $ArpKey -Name "InstallDate"     -Value (Get-Date -Format 'yyyyMMdd')
        Set-ItemProperty -Path $ArpKey -Name "NoModify"        -Value 0 -Type DWord
        Set-ItemProperty -Path $ArpKey -Name "NoRepair"        -Value 0 -Type DWord
        if (Test-Path "$SublimeDir\sublime_text.exe") {
            Set-ItemProperty -Path $ArpKey -Name "DisplayIcon" -Value "$SublimeDir\sublime_text.exe,0"
        }
        # Both forms matter: Windows uses QuietUninstallString for the one-click
        # "Uninstall" in Settings, and UninstallString for the classic dialog.
        if (Test-Path $StashedUninstall) {
            Set-ItemProperty -Path $ArpKey -Name "UninstallString" `
                -Value "`"$PSExe`" -NoProfile -ExecutionPolicy Bypass -File `"$StashedUninstall`" -InstallPath `"$BaseDir`""
            Set-ItemProperty -Path $ArpKey -Name "QuietUninstallString" `
                -Value "`"$PSExe`" -NoProfile -ExecutionPolicy Bypass -File `"$StashedUninstall`" -Silent -InstallPath `"$BaseDir`""
        }
        # "Modify" maps to -Repair, which is exactly what that button should do.
        if (Test-Path $StashedInstall) {
            Set-ItemProperty -Path $ArpKey -Name "ModifyPath" `
                -Value "`"$PSExe`" -NoProfile -ExecutionPolicy Bypass -File `"$StashedInstall`" -Repair -InstallPath `"$BaseDir`""
        }
        # EstimatedSize is in KB and is what Windows shows in the size column.
        # Measuring a 6 GB TeX Live tree takes real time, so only do it on a run
        # that actually installed one; otherwise keep whatever is already there.
        if ($InstallComponents) {
            try {
                $Bytes = (Get-ChildItem -Path $BaseDir -Recurse -File -Force -ErrorAction SilentlyContinue |
                          Measure-Object -Property Length -Sum).Sum
                if ($Bytes) {
                    Set-ItemProperty -Path $ArpKey -Name "EstimatedSize" -Value ([int]($Bytes / 1KB)) -Type DWord
                }
            } catch { $null = $_ }
        }
        Write-Host "  TeXLib now appears in Settings > Apps > Installed apps" -ForegroundColor Green
    } catch {
        Write-Host "  [warn] Could not register in Installed Apps: $_" -ForegroundColor Yellow
        Write-Host "         Non-fatal; uninstall.bat still works." -ForegroundColor Yellow
    }
}


# =============================================================================
# 19. WRITE VERSION STAMP
# =============================================================================
$VersionFile = "$BaseDir\VERSION"

# -TexLiveScheme describes what THIS run installed. A mode that installs no TeX
# Live must not overwrite the record with its own parameter default: repair an
# install made with -TexLiveScheme basic and the stamp would flip to "full",
# after which the Doctor's missing-package report would stop mentioning the
# scheme that actually explains it. Keep what the installing run wrote.
$StampedScheme = $TexLiveScheme
if (-not $InstallComponents) {
    $PriorScheme = Get-StampedValue -VersionFile $VersionFile -Key "texlive_scheme"
    if ($PriorScheme) { $StampedScheme = $PriorScheme }
}

$VersionContent = @"
installer_version=$InstallerVersion
installed_at=$(Get-Date -Format 'o')
texlib_root=$TeXLibDir
sublime_dir=$SublimeDir
sumatra_dir=$SumatraDir
texlive_dir=$TexLiveDir
using_onedrive=$UsingOneDrive
texlive_scheme=$StampedScheme
last_mode=$(if ($Repair) { 'repair' } elseif ($OnlyTeXLib) { 'only-texlib' } else { 'full' })
"@
Set-Content -Path $VersionFile -Value $VersionContent -Encoding UTF8
Write-Host "  Wrote $VersionFile" -ForegroundColor Gray

# --- Install manifest --------------------------------------------------------
# A hash per file this installer authored, so `install-console.bat -Verify` can later
# answer "is this still what was installed?" -- the question behind every build
# that used to work and now doesn't. Cheap: TeX Live is excluded, so this is
# tens of MB, not gigabytes.
$ManifestFile = "$BaseDir\MANIFEST"
try {
    $ManifestRelPaths = Get-ManifestPath -Root $BaseDir
    $ManifestLines = New-Object System.Collections.Generic.List[string]
    foreach ($Rel in $ManifestRelPaths) {
        $Full = Join-Path $BaseDir $Rel
        try {
            $h = (Get-FileHash -LiteralPath $Full -Algorithm SHA256 -ErrorAction Stop).Hash
            $ManifestLines.Add("$h  $Rel")
        } catch { $null = $_ }   # vanished mid-walk: not worth failing an install over
    }
    Set-Content -Path $ManifestFile -Value $ManifestLines -Encoding UTF8
    Write-Host "  Wrote $ManifestFile ($($ManifestLines.Count) files; TeX Live excluded)" -ForegroundColor Gray
} catch {
    Write-Host "  [warn] Could not write the install manifest: $_" -ForegroundColor Yellow
}


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

        # Can Ctrl+B resolve the TeXLib classes? The hello.tex compile above
        # says only that LaTeX runs -- it is a plain `article` and would pass on
        # a machine where not one TeXLib document builds, which is exactly what
        # 0.10.1 shipped. What actually has to hold is that the TEXINPUTS
        # written into TeXLib.sublime-settings resolves the library's classes,
        # so ask kpsewhich under precisely that TEXINPUTS. Cheap (one call), and
        # it fails in the same place a user's first Ctrl+B would.
        $Kpse = "$TexBinPath\kpsewhich.exe"
        $LibClasses = @(Get-ChildItem -LiteralPath $TeXLibDir -Filter "*.cls" -Recurse -Depth 1 -ErrorAction SilentlyContinue |
                        Where-Object { $_.DirectoryName -notlike "*\Sublime*" } |
                        Select-Object -ExpandProperty Name -Unique)
        if (-not $TeXLibTexInputsEnv) {
            Write-Host "  [note] TeXLib.sublime-settings is yours to manage; skipping the class-resolution check" -ForegroundColor Gray
        } elseif ((Test-Path $Kpse) -and $LibClasses.Count -gt 0) {
            $PrevTexInputs = $env:TEXINPUTS
            $PrevEap2 = $ErrorActionPreference
            $env:TEXINPUTS = $TeXLibTexInputsEnv
            $ErrorActionPreference = 'Continue'   # kpsewhich exits 1 on any miss
            try { $KpseFound = @(& $Kpse @LibClasses) } catch { $KpseFound = @() } finally {
                $ErrorActionPreference = $PrevEap2
                if ($null -eq $PrevTexInputs) { Remove-Item Env:TEXINPUTS -ErrorAction SilentlyContinue }
                else { $env:TEXINPUTS = $PrevTexInputs }
            }
            $ResolvedNames = @($KpseFound | ForEach-Object { Split-Path $_ -Leaf })
            $UnresolvedCls = @($LibClasses | Where-Object { $ResolvedNames -notcontains $_ })
            if ($UnresolvedCls.Count -eq 0) {
                Write-Host "  [OK] All $($LibClasses.Count) TeXLib classes resolve on the build TEXINPUTS -- Ctrl+B will find them" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] $($UnresolvedCls.Count) TeXLib class(es) do NOT resolve: $($UnresolvedCls -join ', ')" -ForegroundColor Red
                Write-Host "         Ctrl+B will fail with `"File ``<name>.cls' not found`" on those documents." -ForegroundColor Yellow
                Write-Host "         TEXINPUTS used: $TeXLibTexInputsEnv" -ForegroundColor Gray
                Write-Host "         Check `"texinputs`" in $UserDir\TeXLib.sublime-settings" -ForegroundColor Gray
            }
        } else {
            # Say why, rather than vanishing. A check that silently does nothing
            # reads as a check that passed: CI's full-install job deployed an
            # 8-file stub library with no .cls in it, this branch was taken, and
            # nothing in the log distinguished that from a clean 9-of-9 result.
            $WhyNoCheck = if (-not (Test-Path $Kpse)) {
                "kpsewhich not found at $Kpse"
            } elseif ($LibClasses.Count -eq 0) {
                "no .cls files found in $TeXLibDir -- is the library complete?"
            } else {
                "no TEXINPUTS was written this run"
            }
            Write-Host "  [WARN] Could not check that TeXLib classes resolve: $WhyNoCheck" -ForegroundColor Yellow
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
if ($Repair) {
    Write-Host "   TeXLib configuration repaired (installer v$InstallerVersion)   " -ForegroundColor Green
} elseif ($OnlyTeXLib) {
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
    Write-Host "  2. Everything Sublime needs is already installed and pinned. If you want" -ForegroundColor Gray
    Write-Host "     Package Control for packages of your own, install it yourself the usual" -ForegroundColor Gray
    Write-Host "     way -- nothing here gets in its way." -ForegroundColor Gray
    Write-Host "  3. If .tex / .pdf don't open with the right app, Right Click -> Open With" -ForegroundColor Gray
    Write-Host "     -> Choose Another App -> 'Always use this app'. Windows sometimes" -ForegroundColor Gray
    Write-Host "     refuses to honor the registry defaults on the first try. The TeXLib" -ForegroundColor Gray
    Write-Host "     entries are the ones labelled 'Sublime Text (TeXLib)' and" -ForegroundColor Gray
    Write-Host "     'SumatraPDF (TeXLib)'." -ForegroundColor Gray
    Write-Host ""
}
Write-Host "Troubleshooting:    tools\install-console.bat -Doctor" -ForegroundColor Cyan
Write-Host "Issues:             $InstallerRepo/issues"          -ForegroundColor Cyan
Write-Host ""

Stop-Installer 0
