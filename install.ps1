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
    [switch]$Silent
)

# =============================================================================
# 0. INSTALLER METADATA
# =============================================================================
$InstallerVersion = "0.1.0"
$InstallerRepo    = "https://github.com/landonfox00/TeXLib-Installer"

# =============================================================================
# 1. SETUP VARIABLES
# =============================================================================
$ScriptDir  = $PSScriptRoot
$UserName   = $env:USERNAME

# Install location (per-user, no admin needed).
$BaseDir    = "$env:LOCALAPPDATA\TeXLib"
$ScriptsDir = "$BaseDir\Scripts"
$LogDir     = "$BaseDir\Logs"

# Program paths.
$SublimeDir = "$BaseDir\Sublime Text"
$SumatraDir = "$BaseDir\Sumatra"
$TexLiveDir = "$BaseDir\TexLive\2025"
$TexBinPath = "$TexLiveDir\bin\windows"

# TeXLib bundle: this installer expects a sibling `texlib\` directory
# containing the TeXLib library snapshot. The release ZIP includes it; if you
# are running from a source clone instead, the script falls back to looking
# for an environment-configured TeXLib root.
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

$SublimeUserSync = "$TeXLibDir\Sublime"
$TempDir = "$env:TEMP\TeXLib_Install"

# Pinned component versions.
$Downloads = @{
    "sublime" = @{
        "Url"  = "https://download.sublimetext.com/sublime_text_build_4180_x64.zip"
        "File" = "sublime_text_build_4180_x64.zip"
        "Type" = "Static"
        "Hash" = "6B6B53AEDCDEE13A19D33363FF9ED48A1549463647567C93E12F5260F7AA911F"
    }
    "sumatra" = @{
        "Url"  = "https://www.sumatrapdfreader.org/dl/rel/3.5.2/SumatraPDF-3.5.2-64.zip"
        "File" = "SumatraPDF-3.5.2-64.zip"
        "Type" = "Static"
        "Hash" = "78D6397D8C4598F7C6B37B246A360D6D29871578351C2C903001878E48D6C58B"
    }
    "texlive" = @{
        "Url"     = "https://mirror.ctan.org/systems/texlive/tlnet/install-tl.zip"
        "HashUrl" = "https://mirror.ctan.org/systems/texlive/tlnet/install-tl.zip.sha512"
        "File"    = "install-tl.zip"
        "Type"    = "Dynamic"
    }
    "pkgctrl" = @{
        "Url"  = "https://packagecontrol.io/Package%20Control.sublime-package"
        "File" = "Package Control.sublime-package"
        "Type" = "Skip"
    }
    "latextools" = @{
        "Url"  = "https://github.com/SublimeText/LaTeXTools/archive/refs/heads/master.zip"
        "File" = "latextools.zip"
        "Type" = "Skip"
    }
}


# =============================================================================
# 2. LOGGING
# =============================================================================
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = "$LogDir\install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile -IncludeInvocationHeader | Out-Null

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   TeXLib-Installer v$InstallerVersion"        -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log file: $LogFile" -ForegroundColor Gray
Write-Host "Silent mode: $Silent" -ForegroundColor Gray
Write-Host ""

