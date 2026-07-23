<#
.SYNOPSIS
    Run a REAL install against a seeded "returning machine" state, locally,
    without touching anything outside a throwaway sandbox directory.

.DESCRIPTION
    The returning-machine paths -- reusing an already-synced library, the
    Skip/Reinstall prompts, the junctioned Packages\User -- are where the v0.6.1
    install bugs lived, and they are awkward to reach on a dev box: they need an
    existing library, an existing install, and a full (non--OnlyTeXLib) run.

    This script builds that state in a temp sandbox and drives install.ps1
    through it twice: once -Silent, once interactively with the Skip answers on
    stdin. Seeding empty component directories is enough for the installer's
    Test-Path detection to offer Skip, so none of the four large downloads
    happen and a full run takes about a minute.

    Containment is entirely by flags -- -InstallPath, -TeXLibPath, -Sandbox --
    so there is nothing to restore afterwards. Deleting the sandbox is the whole
    cleanup. In particular this NEVER calls uninstall.ps1: that removes
    %USERPROFILE%\TeXLib when it is a junction, which on a developer's machine
    is the live junction to their real library. CI covers uninstall instead,
    where the VM is disposable.

.PARAMETER SandboxRoot
    Where to build the throwaway state. Defaults to
    %TEMP%\texlib-installer-devtest. Wiped at the start of every run.

.PARAMETER Keep
    Leave the sandbox in place on exit so you can inspect the resulting tree,
    logs, and VERSION stamp.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\dev-install-test.ps1 -Keep
#>
[CmdletBinding()]
param(
    [string]$SandboxRoot = (Join-Path $env:TEMP 'texlib-installer-devtest'),
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Installer = Join-Path $RepoRoot 'install.ps1'
if (-not (Test-Path $Installer)) { throw "install.ps1 not found at $Installer" }

$Root = Join-Path $SandboxRoot 'root'      # -InstallPath : components
$Lib  = Join-Path $SandboxRoot 'library'   # -TeXLibPath  : the TeXLib library

$script:Fails = 0
function Assert-That($ok, $msg) {
    if ($ok) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else     { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:Fails++ }
}
function Write-Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }


# --- seed -------------------------------------------------------------------
Write-Head "SEED returning machine at $SandboxRoot"
Remove-Item $SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue

# A library but deliberately NO texlib\ bundle next to install.ps1: that pairing
# is what puts the installer on the $UseExistingTeXLib path.
New-Item -ItemType Directory -Force -Path (Join-Path $Lib 'Sublime') | Out-Null
Set-Content -Encoding UTF8 -Path (Join-Path $Lib 'CHANGELOG.md') `
    -Value "# Changelog`r`n`r`n## [Unreleased]`r`n- dev-install-test stub library."
foreach ($p in 'course-metadata','texlib-build','basic-utilities') {
    Set-Content -Encoding UTF8 -Path (Join-Path $Lib "$p.sty") `
        -Value "\NeedsTeXFormat{LaTeX2e}`r`n\ProvidesPackage{$p}[2026/01/01 stub]`r`n\endinput"
}
# Present HERE, these are what make section 16's source and destination the same
# directory once Packages\User is junctioned to <library>\Sublime.
Set-Content -Encoding UTF8 -Path (Join-Path $Lib 'Sublime\texlib_builder.py')        -Value '# dev-install-test stub builder.'
Set-Content -Encoding UTF8 -Path (Join-Path $Lib 'Sublime\TeXLib.sublime-build')     -Value '{ "//": "stub" }'
Set-Content -Encoding UTF8 -Path (Join-Path $Lib 'Sublime\Default.sublime-commands') -Value '[]'
Set-Content -Encoding UTF8 -Path (Join-Path $Lib 'Sublime\LaTeX.sublime-settings')   -Value '{ "//": "stub" }'

# Empty dirs are all the installer's detection needs to offer Skip. The TexLive
# path must match $TexLiveYear exactly.
New-Item -ItemType Directory -Force -Path `
    (Join-Path $Root 'Sublime Text\Data\Packages\LaTeXTools'), `
    (Join-Path $Root 'Sublime Text\Data\Lib\python38\regex'), `
    (Join-Path $Root 'Sumatra'), `
    (Join-Path $Root 'TexLive\2025\bin\windows') | Out-Null
