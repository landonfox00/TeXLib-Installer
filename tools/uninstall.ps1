<#
.SYNOPSIS
    TeXLib-Installer uninstall: reverses install.ps1.

.DESCRIPTION
    Removes the per-user TeXLib install (%LOCALAPPDATA%\TeXLib) -- Sublime Text,
    SumatraPDF, TeX Live and, as of 0.6.3, the TeXLib library itself, which now
    lives inside that same root. Also removes Desktop and Start Menu shortcuts,
    the PATH entry, and the file-association / "Open with" registry entries.

    Interactive runs confirm each component separately, so you can drop the
    editor and keep the 6 GB TeX Live tree (or the other way round). Every
    choice also has a switch, for unattended runs.

    A pre-0.6.3 library in Documents / OneDrive is NOT removed by default: at
    that location it sits among the user's own files. Pass -RemoveLibrary (or
    answer Y at the prompt) to delete it too.

.PARAMETER Silent
    Skip all interactive prompts. Removes the programs and leaves the library,
    the user-root junction, and any component named by a -Keep switch.

.PARAMETER InstallPath
    Uninstall an install rooted somewhere other than %LOCALAPPDATA%\TeXLib --
    the counterpart to install.ps1's -InstallPath.

.PARAMETER All
    Remove everything without per-component prompts: the programs, the TeXLib
    library wherever it lives, and the user-root junction. Implies
    -RemoveLibrary and -RemoveJunction.

.PARAMETER RemoveLibrary
    Also delete a TeXLib library that lives OUTSIDE the install root -- i.e. a
    pre-0.6.3 Documents\TeXLib, which is preserved by default because it may
    hold course materials the user parked alongside the library. A 0.6.3+
    library lives inside the install root and always goes with it; this switch
    is a no-op there.

.PARAMETER KeepSublime
    Leave the Sublime Text install in place.

.PARAMETER KeepSumatra
    Leave the SumatraPDF install in place.

.PARAMETER KeepTeXLive
    Leave the TeX Live tree in place. Worth considering: re-installing it costs
    30-60 minutes, and a later install.bat run detects it and offers to skip.

.PARAMETER Force
    Close running Sublime Text / SumatraPDF processes belonging to this install
    without asking. Without it, an interactive run prompts and a silent run
    closes them (they hold file locks that would otherwise fail the removal).

.PARAMETER RemoveJunction
    Remove the %USERPROFILE%\TeXLib junction even when this uninstaller cannot
    prove the installer created it. By default an unclaimed junction is left in
    place: a developer machine typically has one pointing at a real library, and
    silently unlinking it breaks every TeX build that resolves through that
    path. Use this only after checking where the junction actually points.

.NOTES
    Logs to %TEMP%\TeXLib-Uninstall\uninstall-<timestamp>.log -- deliberately
    outside the install root, which this script deletes while the transcript is
    still open.
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    [string]$InstallPath = "",
    [switch]$All,
    [switch]$RemoveLibrary,
    [switch]$KeepSublime,
    [switch]$KeepSumatra,
    [switch]$KeepTeXLive,
    [switch]$Force,
    [switch]$RemoveJunction
)

$UninstallerVersion = "0.6.3"   # keep in lockstep with install.ps1 $InstallerVersion
$InstallerRepo      = "https://github.com/landonfox00/TeXLib-Installer"

$BaseDir = if ($InstallPath) { $InstallPath } else { "$env:LOCALAPPDATA\TeXLib" }
# The log NEVER goes inside $BaseDir. Start-Transcript holds its file open for
# the whole run, and an open file inside the tree we are about to delete is what
# made every uninstall through 0.6.2 stop partway through: Remove-Item -Recurse
# walked the root in enumeration order, hit the locked Logs\uninstall-*.log, and
# aborted -- so Sublime Text, SumatraPDF and TeX Live, which come later in that
# order, were never touched. That is the "the uninstaller doesn't remove
# anything" report, and moving the log out of the way is the fix.
$LogDir  = "$env:TEMP\TeXLib-Uninstall"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = "$LogDir\uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile -IncludeInvocationHeader | Out-Null

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   TeXLib-Uninstaller v$UninstallerVersion"      -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log file: $LogFile" -ForegroundColor Gray
Write-Host ""