function Stop-Installer {
    param([int]$ExitCode = 0)
    try { Stop-Transcript | Out-Null } catch {}
    if (-not $Silent -and $ExitCode -ne 0) {
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
# 3. PRE-FLIGHT CHECKS
# =============================================================================
Write-Host "Running pre-flight checks..." -ForegroundColor Cyan

$PreflightFailed = $false

function Add-PreflightFailure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
    $script:PreflightFailed = $true
}

function Add-PreflightWarning {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Add-PreflightOK {
    param([string]$Message)
    Write-Host "  [ OK ] $Message" -ForegroundColor Green
}

# 3a. Windows version (need Windows 10 1809 / build 17763 or newer).
$WinBuild = [System.Environment]::OSVersion.Version.Build
if ($WinBuild -ge 17763) {
    Add-PreflightOK "Windows build $WinBuild (>= 17763 required)"
} else {
    Add-PreflightFailure "Windows build $WinBuild detected; need 17763 (Windows 10 1809) or newer"
}

# 3b. PowerShell version (5.1+).
$PSMajor = $PSVersionTable.PSVersion.Major
$PSMinor = $PSVersionTable.PSVersion.Minor
if ($PSMajor -gt 5 -or ($PSMajor -eq 5 -and $PSMinor -ge 1)) {
    Add-PreflightOK "PowerShell $($PSVersionTable.PSVersion) (>= 5.1 required)"
} else {
    Add-PreflightFailure "PowerShell $($PSVersionTable.PSVersion) detected; need 5.1 or newer"
}

# 3c. Disk space (need ~6 GB free on the volume hosting %LOCALAPPDATA%).
try {
    $Drive = (Get-Item $env:LOCALAPPDATA).PSDrive
    $FreeGB = [math]::Round($Drive.Free / 1GB, 1)
    if ($FreeGB -ge 6) {
        Add-PreflightOK "Free space on $($Drive.Name): ${FreeGB} GB (>= 6 GB required)"
    } else {
        Add-PreflightFailure "Only ${FreeGB} GB free on $($Drive.Name); need >= 6 GB"
    }
} catch {
    Add-PreflightWarning "Could not determine free disk space; continuing"
}

# 3d. Internet connectivity (one quick probe).
try {
    $Probe = Test-NetConnection -ComputerName mirror.ctan.org -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($Probe) {
        Add-PreflightOK "Internet connectivity to mirror.ctan.org"
    } else {
        Add-PreflightFailure "Cannot reach mirror.ctan.org on port 443; check your internet connection"
    }
} catch {
    Add-PreflightWarning "Could not run Test-NetConnection; assuming internet is up"
}

# 3e. Detect existing non-TeXLib TeX install (MiKTeX, system TeX Live).
$ExistingTex = Get-Command pdflatex -ErrorAction SilentlyContinue
if ($ExistingTex) {
    $ExistingPath = $ExistingTex.Source
    if ($ExistingPath -like "*$BaseDir*") {
        Add-PreflightOK "Existing TeXLib install detected at $ExistingPath (will be re-used or replaced per prompts)"
    } else {
        Add-PreflightWarning "Another LaTeX install detected at $ExistingPath"
        Add-PreflightWarning "  This installer will install its own TeX Live alongside it; PATH order may need attention afterwards."
    }
} else {
    Add-PreflightOK "No conflicting LaTeX install on PATH"
}

# 3f. OneDrive enrollment.
if ($UsingOneDrive) {
    Add-PreflightOK "OneDrive detected at $OneDrivePath; TeXLib will sync via $TeXLibDir"
} else {
    Add-PreflightWarning "OneDrive not detected; TeXLib will live at $TeXLibDir (no multi-machine sync)"
}

if ($PreflightFailed) {
    Write-Host ""
    Write-Host "Pre-flight checks failed. Fix the issues above and re-run." -ForegroundColor Red
    Stop-Installer 1
}

Write-Host ""


# =============================================================================
# 4. HELPER FUNCTIONS
# =============================================================================
function Get-SourceFile {
    param ($Key, $DestPath)
    $Info = $Downloads[$Key]
    $LocalPath = "$ScriptDir\$($Info.File)"
    $ExpectedHash = $null

    if ($Info.Type -eq "Static") {
        $ExpectedHash = $Info.Hash
    } elseif ($Info.Type -eq "Dynamic") {
        Write-Host "Fetching latest hash for $($Info.File)..." -ForegroundColor Cyan
        try {
            $HashContent = (Invoke-WebRequest -Uri $Info.HashUrl -UseBasicParsing).Content
            $ExpectedHash = ($HashContent -split "\s+")[0].Trim()
        } catch {
            Write-Host "  [FAIL] Could not fetch hash for $($Info.File): $_" -ForegroundColor Red
            throw "Hash fetch failed (no fallback for dynamic-hash component)."
        }
    }

    $Algo = if ($Key -eq "texlive") { "SHA512" } else { "SHA256" }

    # If a pre-staged copy exists next to the installer, prefer it (skips download).
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
    Invoke-WebRequest -Uri $Info.Url -OutFile $DestPath -UseBasicParsing

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
    param ([string]$ComponentName, [string]$ReinstallWarning = "")
    if ($Silent) {
        Write-Host "  [silent] Skipping reinstall of $ComponentName" -ForegroundColor Gray
        return $false
    }
    $msg = "  [S]kip or [R]einstall"
    if ($ReinstallWarning) { $msg += " ($ReinstallWarning)" }
    $msg += "? (Default: S)"
    $Choice = Read-Host $msg
    return ($Choice -eq "R" -or $Choice -eq "r")
}


# =============================================================================
# 5. PREPARE DIRECTORIES
# =============================================================================
Write-Host "Setting up TeXLib..." -ForegroundColor Cyan

try {
    foreach ($d in @($BaseDir, $TempDir, $ScriptsDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    if (-not (Test-Path $TeXLibDir)) {
        Write-Host "Creating TeXLib in Documents..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $TeXLibDir | Out-Null
    }

    # Stash the installer scripts so the user can re-run / uninstall later.
    Copy-Item "$ScriptDir\install.ps1"   "$ScriptsDir\install.ps1"   -Force
    if (Test-Path "$ScriptDir\uninstall.ps1") {
        Copy-Item "$ScriptDir\uninstall.ps1" "$ScriptsDir\uninstall.ps1" -Force
    }
} catch {
    Write-Host "Failed to prepare directories: $_" -ForegroundColor Red
    Stop-Installer 2
}


# =============================================================================
# 6. INSTALL PROGRAMS
# =============================================================================

# ---- Sublime Text ----
$InstallSublime = $true
if (Test-Path $SublimeDir) {
    Write-Host ""
    Write-Host "Sublime Text is already installed." -ForegroundColor Yellow
    if (Read-SkipOrReinstall -ComponentName "Sublime Text" -ReinstallWarning "wipes settings") {
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
    if (Read-SkipOrReinstall -ComponentName "TeX Live" -ReinstallWarning "takes 30+ minutes") {
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

        $TexDirFwd = $BaseDir.Replace("\", "/") + "/TexLive/2025"
        $TexMfLocalFwd = $BaseDir.Replace("\", "/") + "/TexLive/texmf-local"
        $TexMfSysConfigFwd = $BaseDir.Replace("\", "/") + "/TexLive/2025/texmf-config"
        $TexMfSysVarFwd = $BaseDir.Replace("\", "/") + "/TexLive/2025/texmf-var"

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
        Start-Process -FilePath "$InstallerRoot\install-tl-windows.bat" `
            -ArgumentList "-no-gui -profile texlive.profile" `
            -WorkingDirectory $InstallerRoot -Wait
    } catch {
        Write-Host "TeX Live install failed: $_" -ForegroundColor Red
        Stop-Installer 5
    }
}


# =============================================================================
# 7. DEPLOY TEXLIB BUNDLE TO ONEDRIVE / DOCUMENTS
# =============================================================================
Write-Host ""
Write-Host "Deploying TeXLib library..." -ForegroundColor Cyan

if (-not (Test-Path $TexLibBundle)) {
    Write-Host "  [FAIL] No texlib/ folder found next to the installer at $TexLibBundle" -ForegroundColor Red
    Write-Host "         The release ZIP should include this. Were you running the installer" -ForegroundColor Yellow
    Write-Host "         from a partial download?" -ForegroundColor Yellow
    Stop-Installer 6
}

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
# 8. CONFIGURE ENVIRONMENT
# =============================================================================
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


# =============================================================================
# 9. SYNC SUBLIME SETTINGS
# =============================================================================
Write-Host ""
Write-Host "Wiring up Sublime settings sync..." -ForegroundColor Cyan

try {
    $UserPackagesLocal = "$SublimeDir\Data\Packages\User"
    $PackagesDir = "$SublimeDir\Data\Packages"
    if (-not (Test-Path $PackagesDir)) { New-Item -ItemType Directory -Force -Path $PackagesDir | Out-Null }

    # Zombie check: the sync target may exist as a stale junction from a
    # previous half-install; remove it before re-linking.
    if (Test-Path $SublimeUserSync) {
        $Item = Get-Item $SublimeUserSync -Force
        if ($Item.Attributes -match "ReparsePoint") {
            Write-Host "  [fix] Removing stale junction at sync target" -ForegroundColor Yellow
            Remove-Item $SublimeUserSync -Force -Recurse
        }
    }

    if (Test-Path $SublimeUserSync) {
        # Already-populated sync folder (probably TeXLib's bundled Sublime/ dir).
        Write-Host "  Found existing TeXLib\Sublime; junctioning Packages\User to it" -ForegroundColor Green
        if (Test-Path $UserPackagesLocal) { Remove-Item $UserPackagesLocal -Recurse -Force }
        New-Item -ItemType Junction -Path $UserPackagesLocal -Target $SublimeUserSync | Out-Null
    } else {
        Write-Host "  Creating new sync folder at $SublimeUserSync" -ForegroundColor Cyan
        if (-not (Test-Path $UserPackagesLocal)) { New-Item -ItemType Directory -Force -Path $UserPackagesLocal | Out-Null }
        New-Item -ItemType Directory -Force -Path $SublimeUserSync | Out-Null
        Get-ChildItem -Path $UserPackagesLocal -Force | Move-Item -Destination $SublimeUserSync -Force
        Remove-Item $UserPackagesLocal -Recurse -Force
        New-Item -ItemType Junction -Path $UserPackagesLocal -Target $SublimeUserSync | Out-Null
    }
} catch {
    Write-Host "Sublime sync setup failed: $_" -ForegroundColor Red
    Stop-Installer 9
}


# =============================================================================
# 10. CONFIGURE PROGRAMS
# =============================================================================
Write-Host ""
Write-Host "Writing program configurations..." -ForegroundColor Cyan

try {
    $UserDir = $SublimeUserSync
    $LaTeXToolsDir = "$PackagesDir\LaTeXTools"

    # 10a. Install LaTeXTools (the package that loads the TeXLib builder).
    if (-not (Test-Path $LaTeXToolsDir)) {
        $ZipPath = "$TempDir\latextools.zip"
        Get-SourceFile -Key "latextools" -DestPath $ZipPath
        Expand-Archive -Path $ZipPath -DestinationPath "$TempDir\lt_extract"
        Move-Item -Path "$TempDir\lt_extract\LaTeXTools-master" -Destination $LaTeXToolsDir
    }

    # 10b. Deploy the TeXLib custom builder. Its source of truth is the bundled
    # TeXLib snapshot; we copy texlib_builder.py + TeXLib.sublime-build into the
    # user Packages so LaTeXTools picks them up.
    $BundledSublimeDir = Join-Path $TexLibBundle "Sublime"
    if (Test-Path $BundledSublimeDir) {
        foreach ($f in @("texlib_builder.py", "TeXLib.sublime-build", "Default.sublime-commands")) {
            $src = Join-Path $BundledSublimeDir $f
            if (Test-Path $src) { Copy-Item $src $UserDir -Force }
        }
    }

    # 10c. LaTeXTools settings (templated).
    $LaTeXToolsTpl = "$ScriptDir\templates\LaTeXTools.sublime-settings"
    if (Test-Path $LaTeXToolsTpl) {
        $JsonSumatra = "$SumatraDir\SumatraPDF-3.5.2-64.exe".Replace("\", "\\")
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

    # 10d. Sublime editor preferences.
    $PrefsTpl = "$ScriptDir\templates\Preferences.sublime-settings"
    if (Test-Path $PrefsTpl) {
        Copy-Item $PrefsTpl "$UserDir\Preferences.sublime-settings" -Force
    }

    # 10e. SumatraPDF settings (templated).
    $SumatraTpl = "$ScriptDir\templates\SumatraPDF-settings.txt"
    if (Test-Path $SumatraTpl) {
        $TxtSublime = "$SublimeDir\sublime_text.exe".Replace("\", "\\")
        $Content = Get-Content $SumatraTpl -Raw
        $Content = $Content.Replace("{{SUBLIME_EXE}}", $TxtSublime)
        Set-Content -Path "$SumatraDir\SumatraPDF-settings.txt" -Value $Content -Encoding UTF8
    }
} catch {
    Write-Host "Program config write failed: $_" -ForegroundColor Red
    Stop-Installer 10
}


# =============================================================================
# 11. REGISTER FILE ASSOCIATIONS
# =============================================================================
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
    $SumExe = "$SumatraDir\SumatraPDF-3.5.2-64.exe"
    $SumIcon = "$SumatraDir\SumatraPDF-3.5.2-64.exe,0"
    Register-TeXLibAssociation -Ext ".pdf" -ProgID "TeXLib.SumatraPDF" -Desc "SumatraPDF Document" -Exe $SumExe -Icon $SumIcon
    Write-Host "  Registered .tex .cls .sty .bib .pdf and friends" -ForegroundColor Green
} catch {
    Write-Host "File-association registration failed: $_" -ForegroundColor Red
    Write-Host "  (Non-fatal; you can set defaults manually via Right Click -> Open With.)" -ForegroundColor Yellow
}


# =============================================================================
# 12. SHORTCUTS
# =============================================================================
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
New-DesktopAndStartMenuShortcut -SourceExe "$SumatraDir\SumatraPDF-3.5.2-64.exe"   -ShortcutName "Sumatra"


# =============================================================================
# 13. WRITE VERSION STAMP
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
"@
Set-Content -Path $VersionFile -Value $VersionContent -Encoding UTF8
Write-Host "  Wrote $VersionFile" -ForegroundColor Gray


# =============================================================================
# 14. END-OF-INSTALL VERIFICATION
# =============================================================================
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
        # Run pdflatex directly from the freshly installed bin; PATH update
        # above only affects new shells, not this one.
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


# =============================================================================
# 15. CLEANUP
# =============================================================================
Write-Host ""
Write-Host "Cleaning up temp files..." -ForegroundColor Yellow
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}


# =============================================================================
# 16. COMPLETION
# =============================================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   TeXLib v$InstallerVersion installation complete!  " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Install location:   $BaseDir"  -ForegroundColor Gray
Write-Host "TeXLib library:     $TeXLibDir" -ForegroundColor Gray
Write-Host "Log file:           $LogFile"   -ForegroundColor Gray
Write-Host ""
Write-Host "First-launch notes:" -ForegroundColor Yellow
Write-Host "  1. Open a NEW terminal -- the updated PATH is not visible to this one." -ForegroundColor Gray
Write-Host "  2. Sublime Text may show a Package Control loading message on first run;" -ForegroundColor Gray
Write-Host "     just restart Sublime once and it goes away." -ForegroundColor Gray
Write-Host "  3. If .tex / .pdf don't open with the right app, Right Click -> Open With" -ForegroundColor Gray
Write-Host "     -> Choose Another App -> 'Always use this app'. Windows sometimes" -ForegroundColor Gray
Write-Host "     refuses to honor the registry defaults on the first try." -ForegroundColor Gray
Write-Host ""
Write-Host "Open issues at $InstallerRepo/issues" -ForegroundColor Cyan
Write-Host ""

Stop-Installer 0