# Gates section 16a-2, so the regex wheel is not downloaded either.
Set-Content -Encoding UTF8 -Path (Join-Path $Root 'Sublime Text\Data\Lib\python38\regex\__init__.py') `
    -Value '# stub regex.'
Write-Host "  library: $Lib"
Write-Host "  root:    $Root"


# --- run --------------------------------------------------------------------
function Invoke-Install {
    param([switch]$Interactive)
    Write-Head $(if ($Interactive) { 'INTERACTIVE re-run (Skip answers on stdin)' } else { 'SILENT full install' })

    # The wrapper owns the pause-on-failure prompt; set this so a failing run
    # cannot block on "Press Enter" here.
    $env:TEXLIB_INSTALLER_WRAPPED = '1'
    $log = Join-Path $SandboxRoot "out-$(if($Interactive){'interactive'}else{'silent'}).txt"

    Push-Location $RepoRoot
    try {
        if ($Interactive) {
            # Answers via file redirect, not `echo s | ...`: cmd's echo appends a
            # trailing space, so Read-Host would see "s " -- harmless for Skip
            # today, silently wrong the day this is extended to test "r".
            # Redirected stdin is closed at EOF, so this cannot hang.
            $answers = Join-Path $SandboxRoot 'answers.txt'
            Set-Content -Encoding ascii -Path $answers -Value "s`r`ns`r`ns"
            $out = & cmd /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Installer`" -InstallPath `"$Root`" -TeXLibPath `"$Lib`" -Sandbox < `"$answers`"" |
                   Tee-Object -FilePath $log | Out-String
        } else {
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                -File $Installer -Silent -InstallPath $Root -TeXLibPath $Lib -Sandbox |
                   Tee-Object -FilePath $log | Out-String
        }
        $rc = $LASTEXITCODE
    } finally { Pop-Location }

    Write-Host "exit code: $rc" -ForegroundColor Yellow
    return @{ Out = $out; Rc = $rc }
}

try {
    $r1 = Invoke-Install
    Write-Head "ASSERT silent install"
    Assert-That ($r1.Out -notmatch 'with itself')                   "no 'Cannot overwrite ... with itself'"
    Assert-That ($r1.Out -match 'Existing TeXLib library detected') "took the `$UseExistingTeXLib path"
    Assert-That ($r1.Rc -eq 0)                                       "exit 0"
    Assert-That ($r1.Out -notmatch 'Update available')               "no bogus downgrade notice"
    Assert-That ($r1.Out -notmatch 'Could not create shortcut')      "no shortcut attempt under -Sandbox"

    $user = Join-Path $Root 'Sublime Text\Data\Packages\User'
    Assert-That (Test-Path $user) "Packages\User exists"
    if (Test-Path $user) {
        Assert-That ((Get-Item $user -Force).Attributes -match 'ReparsePoint') "Packages\User is a junction"
        Assert-That (Test-Path (Join-Path $user 'texlib_builder.py'))          "builder reachable through the junction"
    }
    Assert-That ((Get-Content (Join-Path $Lib 'Sublime\texlib_builder.py') -Raw) -match 'stub builder') `
                                                                     "library builder file not clobbered"

    $r2 = Invoke-Install -Interactive
    Write-Head "ASSERT interactive re-run"
    Assert-That ($r2.Out -notmatch 'with itself')                    "no self-copy on the interactive path"
    Assert-That (([regex]::Matches($r2.Out,'is already installed\.')).Count -ge 3) "3 already-installed prompts"
    foreach ($c in 'Skipping Sublime Text','Skipping SumatraPDF','Skipping TeX Live') {
        Assert-That ($r2.Out -match [regex]::Escape($c))             "'$c' reached (stdin answer took)"
    }
    Assert-That ($r2.Rc -eq 0)                                        "interactive re-run exit 0"

    # -Sandbox's whole promise: nothing outside the sandbox was written.
    Write-Head "ASSERT sandbox containment"
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    Assert-That ($userPath -notlike "*$Root*")                        "user PATH free of the sandbox"
    foreach ($k in 'TeXLib.SublimeFile','TeXLib.SumatraPDF') {
        Assert-That (-not (Test-Path "HKCU:\Software\Classes\$k"))    "HKCU\Software\Classes\$k not created"
    }
    foreach ($p in 'C:\Sublime.lnk','C:\Sumatra.lnk') {
        Assert-That (-not (Test-Path $p))                             "$p not created"
    }
}
finally {
    if ($Keep) { Write-Host ""; Write-Host "Sandbox kept at $SandboxRoot" -ForegroundColor Gray }
    else { Remove-Item $SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Head "RESULT"
if ($script:Fails -eq 0) { Write-Host "ALL ASSERTIONS PASSED" -ForegroundColor Green; exit 0 }
Write-Host "$script:Fails ASSERTION(S) FAILED" -ForegroundColor Red
exit 1
