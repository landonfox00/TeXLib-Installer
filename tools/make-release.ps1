<#
.SYNOPSIS
    Build a TeXLib-Installer release ZIP for distribution.

.DESCRIPTION
    Assembles the installer scripts into a single ZIP, computes a SHA256SUMS
    file alongside it, and stages everything under .\dist\<version>\ ready to
    attach to a GitHub Release.

    The TeXLib library is NOT bundled as of 0.11.0 -- install.ps1 downloads the
    pinned release and hash-verifies it, like every other component.

    Run this from the repo root or from the tools/ directory.

.PARAMETER TexLibPath
    DEPRECATED and ignored since 0.11.0, when the library stopped being
    bundled. Still accepted so existing build scripts and CI invocations do not
    break; passing it prints a notice and changes nothing.

.PARAMETER Version
    Release version string (no leading 'v'). Used for the ZIP filename and
    recorded as release_version= in the bundle's RELEASE file. (It has never
    been written to a file named VERSION, which this line claimed through
    0.11.1.)

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

if ($TexLibPath) {
    Write-Host "  [note] -TexLibPath is ignored since 0.11.0; the library is downloaded, not bundled." -ForegroundColor Yellow
}

Write-Host "make-release.ps1" -ForegroundColor Cyan
Write-Host "  Repo root:   $RepoRoot"
Write-Host "  Version:     $Version"
Write-Host "  Out dir:     $OutDir"
Write-Host ""

# Validate inputs.
$RequiredFiles = @("tools\install.ps1", "tools\uninstall.ps1", "tools\boot_wrapper.ps1",
                   "tools\install-gui.ps1", "tools\uninstall-gui.ps1",
                   "tools\install-console.bat", "tools\uninstall-console.bat",
                   "install.vbs", "uninstall.vbs")
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
# TWO .vbs entry points and the docs sit at the release root -- nothing else.
# Opening the extracted folder should present one obvious thing to
# double-click per direction, install or uninstall, and both are the
# GRAPHICAL ones (a 0.11.0 decision: before it, the root held four .bat
# files and the two plainest names were the CONSOLE ones, so the file a
# first-time user was most likely to click was the one meant for
# scripting). They are .vbs rather than .bat because a double-clicked .bat
# is a console program -- Windows flashes a console window before its first
# line runs -- while wscript is a GUI-subsystem host that never allocates
# one. The console/scriptable surface did not go away; it lives at
# tools\install-console.bat / tools\uninstall-console.bat, where CI, anyone
# typing -Repair / -Doctor / -Verify, and any machine without a script host
# can still reach it.
$InstallerFiles = @(
    "install.vbs", "uninstall.vbs",
    "INSTALL.md", "README.md", "LICENSE", "CHANGELOG.md"
)
foreach ($f in $InstallerFiles) {
    $src = Join-Path $RepoRoot $f
    if (Test-Path $src) { Copy-Item $src $StageRoot -Force }
}
Copy-Item (Join-Path $RepoRoot "templates") $StageRoot -Recurse -Force

# The root .vbs entry points run tools\*-gui.ps1 with the PowerShell console
# hidden from creation (and explain themselves in a message box when the .ps1
# is missing); the console .bat files invoke tools\boot_wrapper.ps1, which in
# turn runs tools\install.ps1 / tools\uninstall.ps1. Every one of these MUST
# ship -- a bundle missing any of them fails at the one moment a user is
# watching it.
# make-release.ps1 itself is the build tool, and dev-install-test.ps1 is a
# local test harness; neither ships. package-integrity asserts that the shipped
# files are present and the other two are not.
$ToolsStage = Join-Path $StageRoot "tools"
New-Item -ItemType Directory -Force -Path $ToolsStage | Out-Null
foreach ($w in @("boot_wrapper.ps1", "install.ps1", "uninstall.ps1", "install-gui.ps1", "uninstall-gui.ps1",
                 "install-console.bat", "uninstall-console.bat")) {
    Copy-Item (Join-Path $RepoRoot "tools\$w") $ToolsStage -Force
}

# The TeXLib library is NOT bundled as of 0.11.0. install.ps1 downloads the
# pinned release (the "texlib" entry in its $Downloads table) and hash-verifies
# it, exactly like Sublime Text, SumatraPDF, TeX Live and LaTeXTools.
#
# Bundling tied two projects' release cadences together: a library fix meant
# cutting an installer release, and every installer release had to decide which
# snapshot of a separate repo to freeze -- in practice whatever HEAD happened to
# be on the maintainer's machine at build time.
#
# The curation this block used to perform -- drop .github\, the author's Package
# Control state, and every non-deployable .py in Sublime\ -- now lives in
# install.ps1's Copy-LibraryTree, which applies it at ANY depth and to EVERY
# source: a downloaded archive, a local texlib\ tree, or a pre-0.6.3 migration.
# That is strictly wider coverage than doing it here ever was.
#
# Read the pin back out of install.ps1 so RELEASE records which library the
# installer being built will actually fetch.
$InstallPs1Text = Get-Content (Join-Path $RepoRoot "tools\install.ps1") -Raw
$PinMatch  = [regex]::Match($InstallPs1Text, '\$TeXLibVersion\s*=\s*"([^"]+)"')
$TeXLibPin = if ($PinMatch.Success) { $PinMatch.Groups[1].Value } else { "" }
if (-not $TeXLibPin) {
    Write-Host "Could not read `$TeXLibVersion from tools\install.ps1; the library pin is unknown." -ForegroundColor Red
    exit 1
}
Write-Host "TeXLib library: not bundled -- install.ps1 fetches $TeXLibPin" -ForegroundColor Cyan

# Stamp the release metadata.
$Stamp = @"
release_version=$Version
built_at=$(Get-Date -Format 'o')
texlib_pin=$TeXLibPin
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
# LF, and no trailing newline beyond the one: Set-Content would end the line
# CRLF, and `sha256sum -c` then parses the filename WITH the \r and reports
# "FAILED open or read" for a file that is sitting right there and whose hash
# is correct. Windows verifiers (Get-FileHash) never noticed; anyone checking
# from WSL, git-bash or a Linux box saw a checksum file that appeared to fail.
[System.IO.File]::WriteAllText($SumsPath, "$Hash  $ZipName`n", [System.Text.UTF8Encoding]::new($false))

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
