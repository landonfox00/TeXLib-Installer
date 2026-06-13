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
    — no network calls (unless combined with non-silent update check).

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
    Apply the +h (hidden) file attribute to the %USERPROFILE%\TeXLib junction
    that gets created when your OneDrive path contains a space or comma (e.g.
    "OneDrive - University of Nevada, Reno"). Off by default — a visible
    junction is easier to discover and diagnose. Has no effect when no
    junction is needed.

.PARAMETER EnableBuildHotkey
    Also install the resident Explorer hotkey (Ctrl+B builds the selected .tex
    with no editor open). Off by default: every install gets the right-click
    "Build with TeXLib" menu, but the auto-starting background hook is opt-in
    so coworker installs stay lean and avoid antivirus questions about a
    login-launched background app. Compiles a small helper with the in-box
    .NET C# compiler and adds a Startup shortcut for the current user.

.PARAMETER VerifyDownloads
    Hash-rot canary. Download each pinned component and verify its SHA256/512
    against $Downloads, then exit — without installing anything, touching the
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
    [switch]$HideJunction,
    [switch]$EnableBuildHotkey,
    [switch]$VerifyDownloads
)

# =============================================================================
# 0. INSTALLER METADATA
# =============================================================================
$InstallerVersion = "0.5.0"
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
# script load — before the rest of the function definitions further down.
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
    # When launched via install.bat -> tools\install_wrapper.ps1, the wrapper
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
$ScriptDir  = $PSScriptRoot

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

# TeXLib bundle: this installer expects a sibling `texlib\` directory
# containing the TeXLib library snapshot. The release ZIP includes it.
$TexLibBundle = Join-Path $ScriptDir "texlib"

# Synced content location (OneDrive-aware detection).
$OneDrivePath = $env:OneDrive
if (-not $OneDrivePath) { $OneDrivePath = $env:OneDriveCommercial }
if (-not $OneDrivePath) { $OneDrivePath = $env:OneDriveConsumer }

if ($OneDrivePath -and (Test-Path "$OneDrivePath\Documents")) {
    $TeXLibDir = "$OneDrivePath\Documents\TeXLib"
    $UsingOneDrive = $true
} else {
    $TeXLibDir = "$env:USERPROFILE\Documents\TeXLib"
    $UsingOneDrive = $false
}

