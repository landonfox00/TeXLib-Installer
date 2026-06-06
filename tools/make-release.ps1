<#
.SYNOPSIS
    Build a TeXLib-Installer release ZIP for distribution.

.DESCRIPTION
    Assembles the installer scripts plus a snapshot of the TeXLib library
    into a single ZIP, computes a SHA256SUMS file alongside it, and stages
    everything under .\dist\<version>\ ready to attach to a GitHub Release.

    Run this from the repo root or from the tools/ directory.

.PARAMETER TexLibPath
    Path to the TeXLib repo root to snapshot. Defaults to the OneDrive
    location used by the author; override on any other machine.

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
    [string]$TexLibPath = "$env:USERPROFILE\OneDrive - University of Nevada, Reno\Documents\TeXLib",
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
$RequiredFiles = @("install.ps1", "uninstall.ps1", "install.bat", "uninstall.bat")
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
$InstallerFiles = @(
    "install.ps1", "uninstall.ps1", "install.bat", "uninstall.bat",
    "INSTALL.md", "README.md", "LICENSE", "CHANGELOG.md"
)
foreach ($f in $InstallerFiles) {
    $src = Join-Path $RepoRoot $f
    if (Test-Path $src) { Copy-Item $src $StageRoot -Force }
}
Copy-Item (Join-Path $RepoRoot "templates") $StageRoot -Recurse -Force
# runtime/ holds the standalone Explorer builder + Ctrl+B hotkey source that
# install.ps1 deploys/compiles on the target machine.
Copy-Item (Join-Path $RepoRoot "runtime") $StageRoot -Recurse -Force

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

# Stamp the release metadata.
$Stamp = @"
release_version=$Version
built_at=$(Get-Date -Format 'o')
texlib_source=$TexLibPath
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