# -All is shorthand, resolved once here so nothing downstream has to remember
# which switches it stands in for.
if ($All) { $RemoveLibrary = $true; $RemoveJunction = $true }

function Stop-Uninstaller {
    param([int]$ExitCode = 0)
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    # tools\boot_wrapper.ps1 owns the prompt when present; see the
    # matching note in install.ps1's Stop-Installer.
    if (-not $Silent -and $ExitCode -ne 0 -and -not $env:TEXLIB_INSTALLER_WRAPPED) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    exit $ExitCode
}

function Get-StampedValue {
    # Read one `key=value` line out of the install's VERSION stamp. The stamp is
    # the authority on where things actually went: an install predating 0.6.3
    # put the library in Documents, and one made with -InstallPath put the
    # components somewhere this script would never guess.
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

function Get-ShellCommandExe {
    # Pull the executable out of a shell command. Two shapes turn up in the
    # wild, and only one of them is well behaved:
    #     "C:\path\app.exe" "%1"            -- quoted
    #     C:\Program Files\app.exe "%1"     -- UNQUOTED, spaces and all
    # Splitting the second on whitespace yields "C:\Program", which does not
    # exist -- so a naive parse declares a perfectly live app dead and this
    # script rips it out of the user's Open With lists. Match up to the FIRST
    # .exe instead, and keep first-token as a last resort.
    param([string]$Command)
    if (-not $Command) { return $null }
    if ($Command -match '^\s*"([^"]+)"')        { return $Matches[1] }
    if ($Command -match '^\s*(.*?\.exe)(\s|$)') { return $Matches[1] }
    if ($Command -match '^\s*(\S+)')            { return $Matches[1] }
    return $null
}

function Test-ShellCommandLive {
    # Does this shell command still name an executable that exists? Used to tell
    # OUR removed copy of Sublime / SumatraPDF apart from one the user installed
    # themselves: both share an exe name, but only ours is gone by this point.
    param([string]$RegKey)
    if (-not (Test-Path $RegKey)) { return $false }
    $cmd = $null
    try { $cmd = (Get-Item -Path $RegKey).GetValue("") } catch { $cmd = $null }
    $exe = Get-ShellCommandExe $cmd
    if (-not $exe) { return $false }
    return (Test-Path $exe)
}

function Read-YesNo {
    # Y/N prompt with an explicit default, honoured on a bare Enter. Silent runs
    # never reach it -- callers gate on $Silent -- but it returns the default if
    # they ever do, so a stray prompt can't hang an unattended uninstall.
    param([string]$Question, [bool]$DefaultYes = $true)
    if ($Silent) { return $DefaultYes }
    $Suffix = if ($DefaultYes) { "(Y/n)" } else { "(y/N)" }
    $Answer = Read-Host "$Question $Suffix"
    if (-not $Answer) { return $DefaultYes }
    return ($Answer.Trim() -match '^(y|yes)$')
}

# -----------------------------------------------------------------------------
# 0. Work out what this machine actually has, from the install's own stamp.
# -----------------------------------------------------------------------------
$VersionFile = "$BaseDir\VERSION"
$TexLiveYear = "2025"   # keep in lockstep with install.ps1 $TexLiveYear

$SublimeDir  = Get-StampedValue -VersionFile $VersionFile -Key "sublime_dir"
$SumatraDir  = Get-StampedValue -VersionFile $VersionFile -Key "sumatra_dir"
$TexLiveDir  = Get-StampedValue -VersionFile $VersionFile -Key "texlive_dir"
$TeXLibDir   = Get-StampedValue -VersionFile $VersionFile -Key "texlib_root"
if (-not $SublimeDir) { $SublimeDir = "$BaseDir\Sublime Text" }
if (-not $SumatraDir) { $SumatraDir = "$BaseDir\Sumatra" }
if (-not $TexLiveDir) { $TexLiveDir = "$BaseDir\TexLive\$TexLiveYear" }
if (-not $TeXLibDir)  { $TeXLibDir  = "$BaseDir\Library" }

# 0.6.3+ puts the library inside the install root, where it is a deployed
# artifact of the install rather than anything the user put there: it goes with
# the root, no prompt and no switch needed. A library OUTSIDE the root is a
# pre-0.6.3 layout in Documents / OneDrive, where the user may well have parked
# course materials alongside it -- that one is preserved unless asked for.
$LibraryInsideRoot = $TeXLibDir.TrimEnd('\').ToLowerInvariant().StartsWith(
                        $BaseDir.TrimEnd('\').ToLowerInvariant() + '\')
if ($LibraryInsideRoot) { $RemoveLibrary = $true }

# Quick check: anything to uninstall?
if (-not (Test-Path $BaseDir)) {
    Write-Host "Nothing to uninstall: $BaseDir does not exist." -ForegroundColor Yellow
    Write-Host "  (Will still clean up PATH entries, shortcuts, and registry keys in case of a partial prior install.)" -ForegroundColor Gray
    Write-Host ""
}

# -----------------------------------------------------------------------------
# 1. Confirm, then decide each component.
# -----------------------------------------------------------------------------
if (-not $Silent -and -not $All) {
    Write-Host "About to remove:" -ForegroundColor Yellow
    $RootContents = if ($LibraryInsideRoot) {
        "Sublime, Sumatra, TeX Live, the TeXLib library, scripts, logs"
    } else {
        "Sublime, Sumatra, TeX Live, scripts, logs"
    }
    Write-Host "  - $BaseDir ($RootContents)" -ForegroundColor Gray
    Write-Host "  - Desktop and Start Menu shortcuts" -ForegroundColor Gray
    Write-Host "  - PATH entries pointing at TeX Live" -ForegroundColor Gray
    Write-Host "  - File-association and 'Open with' registry entries" -ForegroundColor Gray
    Write-Host "  - $env:USERPROFILE\TeXLib  (only if it is a junction -- see notes)" -ForegroundColor Gray
    Write-Host ""
    if (-not $LibraryInsideRoot) {
        Write-Host "PRESERVES (unless you say otherwise below):" -ForegroundColor Green
        Write-Host "  - $TeXLibDir  (the TeXLib library)" -ForegroundColor Gray
        Write-Host ""
    }
    $Confirm = Read-Host "Proceed? (Y/N)"
    if ($Confirm -ne "Y" -and $Confirm -ne "y") {
        Write-Host "Aborted." -ForegroundColor Yellow
        Stop-Uninstaller 0
    }
    Write-Host ""

    # Per-component questions. Only asked for components that are actually
    # present, so a partial install doesn't march the user through prompts about
    # things that were never there.
    if (-not $KeepSublime -and (Test-Path $SublimeDir)) {
        $KeepSublime = -not (Read-YesNo "Remove Sublime Text ($SublimeDir)?" $true)
    }
    if (-not $KeepSumatra -and (Test-Path $SumatraDir)) {
        $KeepSumatra = -not (Read-YesNo "Remove SumatraPDF ($SumatraDir)?" $true)
    }
    if (-not $KeepTeXLive -and (Test-Path $TexLiveDir)) {
        Write-Host "  (TeX Live is ~6 GB and takes 30-60 minutes to reinstall.)" -ForegroundColor Gray
        $KeepTeXLive = -not (Read-YesNo "Remove TeX Live ($TexLiveDir)?" $true)
    }
    if (-not $RemoveLibrary -and -not $LibraryInsideRoot -and (Test-Path $TeXLibDir)) {
        Write-Host "  (This is the pre-0.6.3 location; anything you saved alongside the" -ForegroundColor Gray
        Write-Host "   library goes with it.)" -ForegroundColor Gray
        $RemoveLibrary = Read-YesNo "Remove the TeXLib library ($TeXLibDir)?" $false
    }
    Write-Host ""
}

# Keeping any component means the install root has to survive to hold it.
$KeepAnyComponent = $KeepSublime -or $KeepSumatra -or $KeepTeXLive

# -----------------------------------------------------------------------------
# 2. Close anything holding a lock.
# -----------------------------------------------------------------------------
# Sublime Text and SumatraPDF keep their own exe (and, for Sublime, its plugin
# host and cache) open while running. Remove-Item then deletes what it can,
# throws on the rest, and leaves a half-removed install behind -- which is
# exactly how "the uninstaller didn't remove Sublime" happens. Only processes
# whose image lives under THIS install root are touched; a Sublime the user
# installed themselves is none of our business.
$Running = @()
foreach ($Name in @("sublime_text", "sublime_text_helper", "plugin_host-3.3", "plugin_host-3.8", "SumatraPDF")) {
    foreach ($p in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        $ImagePath = $null
        try { $ImagePath = $p.Path } catch { $ImagePath = $null }
        if ($ImagePath -and $ImagePath.ToLowerInvariant().StartsWith($BaseDir.TrimEnd('\').ToLowerInvariant() + '\')) {
            $Running += $p
        }
    }
}
if ($Running.Count -gt 0) {
    $Names = ($Running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Write-Host "These TeXLib programs are running and hold file locks: $Names" -ForegroundColor Yellow
    $CloseThem = $Force -or $Silent -or (Read-YesNo "Close them now? (unsaved work will be lost)" $true)
    if ($CloseThem) {
        foreach ($p in $Running) {
            try {
                # Ask nicely first so Sublime can flush its session; kill only
                # what refuses. CloseMainWindow returns $false for processes with
                # no window at all (the plugin hosts), which is not a failure.
                $null = $p.CloseMainWindow()
                if (-not $p.WaitForExit(5000)) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
            } catch { $null = $_ }
        }
        Start-Sleep -Seconds 1
        Write-Host "  Closed" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Leaving them running; removal of the locked files will fail." -ForegroundColor Yellow
    }
    Write-Host ""
}

# -----------------------------------------------------------------------------
# 3. Decide junction ownership BEFORE step 5 deletes the evidence.
# -----------------------------------------------------------------------------
# install.ps1 stamps <BaseDir>\VERSION with `texlib_root=<path>`, and when it
# creates the user-root junction it reassigns $TeXLibDir to that junction --
# so texlib_root pointing AT the junction is the installer saying "I made this".
# The file lives inside $BaseDir, which step 5 removes, hence reading it here.
#
# Kept as a named function so the unit-helpers CI job can lift it out by AST and
# test the decision without a real junction anywhere near a developer's machine.
function Test-InstallerOwnsJunction {
    param([string]$JunctionPath, [string]$VersionFile)

    if (-not $JunctionPath) { return $false }
    if (-not $VersionFile -or -not (Test-Path $VersionFile)) { return $false }

    $line = Get-Content $VersionFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\s*texlib_root\s*=' } |
            Select-Object -First 1
    if (-not $line) { return $false }

    $claimed = ($line -split '=', 2)[1]
    if (-not $claimed) { return $false }
    # Compare as paths, not strings: tolerate a trailing slash and case.
    return ($claimed.Trim().TrimEnd('\') -ieq $JunctionPath.Trim().TrimEnd('\'))
}

$UserRootJunction = "$env:USERPROFILE\TeXLib"
$InstallerOwnsJunction = Test-InstallerOwnsJunction `
    -JunctionPath $UserRootJunction -VersionFile $VersionFile

# -----------------------------------------------------------------------------
# 4. Unlink junctions inside the install root BEFORE removing it.
# -----------------------------------------------------------------------------
# <Sublime>\Data\Packages\User is a junction to the library's Sublime\ folder.
# Windows PowerShell 5.1's Remove-Item -Recurse walks INTO reparse points, so
# removing the install root with that junction still in place either deletes the
# user's settings on the other side of it or -- when something over there is
# locked or a OneDrive placeholder -- throws partway through and leaves Sublime
# and SumatraPDF sitting there half-deleted. Unlinking first makes the removal
# both safe and reliable. Directory::Delete(path, $false) drops the link entry
# only and never follows it.
function Clear-JunctionsUnder {
    param([string]$Root)
    if (-not (Test-Path $Root)) { return }
    $Links = @(Get-ChildItem -Path $Root -Recurse -Force -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Attributes -match 'ReparsePoint' })
    foreach ($Link in $Links) {
        try {
            [System.IO.Directory]::Delete($Link.FullName, $false)
            Write-Host "  Unlinked junction $($Link.FullName) (target preserved)" -ForegroundColor Gray
        } catch {
            Write-Host "  [WARN] Could not unlink $($Link.FullName): $_" -ForegroundColor Yellow
        }
    }
}

if (Test-Path $BaseDir) {
    Write-Host "Unlinking junctions inside $BaseDir..." -ForegroundColor Yellow
    Clear-JunctionsUnder -Root $BaseDir
}

# -----------------------------------------------------------------------------
# 5. Remove the components.
# -----------------------------------------------------------------------------
function Uninstall-Component {
    # One removal, reported. Returns nothing: callers care about the console
    # line and the on-disk result, and a return value here would only be a
    # second thing to keep in sync.
    param([string]$Label, [string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return }
    Write-Host "Removing $Label ($Path)..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-Host "  Removed" -ForegroundColor Green
        return
    } catch {
        Write-Host "  [warn] bulk removal stopped: $_" -ForegroundColor Yellow
    }
    # A single locked file aborts the whole recursive delete, abandoning
    # everything the walk had not reached yet. Retry child by child so one
    # stubborn file costs only itself, then say exactly what is left.
    Write-Host "  Retrying item by item..." -ForegroundColor Yellow
    foreach ($Child in @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $Child.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $Path) {
        $Left = @(Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue).Count
        Write-Host "  [WARN] $Label is only partly removed: $Left item(s) remain in $Path" -ForegroundColor Yellow
        Write-Host "  [WARN] Close anything still using them and re-run the uninstaller." -ForegroundColor Yellow
    } else {
        Write-Host "  Removed" -ForegroundColor Green
    }
}

if ($KeepAnyComponent) {
    # Something is staying, so the root has to stay too: remove only what was
    # actually selected, then tidy up the installer's own bookkeeping.
    if (-not $KeepSublime) { Uninstall-Component -Label "Sublime Text" -Path $SublimeDir }
    else { Write-Host "Keeping Sublime Text at $SublimeDir" -ForegroundColor Gray }

    if (-not $KeepSumatra) { Uninstall-Component -Label "SumatraPDF" -Path $SumatraDir }
    else { Write-Host "Keeping SumatraPDF at $SumatraDir" -ForegroundColor Gray }

    if (-not $KeepTeXLive) { Uninstall-Component -Label "TeX Live" -Path $TexLiveDir }
    else { Write-Host "Keeping TeX Live at $TexLiveDir" -ForegroundColor Gray }

    if ($RemoveLibrary) { Uninstall-Component -Label "TeXLib library" -Path $TeXLibDir }
    elseif (Test-Path $TeXLibDir) { Write-Host "Keeping the TeXLib library at $TeXLibDir" -ForegroundColor Gray }

    # $BaseDir\Scripts and $BaseDir\VERSION stay deliberately. The install is now
    # partial, and those two are exactly what a later re-install or a follow-up
    # uninstall needs to find the components that were kept.
    Write-Host ""
    Write-Host "Kept components remain under $BaseDir; a later install.bat run will find them" -ForegroundColor Gray
    Write-Host "and offer to skip re-downloading them." -ForegroundColor Gray
} else {
    # Everything goes: one removal of the root takes the components, the library
    # (0.6.3+ layout), the scripts, and the logs with it.
    Uninstall-Component -Label "the TeXLib install" -Path $BaseDir
    if ($RemoveLibrary -and -not $LibraryInsideRoot) {
        Uninstall-Component -Label "TeXLib library" -Path $TeXLibDir
    }
}

# -----------------------------------------------------------------------------
# 6. Remove user-root TeXLib junction.
# -----------------------------------------------------------------------------
# The TEXINPUTS-safe path install.ps1 creates when the library path contains a
# space or comma. Two safety checks, both required:
#   a) it must actually be a reparse point -- a real folder at
#      %USERPROFILE%\TeXLib (someone's hand-built library) must never be touched;
#   b) the installer must have CLAIMED it via VERSION's texlib_root. A junction
#      we did not create is very often a developer's own link to their real
#      library, and unlinking it silently breaks every TeX build that resolves
#      through that path. -RemoveJunction (and -All) override (b) deliberately.
if (Test-Path $UserRootJunction) {
    $Item = Get-Item $UserRootJunction -Force
    if ($Item.Attributes -notmatch 'ReparsePoint') {
        Write-Host "$UserRootJunction is a real folder, not a junction; leaving it alone." -ForegroundColor Gray
    } elseif (-not $InstallerOwnsJunction -and -not $RemoveJunction) {
        $Target = $Item.Target; if (-not $Target) { $Target = $Item.LinkTarget }
        Write-Host "Leaving $UserRootJunction in place." -ForegroundColor Gray
        Write-Host "  This uninstaller could not confirm it created that junction" -ForegroundColor Gray
        Write-Host "  (no matching texlib_root in $VersionFile), and it may be your own" -ForegroundColor Gray
        Write-Host "  link to a real library. Target: $($Target -join '; ')" -ForegroundColor Gray
        Write-Host "  Re-run with -RemoveJunction if you are sure you want it gone." -ForegroundColor Gray
    } else {
        Write-Host "Removing user-root junction $UserRootJunction..." -ForegroundColor Yellow
        try {
            # [System.IO.Directory]::Delete with recursive=$false unambiguously
            # deletes the junction entry without following the link into the
            # target.
            [System.IO.Directory]::Delete($UserRootJunction, $false)
            Write-Host "  Removed junction (target preserved)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not remove $UserRootJunction : $_" -ForegroundColor Yellow
        }
    }
}

# -----------------------------------------------------------------------------
# 7. Remove shortcuts.
# -----------------------------------------------------------------------------
Write-Host "Removing shortcuts..." -ForegroundColor Yellow
$DesktopPath   = [Environment]::GetFolderPath("Desktop")
$StartMenuPath = [Environment]::GetFolderPath("StartMenu") + "\Programs"
$ShortcutNames = @("Sublime.lnk", "Sumatra.lnk", "Sublime Text.lnk", "SumatraPDF.lnk")
foreach ($n in $ShortcutNames) {
    foreach ($dir in @($DesktopPath, $StartMenuPath)) {
        if (-not $dir) { continue }
        $p = Join-Path $dir $n
        if (Test-Path $p) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed $p" -ForegroundColor Gray
        }
    }
}

# -----------------------------------------------------------------------------
# 8. Clean PATH.
# -----------------------------------------------------------------------------
Write-Host "Cleaning user PATH..." -ForegroundColor Yellow
$TexBinPath     = "$TexLiveDir\bin\windows"
$LegacyOneTeX   = "$env:LOCALAPPDATA\OneTeX\TexLive\$TexLiveYear\bin\windows"
$LegacyWrappers = "$env:LOCALAPPDATA\OneTeX\Wrappers"

$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath) {
    $PathParts = $CurrentPath -split ";"
    $NewParts = $PathParts | Where-Object {
        # TeX Live's bin stays on PATH when TeX Live itself is staying.
        (-not ($_ -eq $TexBinPath -and -not $KeepTeXLive)) -and
        $_ -ne $LegacyOneTeX -and $_ -ne $LegacyWrappers -and $_ -ne ""
    }
    if ($NewParts.Count -ne $PathParts.Count) {
        [Environment]::SetEnvironmentVariable("Path", ($NewParts -join ";"), "User")
        Write-Host "  PATH cleaned" -ForegroundColor Green
    } else {
        Write-Host "  PATH had nothing to remove" -ForegroundColor Gray
    }
}

# -----------------------------------------------------------------------------
# 9. Remove file associations and "Open with" entries.
# -----------------------------------------------------------------------------
# Leaving these behind is what produces the stale rows in the Open With dialog:
# entries naming an exe that this uninstaller just deleted. Everything we ever
# registered comes out -- the ProgIDs, the per-extension defaults that point at
# them, the Applications\<exe> entries, and the Explorer-side OpenWithList /
# OpenWithProgids / UserChoice records. Only entries that are OURS are touched.
Write-Host "Removing file associations and 'Open with' entries..." -ForegroundColor Yellow

$RegPath = "HKCU:\Software\Classes"
$TexlibProgIDs = @("TeXLib.SublimeFile", "TeXLib.SumatraPDF",
                   "OneTeX.SublimeFile", "OneTeX.SumatraPDF")
$ManagedExts = @(".txt", ".tex", ".cls", ".sty", ".bib",
                 ".sublime-project", ".sublime-workspace", ".pdf")
$ExePatterns = @("sublime_text.exe", "SumatraPDF*.exe")
$ProviderProps = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')

foreach ($ID in $TexlibProgIDs) {
    $full = "$RegPath\$ID"
    if (Test-Path $full) {
        Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed ProgID $ID" -ForegroundColor Gray
    }
}

# Applications\<exe>: what puts an app in the Open With list under its own name.
# Remove only entries whose exe is now gone, so a Sublime the user installed
# themselves -- which shares the exe name -- survives an uninstall of ours.
$AppsKey = "$RegPath\Applications"
if (Test-Path $AppsKey) {
    foreach ($App in @(Get-ChildItem $AppsKey -ErrorAction SilentlyContinue)) {
        $IsOurs = $false
        foreach ($p in $ExePatterns) { if ($App.PSChildName -like $p) { $IsOurs = $true; break } }
        if (-not $IsOurs) { continue }
        if (Test-ShellCommandLive "$($App.PSPath)\shell\open\command") { continue }
        Remove-Item -Path $App.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed Applications\$($App.PSChildName)" -ForegroundColor Gray
    }
}

# Per-extension associations install created (HKCU\Software\Classes\<ext> whose
# default points at one of our ProgIDs). Without this, uninstall leaves
# .tex/.cls/... pointing at a now-deleted ProgID (a broken "open with"), and --
# most rudely -- leaves .txt hijacked. Only delete a key whose default is OURS,
# so an association the user set themselves is never clobbered. Removing
# HKCU\.txt restores the system (HKLM) default for .txt.
foreach ($Ext in $ManagedExts) {
    $ExtKey = "$RegPath\$Ext"
    if (Test-Path $ExtKey) {
        $def = $null
        try { $def = (Get-Item -Path $ExtKey).GetValue("") } catch { $def = $null }
        if ($def -and ($TexlibProgIDs -contains $def)) {
            Remove-Item -Path $ExtKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed $Ext association ($def)" -ForegroundColor Gray
        } else {
            # The default belongs to someone else, but our ProgID may still be
            # offered in this extension's Open With list. Take just that out.
            $OpenWith = "$ExtKey\OpenWithProgids"
            if (Test-Path $OpenWith) {
                foreach ($ID in $TexlibProgIDs) {
                    Remove-ItemProperty -Path $OpenWith -Name $ID -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Explorer's own per-extension records live in a different hive branch and
    # outlive HKCU\Software\Classes entirely -- this is the branch that keeps
    # showing a removed app in the Open With dialog.
    $FileExts = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext"
    if (-not (Test-Path $FileExts)) { continue }

    $ProgKey = "$FileExts\OpenWithProgids"
    if (Test-Path $ProgKey) {
        foreach ($ID in $TexlibProgIDs) {
            Remove-ItemProperty -Path $ProgKey -Name $ID -Force -ErrorAction SilentlyContinue
        }
    }

    # OpenWithList is lettered values (a, b, c, ...) ordered by MRUList. Drop our
    # exe names, then re-letter the survivors: a hole in the sequence shows up as
    # a blank row in the Open With dialog.
    $ListKey = "$FileExts\OpenWithList"
    if (Test-Path $ListKey) {
        $Props = Get-ItemProperty -Path $ListKey -ErrorAction SilentlyContinue
        if ($Props) {
            $Order = @()
            if ($Props.MRUList) { $Order = $Props.MRUList.ToCharArray() | ForEach-Object { "$_" } }
            foreach ($p in $Props.PSObject.Properties) {
                if ($ProviderProps -contains $p.Name -or $p.Name -eq 'MRUList') { continue }
                if ($Order -notcontains $p.Name) { $Order += $p.Name }
            }
            $Survivors = @()
            foreach ($Slot in $Order) {
                $Val = $Props.$Slot
                if (-not $Val) { continue }
                # A row here is an exe file name, an AppX AUMID (contains '!') or
                # a CLSID-relative path (contains '\'). A value with none of
                # those resolves to nothing and shows as a blank line in the Open
                # With dialog; while we are rewriting this key, drop it.
                if ($Val -notmatch '[.!\\]') {
                    Write-Host "  Removed malformed $Ext entry '$Val' from the Open With list" -ForegroundColor Gray
                    continue
                }
                # Only OUR copy goes. The exe name is shared with a Sublime or
                # SumatraPDF the user installed themselves, so the deciding test
                # is whether it still resolves: ours was deleted minutes ago,
                # theirs is still on disk and must stay in the list. Resolution
                # goes through HKEY_CLASSES_ROOT -- the merged view Explorer
                # uses -- because a per-machine Sublime lives in HKLM, and an
                # HKCU-only lookup would call it dead and strip it out.
                $IsOurs = $false
                foreach ($p in $ExePatterns) { if ($Val -like $p) { $IsOurs = $true; break } }
                if ($IsOurs -and -not (Test-ShellCommandLive "Registry::HKEY_CLASSES_ROOT\Applications\$Val\shell\open\command")) {
                    Write-Host "  Removed $Ext -> $Val from the Open With list" -ForegroundColor Gray
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
    }

    # UserChoice pins the default. If it names one of ours it is about to be a
    # dead pin, so clear it and let Windows fall back. The key is guarded by
    # Windows and the delete can legitimately fail; that is worth a line, not a
    # failed uninstall.
    $UserChoice = "$FileExts\UserChoice"
    if (Test-Path $UserChoice) {
        $Pinned = $null
        try { $Pinned = (Get-ItemProperty -Path $UserChoice -ErrorAction SilentlyContinue).ProgId } catch { $Pinned = $null }
        if ($Pinned -and ($TexlibProgIDs -contains $Pinned)) {
            try {
                Remove-Item -Path $UserChoice -Recurse -Force -ErrorAction Stop
                Write-Host "  Cleared the pinned default for $Ext ($Pinned)" -ForegroundColor Gray
            } catch {
                Write-Host "  [WARN] $Ext is still pinned to $Pinned and Windows would not let us clear it." -ForegroundColor Yellow
                Write-Host "         Right Click -> Open With -> Choose Another App to reset it." -ForegroundColor Yellow
            }
        }
    }
}

# Tell Explorer to reread associations, or it keeps offering the entries we just
# deleted until the next sign-out. SHCNE_ASSOCCHANGED = 0x08000000.
if (-not ("TeXLib.Shell" -as [type])) {
    Add-Type -Namespace TeXLib -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@ -ErrorAction SilentlyContinue
}
try { [TeXLib.Shell]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero) } catch { $null = $_ }

# -----------------------------------------------------------------------------
# 10. Report.
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   Uninstall complete." -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
$Kept = @()
if ($KeepSublime) { $Kept += "Sublime Text ($SublimeDir)" }
if ($KeepSumatra) { $Kept += "SumatraPDF ($SumatraDir)" }
if ($KeepTeXLive) { $Kept += "TeX Live ($TexLiveDir)" }
if (-not $RemoveLibrary -and (Test-Path $TeXLibDir)) { $Kept += "TeXLib library ($TeXLibDir)" }
if ($Kept.Count -gt 0) {
    Write-Host "Kept at your request:" -ForegroundColor Gray
    foreach ($k in $Kept) { Write-Host "  - $k" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "Re-run with -All to remove everything, or delete those by hand." -ForegroundColor Gray
} else {
    Write-Host "Everything this installer created has been removed." -ForegroundColor Gray
}
Write-Host ""
Write-Host "Issues: $InstallerRepo/issues" -ForegroundColor Cyan
Write-Host ""

Stop-Uninstaller 0