# --- User-root junction (TEXINPUTS-safe path) --------------------------------
# kpathsea (TeX Live's file resolver) splits TEXINPUTS on commas and chokes
# on spaces, so a OneDrive folder named "OneDrive - University of Nevada,
# Reno" silently breaks every TeX build. When the resolved path has either,
# we pipe it through a junction at %USERPROFILE%\TeXLib and reassign
# $TeXLibDir to the clean path so every downstream consumer (settings
# template, deploy target, version stamp, doctor) sees a sane location.
# Idempotent across re-runs; not touched in Doctor/Version/DryRun modes.
$UserRootJunction       = "$env:USERPROFILE\TeXLib"
$UserRootJunctionTarget = $TeXLibDir
$NeedsUserRootJunction  = $UsingOneDrive -and ($TeXLibDir -match '[ ,]')
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
            Write-Host "       the comma/space-bearing OneDrive path. Move or rename the existing" -ForegroundColor Red
            Write-Host "       folder (it looks like a real directory you created yourself) and" -ForegroundColor Red
            Write-Host "       re-run the installer." -ForegroundColor Red
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
function Test-LatestVersion {
    # Best-effort GitHub API check. Never fatal — print the result and move on.
    try {
        $resp = Invoke-RestMethod -Uri $ReleasesApi -TimeoutSec 5 -ErrorAction Stop
        $latest = $resp.tag_name -replace '^v', ''
        if ($latest -and ($latest -ne $InstallerVersion)) {
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
    Write-Host "TeXLib Doctor — diagnostic report" -ForegroundColor Cyan
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
        Stop-Installer 0
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

    if (Test-Path $TeXLibDir) {
        $CoreFiles = @("course-metadata.sty", "texlib-build.sty", "basic-utilities.sty")
        $MissingCore = $CoreFiles | Where-Object { -not (Test-Path (Join-Path $TeXLibDir $_)) }
        if ($MissingCore.Count -eq 0) {
            _Pass "TeXLib library at $TeXLibDir (core .sty files present)"
        } else {
            _Warn "TeXLib library at $TeXLibDir but missing: $($MissingCore -join ', ')"
        }
    } else {
        _Fail "TeXLib library directory $TeXLibDir does not exist"
    }

    # User-root junction (created when OneDrive path contains a space or comma).
    if ($NeedsUserRootJunction) {
        if ($UserRootJunctionState -eq "present") {
            _Pass "User-root junction $UserRootJunction -> $UserRootJunctionTarget (TEXINPUTS-safe)"
        } elseif ($UserRootJunctionState -eq "blocked") {
            _Fail "$UserRootJunction exists but is NOT a junction; TeX commands will fail because the OneDrive path contains a space/comma. Move or rename the folder and re-run the installer."
        } else {
            _Fail "OneDrive path contains a space/comma but $UserRootJunction junction is missing. Re-run the installer to create it."
        }
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
    Stop-Installer 0
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

# --- External-install detection -----------------------------------------------
# Phase A: detect-and-report only. Findings are informational; the installer
# still always installs portable copies of every component. Future versions
# may opt to reuse detected externals (TeX Live + Sumatra are the realistic
# candidates; Sublime needs config modifications either way so an isolated
# copy is the right call).

function Find-ExistingSublime {
    # App Paths registry (set by Sublime's official installer).
    $appPaths = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\sublime_text.exe"
    if (Test-Path $appPaths) {
        $p = (Get-ItemProperty -Path $appPaths -Name "(default)" -ErrorAction SilentlyContinue)."(default)"
        if ($p -and (Test-Path $p) -and ($p -notlike "$BaseDir*")) { return $p }
    }
    # Sublime's own install key.
    foreach ($hive in @("HKLM:\SOFTWARE\Sublime Text", "HKCU:\SOFTWARE\Sublime Text")) {
        if (Test-Path $hive) {
            $base = (Get-ItemProperty -Path $hive -Name "(default)" -ErrorAction SilentlyContinue)."(default)"
            if ($base) {
                $exe = Join-Path $base "sublime_text.exe"
                if ((Test-Path $exe) -and ($exe -notlike "$BaseDir*")) { return $exe }
            }
        }
    }
    # Common install locations.
    $candidates = @(
        "$env:ProgramFiles\Sublime Text\sublime_text.exe",
        "${env:ProgramFiles(x86)}\Sublime Text\sublime_text.exe",
        "$env:ProgramFiles\Sublime Text 3\sublime_text.exe",
        "$env:LOCALAPPDATA\Programs\Sublime Text\sublime_text.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c) -and ($c -notlike "$BaseDir*")) { return $c }
    }
    # PATH.
    $cmd = Get-Command sublime_text -ErrorAction SilentlyContinue
    if ($cmd -and ($cmd.Source -notlike "$BaseDir*")) { return $cmd.Source }
    return $null
}

function Find-ExistingSumatra {
    # App Paths registry.
    $appPaths = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\SumatraPDF.exe"
    if (Test-Path $appPaths) {
        $p = (Get-ItemProperty -Path $appPaths -Name "(default)" -ErrorAction SilentlyContinue)."(default)"
        if ($p -and (Test-Path $p) -and ($p -notlike "$BaseDir*")) { return $p }
    }
    # Common install locations.
    $candidates = @(
        "$env:ProgramFiles\SumatraPDF\SumatraPDF.exe",
        "${env:ProgramFiles(x86)}\SumatraPDF\SumatraPDF.exe",
        "$env:LOCALAPPDATA\SumatraPDF\SumatraPDF.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c) -and ($c -notlike "$BaseDir*")) { return $c }
    }
    # Versioned portable copies (e.g. SumatraPDF-3.5.2-64.exe) in LOCALAPPDATA\SumatraPDF.
    $portableDir = "$env:LOCALAPPDATA\SumatraPDF"
    if (Test-Path $portableDir) {
        $glob = Get-ChildItem -Path $portableDir -Filter "SumatraPDF*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($glob -and ($glob.FullName -notlike "$BaseDir*")) { return $glob.FullName }
    }
    return $null
}

function Find-ExistingTeXLive {
    # Returns @{ Path = 'C:\...\pdflatex.exe'; Year = '2024'; OnPath = $true/$false }
    # or $null. Excludes installs under $BaseDir.

    # PATH (most reliable signal that pdflatex is actually usable).
    $found = $null
    $onPath = $false
    $cmd = Get-Command pdflatex -ErrorAction SilentlyContinue
    if ($cmd -and ($cmd.Source -notlike "$BaseDir*")) {
        $found = $cmd.Source
        $onPath = $true
    }

    # Common TeX Live install roots, most recent year first.
    if (-not $found) {
        $years = @("2026", "2025", "2024", "2023", "2022")
        foreach ($y in $years) {
            foreach ($root in @("C:\texlive\$y\bin\windows", "$env:ProgramFiles\texlive\$y\bin\windows")) {
                $candidate = Join-Path $root "pdflatex.exe"
                if ((Test-Path $candidate) -and ($candidate -notlike "$BaseDir*")) {
                    $found = $candidate
                    break
                }
            }
            if ($found) { break }
        }
    }

    if (-not $found) { return $null }

    # Parse TL year from pdflatex --version output.
    $year = "unknown"
    try {
        $verOut = & $found --version 2>$null | Out-String
        if ($verOut -match "TeX Live (\d{4})") { $year = $matches[1] }
        elseif ($verOut -match "MiKTeX")       { return $null }  # handled separately
    } catch {
        # Couldn't run it; report path only.
    }

    return @{ Path = $found; Year = $year; OnPath = $onPath }
}

function Find-ExistingMiKTeX {
    # Common install locations for both per-machine and per-user MiKTeX.
    $candidates = @(
        "$env:ProgramFiles\MiKTeX\miktex\bin\x64\pdflatex.exe",
        "${env:ProgramFiles(x86)}\MiKTeX\miktex\bin\x64\pdflatex.exe",
        "$env:LOCALAPPDATA\Programs\MiKTeX\miktex\bin\x64\pdflatex.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    # If pdflatex on PATH reports MiKTeX, count that too.
    $cmd = Get-Command pdflatex -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $verOut = & $cmd.Source --version 2>$null | Out-String
            if ($verOut -match "MiKTeX") { return $cmd.Source }
        } catch {}
    }
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

# 7c. Disk space — skip the 6GB check in -OnlyTeXLib mode (bundle is tiny).
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
# HEAD request against the CTAN mirror — confirms TLS reachability without
# pulling any payload. Test-NetConnection would also work but trips
# PSScriptAnalyzer's "hardcoded ComputerName" rule (false positive for a
# public mirror).
if (-not $OnlyTeXLib) {
    try {
        $null = Invoke-WebRequest -Uri "https://mirror.ctan.org/" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Add-PreflightOK "Internet connectivity to mirror.ctan.org (HTTPS)"
    } catch {
        Add-PreflightFailure "Cannot reach https://mirror.ctan.org/ ($($_.Exception.Message)); check your internet connection / firewall / VPN"
    }
} else {
    Add-PreflightOK "Skipping internet check (-OnlyTeXLib doesn't download anything)"
}

# 7e. Detect existing TeX Live (or our own prior install).
$OurTex = Get-Command pdflatex -ErrorAction SilentlyContinue
if ($OurTex -and ($OurTex.Source -like "$BaseDir*")) {
    Add-PreflightOK "Existing TeXLib install detected at $($OurTex.Source) (Skip/Reinstall prompt below)"
} else {
    $extTL = Find-ExistingTeXLive
    $extMK = Find-ExistingMiKTeX
    if ($extTL) {
        Add-PreflightOK "TeX Live $($extTL.Year) detected at $($extTL.Path)"
        Add-PreflightNote "(still installing our own TL 2025 in this version; future -UseSystemTeX flag will let you reuse it without re-downloading)"
    } elseif ($extMK) {
        Add-PreflightOK "MiKTeX detected at $extMK"
        Add-PreflightNote "(will install our own TL 2025 alongside; MiKTeX and TeX Live coexist fine, PATH order will favor whichever was added last)"
    } else {
        Add-PreflightOK "No existing TeX distribution detected; will install TL 2025"
    }
}

# 7f. Detect existing Sublime Text.
$extSublime = Find-ExistingSublime
if ($extSublime) {
    Add-PreflightOK "Sublime Text detected at $extSublime"
    Add-PreflightNote "(installing isolated portable copy under $SublimeDir; your existing Sublime is not modified, and our texlib_builder plugin is scoped to the portable install)"
} else {
    Add-PreflightOK "No existing Sublime Text detected; will install portable copy"
}

# 7g. Detect existing SumatraPDF.
$extSumatra = Find-ExistingSumatra
if ($extSumatra) {
    Add-PreflightOK "SumatraPDF detected at $extSumatra"
    Add-PreflightNote "(still installing our own portable copy in this version; future -UseSystemSumatra flag will let you reuse it)"
} else {
    Add-PreflightOK "No existing SumatraPDF detected; will install portable copy"
}

# 7h. OneDrive enrollment.
if ($UsingOneDrive) {
    Add-PreflightOK "OneDrive detected at $OneDrivePath; TeXLib will sync via $UserRootJunctionTarget"
    if ($NeedsUserRootJunction) {
        switch ($UserRootJunctionState) {
            "present"     { Add-PreflightNote "(using existing junction $UserRootJunction so TeX can resolve the space/comma-bearing OneDrive path)" }
            "will-create" { Add-PreflightNote "(will create junction $UserRootJunction so TeX can resolve the space/comma-bearing OneDrive path)" }
            "blocked"     { Add-PreflightFailure "$UserRootJunction exists as a real folder, not a junction. Move or rename it and re-run." }
        }
    }
} else {
    Add-PreflightWarning "OneDrive not detected; TeXLib will live at $TeXLibDir (no multi-machine sync)"
}

# 7i. TeXLib bundle is present (always required, even in -OnlyTeXLib).
if (Test-Path $TexLibBundle) { Add-PreflightOK "TeXLib bundle found at $TexLibBundle" }
else                         { Add-PreflightFailure "TeXLib bundle not found at $TexLibBundle; were you running the installer from a partial download?" }

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
    Write-Host "DRY RUN — would do:" -ForegroundColor Yellow
    if ($NeedsUserRootJunction) {
        if ($UserRootJunctionState -eq "present") {
            Write-Host "  * Reuse existing user-root junction $UserRootJunction -> $UserRootJunctionTarget" -ForegroundColor Gray
        } elseif ($UserRootJunctionState -eq "blocked") {
            Write-Host "  * ABORT: $UserRootJunction exists but is not a junction (would block install)" -ForegroundColor Yellow
        } else {
            Write-Host "  * Create user-root junction $UserRootJunction -> $UserRootJunctionTarget (TEXINPUTS-safe path)" -ForegroundColor Gray
        }
    }
    if ($OnlyTeXLib) {
        Write-Host "  * Deploy TeXLib bundle from $TexLibBundle to $TeXLibDir" -ForegroundColor Gray
        Write-Host "  * Refresh texlib_builder.py + TeXLib.sublime-build in Packages\User" -ForegroundColor Gray
        Write-Host "  * Write $BaseDir\VERSION" -ForegroundColor Gray
    } else {
        Write-Host "  * Install Sublime Text to $SublimeDir" -ForegroundColor Gray
        Write-Host "  * Install SumatraPDF to $SumatraDir"   -ForegroundColor Gray
        Write-Host "  * Install TeX Live to $TexLiveDir (30-60 min)" -ForegroundColor Gray
        Write-Host "  * Deploy TeXLib bundle from $TexLibBundle to $TeXLibDir" -ForegroundColor Gray
        Write-Host "  * Add $TexBinPath to user PATH" -ForegroundColor Gray
        Write-Host "  * Junction $SublimeDir\Data\Packages\User -> $SublimeUserSync" -ForegroundColor Gray
        Write-Host "  * Write LaTeXTools / Preferences / SumatraPDF settings" -ForegroundColor Gray
        Write-Host "  * Register .tex .cls .sty .bib .pdf file associations (HKCU)" -ForegroundColor Gray
        Write-Host "  * Create Desktop + Start Menu shortcuts" -ForegroundColor Gray
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
        Write-Host "Creating TeXLib in Documents..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $TeXLibDir | Out-Null
    }

    # Stash the installer scripts so the user can re-run / uninstall / doctor later.
    Copy-Item "$ScriptDir\install.ps1"   "$ScriptsDir\install.ps1"   -Force
    if (Test-Path "$ScriptDir\uninstall.ps1") {
        Copy-Item "$ScriptDir\uninstall.ps1" "$ScriptsDir\uninstall.ps1" -Force
    }
} catch {
    Write-Host "Failed to prepare directories: $_" -ForegroundColor Red
    Stop-Installer 2
}

# Backup whatever's already in TeXLib\Sublime before we touch anything.
Backup-SublimeSettings | Out-Null


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
Write-Host "Deploying TeXLib library..." -ForegroundColor Cyan

try {
    # Mirror the bundle into the TeXLib documents folder. We don't delete extra
    # files here (the user may have course materials sitting alongside the
    # library), only overwrite the library bits.
    Copy-Item "$TexLibBundle\*" $TeXLibDir -Recurse -Force -Exclude ".git", ".github"
    Write-Host "  Library deployed to $TeXLibDir" -ForegroundColor Green
} catch {
    Write-Host "TeXLib deploy failed: $_" -ForegroundColor Red
    Stop-Installer 7
}


# =============================================================================
# 14. CONFIGURE ENVIRONMENT (skipped in -OnlyTeXLib)
# =============================================================================
if (-not $OnlyTeXLib) {
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
# 16. CONFIGURE PROGRAMS  (always — -OnlyTeXLib still refreshes builder files)
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

    # 16b. Deploy the TeXLib custom builder + bundled spell-check dictionary.
    # Source of truth is the bundle. LaTeX.sublime-settings is a syntax-
    # scoped settings file shipping curated math added_words / ignored_words;
    # it stacks on top of the user's global Preferences.sublime-settings so
    # personal proper nouns (collaborators, lab jargon) still apply.
    $BundledSublimeDir = Join-Path $TexLibBundle "Sublime"
    if (Test-Path $BundledSublimeDir) {
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
# 17. REGISTER FILE ASSOCIATIONS (skipped in -OnlyTeXLib)
# =============================================================================
if (-not $OnlyTeXLib) {
    Write-Host ""
    Write-Host "Registering file associations..." -ForegroundColor Cyan

    function Register-TeXLibAssociation {
        param ($Ext, $ProgID, $Desc, $Exe, $Icon)
        $RegPath = "HKCU:\Software\Classes"
        if (-not (Test-Path "$RegPath\$ProgID")) { New-Item -Path "$RegPath\$ProgID" -Force | Out-Null }
        Set-ItemProperty -Path "$RegPath\$ProgID" -Name "(default)" -Value $Desc
        if ($Icon) {
            if (-not (Test-Path "$RegPath\$ProgID\DefaultIcon")) { New-Item -Path "$RegPath\$ProgID\DefaultIcon" -Force | Out-Null }
            Set-ItemProperty -Path "$RegPath\$ProgID\DefaultIcon" -Name "(default)" -Value $Icon
        }
        if (-not (Test-Path "$RegPath\$ProgID\shell\open\command")) { New-Item -Path "$RegPath\$ProgID\shell\open\command" -Force | Out-Null }
        Set-ItemProperty -Path "$RegPath\$ProgID\shell\open\command" -Name "(default)" -Value "`"$Exe`" `"%1`""
        if (-not (Test-Path "$RegPath\$Ext")) { New-Item -Path "$RegPath\$Ext" -Force | Out-Null }
        Set-ItemProperty -Path "$RegPath\$Ext" -Name "(default)" -Value $ProgID
    }

    try {
        $SublExe = "$SublimeDir\sublime_text.exe"
        $SublIcon = "$SublimeDir\sublime_text.exe,0"
        foreach ($Ext in @(".txt", ".tex", ".cls", ".sty", ".bib", ".sublime-project", ".sublime-workspace")) {
            Register-TeXLibAssociation -Ext $Ext -ProgID "TeXLib.SublimeFile" -Desc "Sublime Text File" -Exe $SublExe -Icon $SublIcon
        }
        $SumExe = "$SumatraDir\$($SumatraExeName)"
        $SumIcon = "$SumatraDir\$($SumatraExeName),0"
        Register-TeXLibAssociation -Ext ".pdf" -ProgID "TeXLib.SumatraPDF" -Desc "SumatraPDF Document" -Exe $SumExe -Icon $SumIcon
        Write-Host "  Registered .tex .cls .sty .bib .pdf and friends" -ForegroundColor Green
    } catch {
        Write-Host "File-association registration failed: $_" -ForegroundColor Red
        Write-Host "  (Non-fatal; you can set defaults manually via Right Click -> Open With.)" -ForegroundColor Yellow
    }
}


# =============================================================================
# 17b. BUILD-FROM-EXPLORER  (right-click menu always; Ctrl+B hotkey opt-in)
# =============================================================================
# Lets a .tex be built without opening an editor: a "Build with TeXLib" flyout
# on the .tex right-click menu (all modes), plus an optional resident Ctrl+B
# hotkey scoped to File Explorer. Both call runtime\texlib-build.ps1, a
# standalone port of the texlib_builder.py recipe. Script deploy + config
# refresh run in every mode (incl. -OnlyTeXLib) so the recipe stays current.
Write-Host ""
Write-Host "Configuring build-from-Explorer..." -ForegroundColor Cyan

try {
    $RuntimeSrc = Join-Path $ScriptDir "runtime"

    # --- Deploy the standalone builder + selection wrapper -------------------
    foreach ($f in @("texlib-build.ps1", "texlib-build-selected.ps1")) {
        $src = Join-Path $RuntimeSrc $f
        if (Test-Path $src) { Copy-Item $src $ScriptsDir -Force }
    }

    # --- Write the resolved-paths config the builder reads at runtime --------
    # $TeXLibDir here is already the comma-free (junction) path when one was
    # needed, so TEXINPUTS the builder derives from it is kpathsea-safe.
    function ConvertTo-Psd1String { param($s) "'" + ("$s" -replace "'", "''") + "'" }
    $TlPerlBin = "$TexLiveDir\tlpkg\tlperl\bin"
    $SumatraExe = "$SumatraDir\$($SumatraExeName)"
    $SublimeExe = "$SublimeDir\sublime_text.exe"
    $ConfigLines = @(
        "# texlib-build.config.psd1 -- written by TeXLib-Installer $InstallerVersion.",
        "# Paths the standalone Explorer builder (texlib-build.ps1) reads. Regenerated on install.",
        "@{",
        "    TexBin     = $(ConvertTo-Psd1String $TexBinPath)",
        "    TlPerlBin  = $(ConvertTo-Psd1String $TlPerlBin)",
        "    TexLibRoot = $(ConvertTo-Psd1String $TeXLibDir)",
        "    SumatraExe = $(ConvertTo-Psd1String $SumatraExe)",
        "    SublimeExe = $(ConvertTo-Psd1String $SublimeExe)",
        "    AuxMode    = '<<temp>>'",
        "}"
    )
    Set-Content -Path "$ScriptsDir\texlib-build.config.psd1" -Value $ConfigLines -Encoding UTF8
    Write-Host "  Deployed texlib-build.ps1 + config" -ForegroundColor Green

    # --- Register the right-click "Build with TeXLib" flyout on .tex --------
    # A per-user submenu via ExtendedSubCommandsKey (no admin, no COM handler).
    $PsExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $BuildScript = "$ScriptsDir\texlib-build.ps1"
    $StoreProgID = "TeXLib.BuildMenu"
    $StoreKey = "HKCU:\Software\Classes\$StoreProgID"
    $EntryKey = "HKCU:\Software\Classes\SystemFileAssociations\.tex\shell\TeXLibBuild"

    # Rebuild from clean so removed or renamed modes do not linger.
    Remove-Item $StoreKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $EntryKey -Recurse -Force -ErrorAction SilentlyContinue

    New-Item -Path $EntryKey -Force | Out-Null
    Set-ItemProperty -Path $EntryKey -Name "MUIVerb" -Value "Build with TeXLib"
    Set-ItemProperty -Path $EntryKey -Name "Icon" -Value "$SublimeExe,0"
    Set-ItemProperty -Path $EntryKey -Name "ExtendedSubCommandsKey" -Value $StoreProgID

    # Ordered by key name (Explorer sorts alphabetically), so prefix NN_.
    $Modes = @(
        @{ Key = "01_build";       Label = "Build";          Mode = "default" }
        @{ Key = "02_key";         Label = "Answer Key";     Mode = "key" }
        @{ Key = "03_solutions";   Label = "Solutions";      Mode = "solutions" }
        @{ Key = "04_student";     Label = "Student Copy";   Mode = "student" }
        @{ Key = "05_rubric";      Label = "Rubric";         Mode = "rubric" }
        @{ Key = "06_draft";       Label = "Draft";          Mode = "draft" }
        @{ Key = "07_allversions"; Label = "All Versions";   Mode = "allversions" }
    )
    foreach ($m in $Modes) {
        $verbKey = "$StoreKey\shell\$($m.Key)"
        $cmdKey = "$verbKey\command"
        New-Item -Path $cmdKey -Force | Out-Null
        Set-ItemProperty -Path $verbKey -Name "(default)" -Value $m.Label
        $cmd = '"' + $PsExe + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ' +
               '-File "' + $BuildScript + '" -Path "%1" -Mode ' + $m.Mode
        Set-ItemProperty -Path $cmdKey -Name "(default)" -Value $cmd
    }
    Write-Host "  Registered .tex right-click 'Build with TeXLib' menu" -ForegroundColor Green
} catch {
    Write-Host "  [warn] build-from-Explorer setup failed: $_" -ForegroundColor Yellow
    Write-Host "  (Non-fatal; editor builds are unaffected.)" -ForegroundColor Yellow
}

# --- Opt-in resident Ctrl+B hotkey (scoped to File Explorer) ----------------
if ($EnableBuildHotkey) {
    Write-Host "Installing Ctrl+B Explorer hotkey..." -ForegroundColor Cyan
    try {
        $CsSrc = Join-Path $RuntimeSrc "TeXLibHotkey.cs"
        $CsDest = "$ScriptsDir\TeXLibHotkey.cs"
        $ExeDest = "$ScriptsDir\TeXLibHotkey.exe"
        if (-not (Test-Path $CsSrc)) { throw "runtime\TeXLibHotkey.cs not found in the installer bundle." }
        Copy-Item $CsSrc $CsDest -Force

        # Find the in-box .NET Framework C# compiler (present on all Win10/11).
        $Csc = @(
            "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
            "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $Csc) { throw "csc.exe (.NET Framework compiler) not found." }

        # Stop any running instance so we can overwrite the exe.
        Get-Process -Name "TeXLibHotkey" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        & $Csc /nologo /target:winexe /out:"$ExeDest" "$CsDest" | Out-Null
        if (-not (Test-Path $ExeDest)) { throw "compilation produced no exe." }

        # Auto-start at login via a Startup-folder shortcut.
        $StartupDir = [Environment]::GetFolderPath("Startup")
        $WS = New-Object -ComObject WScript.Shell
        $Lnk = $WS.CreateShortcut("$StartupDir\TeXLib Build Hotkey.lnk")
        $Lnk.TargetPath = $ExeDest
        $Lnk.WorkingDirectory = $ScriptsDir
        $Lnk.Description = "TeXLib: Ctrl+B builds the selected .tex in File Explorer"
        $Lnk.Save()

        # Launch now so it works without a reboot (mutex guards against dupes).
        Start-Process -FilePath $ExeDest | Out-Null
        Write-Host "  Hotkey active: select a .tex in Explorer and press Ctrl+B" -ForegroundColor Green
    } catch {
        Write-Host "  [warn] could not install the Ctrl+B hotkey: $_" -ForegroundColor Yellow
        Write-Host "  (The right-click 'Build with TeXLib' menu still works.)" -ForegroundColor Yellow
    }
}


# =============================================================================
# 18. SHORTCUTS (skipped in -OnlyTeXLib)
# =============================================================================
if (-not $OnlyTeXLib) {
    Write-Host ""
    Write-Host "Creating shortcuts..." -ForegroundColor Cyan

    function New-DesktopAndStartMenuShortcut {
        param ($SourceExe, $ShortcutName)
        try {
            $WS = New-Object -ComObject WScript.Shell
            $DesktopPath = [Environment]::GetFolderPath("Desktop")
            $StartMenuPath = [Environment]::GetFolderPath("StartMenu") + "\Programs"
            foreach ($Target in @("$DesktopPath\$ShortcutName.lnk", "$StartMenuPath\$ShortcutName.lnk")) {
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
    Write-Host "     refuses to honor the registry defaults on the first try." -ForegroundColor Gray
    Write-Host ""
}
Write-Host "Troubleshooting:    install.bat -Doctor"            -ForegroundColor Cyan
Write-Host "Issues:             $InstallerRepo/issues"          -ForegroundColor Cyan
Write-Host ""

Stop-Installer 0
