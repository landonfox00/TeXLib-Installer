<#
.SYNOPSIS
    Build a TeXLib-Installer release ZIP for distribution.

.DESCRIPTION
    Assembles the installer scripts plus a snapshot of the TeXLib library
    into a single ZIP, computes a SHA256SUMS file alongside it, and stages
    everything under .\dist\<version>\ ready to attach to a GitHub Release.

    Run this from the repo root or from the tools/ directory.

.PARAMETER TexLibPath
    Path to the TeXLib repo root to snapshot. Defaults to
    %USERPROFILE%\Documents\TeXLib, falling back to the OneDrive Documents copy
    if that is where the checkout still lives; override on any other machine.

.PARAMETER Version
    Release version string (no leading 'v'). Used for the ZIP filename and
    written into VERSION inside the bundle.

.PARAMETER OutDir
    Where to drop the release artifacts. Defaults to .\dist .

.EXAMPLE
    .\tools\make-release.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [string]$TexLibPath = "",
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

# Resolve the installer repo root: parent of tools/ when run from tools/,
# else the current dir.
$RepoRoot = if ($PSScriptRoot) {
    Split-Path $PSScriptRoot -Parent
} else {
    (Get-Location).Path
}

if (-not $OutDir) { $OutDir = Join-Path $RepoRoot "dist" }

# Resolve the TeXLib checkout to snapshot. The library moved out of OneDrive, so
# the local Documents copy is checked first; the OneDrive path stays as a
# fallback for a machine that has not moved yet.
if (-not $TexLibPath) {
    $TexLibCandidates = @("$env:USERPROFILE\Documents\TeXLib")
    foreach ($od in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
        if ($od) { $TexLibCandidates += "$od\Documents\TeXLib" }
    }
    foreach ($c in $TexLibCandidates) {
        if (Test-Path (Join-Path $c "course-metadata.sty")) { $TexLibPath = $c; break }
    }
    if (-not $TexLibPath) { $TexLibPath = $TexLibCandidates[0] }
}

Write-Host "make-release.ps1" -ForegroundColor Cyan
Write-Host "  Repo root:   $RepoRoot"
Write-Host "  TeXLib path: $TexLibPath"
Write-Host "  Version:     $Version"
Write-Host "  Out dir:     $OutDir"
Write-Host ""

# Validate inputs.
if (-not (Test-Path $TexLibPath)) {
    Write-Host "TeXLib path not found: $TexLibPath" -ForegroundColor Red
    exit 1
}
$RequiredFiles = @("tools\install.ps1", "tools\uninstall.ps1", "tools\boot_wrapper.ps1",
                   "tools\install-gui.ps1", "tools\uninstall-gui.ps1",
                   "tools\install-console.bat", "tools\uninstall-console.bat",
                   "install.bat", "uninstall.bat")
foreach ($f in $RequiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $f))) {
        Write-Host "Missing required installer file: $f" -ForegroundColor Red
        exit 1
    }
}

# Stage the release contents.
$StageRoot = Join-Path $OutDir "TeXLib-Installer-v$Version"
if (Test-Path $StageRoot) {
    Write-Host "Cleaning previous stage at $StageRoot..." -ForegroundColor Yellow
    Remove-Item $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null

Write-Host "Copying installer files..." -ForegroundColor Cyan
# TWO .bat files and the docs sit at the release root -- nothing else. Opening
# the extracted folder should present one obvious thing to double-click per
# direction, install or uninstall, and both are the GRAPHICAL ones as of
# 0.10.2. The console/scriptable surface did not go away; it moved to
# tools\install-console.bat / tools\uninstall-console.bat, where CI and anyone
# typing -Repair / -Doctor / -Verify can still reach it. Before 0.10.2 the
# root held four .bat files and the two plainest names -- install.bat,
# uninstall.bat -- were the console ones, so the file a first-time user was
# most likely to click was the one meant for scripting.
$InstallerFiles = @(
    "install.bat", "uninstall.bat",
    "INSTALL.md", "README.md", "LICENSE", "CHANGELOG.md"
)
foreach ($f in $InstallerFiles) {
    $src = Join-Path $RepoRoot $f
    if (Test-Path $src) { Copy-Item $src $StageRoot -Force }
}
Copy-Item (Join-Path $RepoRoot "templates") $StageRoot -Recurse -Force

# The root .bat files invoke tools\*-gui.ps1; the console .bat files invoke
# tools\boot_wrapper.ps1, which in turn runs tools\install.ps1 /
# tools\uninstall.ps1. Every one of these MUST ship -- without any of them the
# .bat just flashes open and dies (PowerShell -File on a missing script).
# make-release.ps1 itself is the build tool, and dev-install-test.ps1 is a
# local test harness; neither ships. package-integrity asserts that the shipped
# files are present and the other two are not.
$ToolsStage = Join-Path $StageRoot "tools"
New-Item -ItemType Directory -Force -Path $ToolsStage | Out-Null
foreach ($w in @("boot_wrapper.ps1", "install.ps1", "uninstall.ps1", "install-gui.ps1", "uninstall-gui.ps1",
                 "install-console.bat", "uninstall-console.bat")) {
    Copy-Item (Join-Path $RepoRoot "tools\$w") $ToolsStage -Force
}

# Bundle the TeXLib snapshot. Prefer `git archive` so ONLY tracked files at
# HEAD are bundled -- a plain file copy would sweep in gitignored build
# artifacts (.aux/.log/.pdf), __pycache__, scratch dirs, and editor state.
Write-Host "Snapshotting TeXLib from $TexLibPath..." -ForegroundColor Cyan
$TexLibStage = Join-Path $StageRoot "texlib"
New-Item -ItemType Directory -Force -Path $TexLibStage | Out-Null

$gitOk = $false
try {
    & git -C $TexLibPath rev-parse --is-inside-work-tree 2>$null | Out-Null
    $gitOk = ($LASTEXITCODE -eq 0)
} catch { $gitOk = $false }

if ($gitOk) {
    Write-Host "  Using git archive (tracked files at HEAD only)." -ForegroundColor Gray
    $TarPath = Join-Path $OutDir "texlib-snapshot.tar"
    & git -C $TexLibPath archive --format=tar -o $TarPath HEAD
    if ($LASTEXITCODE -ne 0) { throw "git archive failed for $TexLibPath" }
    & tar -x -f $TarPath -C $TexLibStage
    if ($LASTEXITCODE -ne 0) { throw "tar extraction of the TeXLib snapshot failed" }
    Remove-Item $TarPath -Force
    # CI config isn't needed in the release bundle.
    Remove-Item (Join-Path $TexLibStage ".github") -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  [warn] $TexLibPath is not a git repo; falling back to a filtered file copy (may include build artifacts)." -ForegroundColor Yellow
    $Excludes = @(".git", ".github", "desktop.ini", "Thumbs.db", "__pycache__")
    Get-ChildItem -Path $TexLibPath -Force | Where-Object { $Excludes -notcontains $_.Name } | ForEach-Object {
        Copy-Item $_.FullName $TexLibStage -Recurse -Force
    }
}

# The author's own Package Control state never ships, by either path above. The
# library tracks it because the author's Sublime uses it, but on a coworker's
# machine that file makes any Package Control they install start pulling down
# PowerShell and UnitTesting and re-resolving LaTeXTools' libraries over the
# pinned copies the installer placed by hand -- which is how a plugin host got
# killed on first launch. See section 12 of install.ps1.
$PkgCtrlState = Join-Path $TexLibStage "Sublime\Package Control.sublime-settings"
if (Test-Path $PkgCtrlState) {
    Remove-Item $PkgCtrlState -Force
    Write-Host "  Excluded the author's Package Control.sublime-settings from the bundle." -ForegroundColor Gray
}

# Nor does the author's test suite. Sublime\ is the author's working directory
# and it is bundled wholesale (git archive of HEAD), but on an installed machine
# that same folder IS Packages\User via the settings junction -- and Sublime
# loads every top-level .py in Packages\User as a plugin. The test modules call
# _testkit.stub_sublime() at import (replacing sys.modules["sublime_plugin"] in
# the live host) and three of them end in a module-scope sys.exit() (SystemExit
# escapes the plugin loader's `except Exception`), so they killed plugin_host-3.8
# on first launch. deploy.ps1 has always deployed an allowlist for exactly this
# reason; the bundle now honours the same contract.
#
# Allowlist, not a test_* denylist: anything new and top-level in Sublime\ is a
# Packages\User plugin on every coworker's machine, so the deployables are named
# and everything else stays home. Sublime\texlib\ is untouched -- it ships as a
# real package to Packages\TeXLib, and Sublime does not auto-load .py from a
# subfolder.
$SublimeStage = Join-Path $TexLibStage "Sublime"
$DeployablePy = @("texlib_builder.py", "texlib_pdfpost.py")   # == deploy.ps1's $pyfiles
if (Test-Path $SublimeStage) {
    $Strays = @(Get-ChildItem -Path $SublimeStage -File -Filter "*.py" |
                Where-Object { $DeployablePy -notcontains $_.Name })
    foreach ($s in $Strays) { Remove-Item $s.FullName -Force }
    if ($Strays.Count -gt 0) {
        Write-Host "  Excluded $($Strays.Count) dev-only Python file(s) from the bundle's Sublime\ folder." -ForegroundColor Gray
    }
}

# Record the exact TeXLib state bundled, for traceability. The bundle is a
# git-archive of HEAD, so this pins which TeXLib commit shipped -- the source
# path alone never told you that.
$TexLibCommit = ""
$TexLibDescribe = ""
if ($gitOk) {
    $TexLibCommit = (& git -C $TexLibPath rev-parse HEAD 2>$null)
    if ($TexLibCommit) { $TexLibCommit = "$TexLibCommit".Trim() }
    $TexLibDescribe = (& git -C $TexLibPath describe --tags --always 2>$null)
    if ($TexLibDescribe) { $TexLibDescribe = "$TexLibDescribe".Trim() }
}

# Stamp the release metadata.
$Stamp = @"
release_version=$Version
built_at=$(Get-Date -Format 'o')
texlib_source=$TexLibPath
texlib_commit=$TexLibCommit
texlib_describe=$TexLibDescribe
"@
Set-Content -Path (Join-Path $StageRoot "RELEASE") -Value $Stamp -Encoding UTF8

# ZIP it.
$ZipPath = Join-Path $OutDir "TeXLib-Installer-v$Version.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Write-Host "Creating $ZipPath..." -ForegroundColor Cyan
Compress-Archive -Path "$StageRoot\*" -DestinationPath $ZipPath -CompressionLevel Optimal

# Generate SHA256SUMS. One file in v0.1.0; pattern in place for future when
# we may ship multiple artifacts (e.g. a separate texlib-only ZIP).
$SumsPath = Join-Path $OutDir "SHA256SUMS"
Write-Host "Writing $SumsPath..." -ForegroundColor Cyan
$Hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()
$ZipName = Split-Path $ZipPath -Leaf
Set-Content -Path $SumsPath -Value "$Hash  $ZipName" -Encoding ASCII

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  ZIP:        $ZipPath"
Write-Host "  Stage:      $StageRoot"
Write-Host "  Checksums:  $SumsPath"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. git tag v$Version && git push --tags"
Write-Host "  2. On GitHub: create a Release for v$Version, upload the ZIP and SHA256SUMS"
Write-Host "  3. Paste the CHANGELOG entry into the release notes"
