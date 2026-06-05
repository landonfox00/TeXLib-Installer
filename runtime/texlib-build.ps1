<#
.SYNOPSIS
    Build a single TeXLib .tex file from outside the editor (Explorer
    right-click / Ctrl+B hotkey). No Sublime, no LaTeXTools.

.DESCRIPTION
    A standalone PowerShell port of the build *recipe* implemented by
    texlib_builder.py (the LaTeXTools custom builder). That builder is a
    PdfBuilder subclass driven by Sublime, so it cannot run on its own. This
    script reproduces the same decisions so a file builds identically whether
    you launch it from the editor or from File Explorer:

      * %!TeX root  -> redirect the build to the master document.
      * %!TeX program / %!TeX TS-program -> engine selection (default pdflatex).
      * \documentclass{autoexam|quiz|schedule} -> force lualatex.
      * Build modes (default/key/solutions/student/rubric/draft) injected as
        \def macros, never by editing the .tex.
      * allversions -> one PDF per \versions{...} entry.
      * -synctex=1, -shell-escape for lua/xe, aux routing via -output-directory.
      * "Rerun to get ... right." + biber rerun loop (up to 3 passes).
      * Copy the PDF/.synctex.gz/.spl back next to the source; .spl PDF split;
        hide the .synctex.gz artifact.

    Keep this in sync with texlib_builder.py in the TeXLib repo: the two share
    no code, so a change to the recipe there must be mirrored here.

.PARAMETER Path
    The .tex file to build (the selected file). If it carries a %!TeX root
    directive, the referenced master is built instead. (Named -Path rather
    than -File so it never collides with powershell.exe's own -File switch
    when invoked from the registry verb.)

.PARAMETER Mode
    default | key | solutions | student | rubric | draft | allversions.

.PARAMETER NoOpen
    Do not open the resulting PDF in SumatraPDF on success.

.NOTES
    Paths (TeX Live bin, TeXLib root, SumatraPDF, Sublime) come from
    texlib-build.config.psd1, written next to this script at install time.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [ValidateSet('default', 'key', 'solutions', 'student', 'rubric', 'draft', 'allversions')]
    [string]$Mode = 'default',

    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

# --- Configuration ----------------------------------------------------------

# Document classes that must compile with lualatex.
$LualatexClasses = @('autoexam', 'quiz', 'schedule')

# Build mode -> the compile-time macro the TeXLib classes branch on
# (texlib-build.sty turns these \def's into \ifsolutions / \ifkey / ...).
$ModeMacros = @{
    'default'   = ''
    'key'       = '\def\ShowKey{}'
    'solutions' = '\def\ShowSolutions{}'
    'student'   = '\def\StudentMode{}'
    'rubric'    = '\def\ShowRubric{}'
    'draft'     = '\def\ShowDraft{}'
}

$MaxReruns = 3

# --- Load installer-written config -----------------------------------------

$ConfigPath = Join-Path $PSScriptRoot 'texlib-build.config.psd1'
if (-not (Test-Path $ConfigPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "TeXLib build config not found:`n$ConfigPath`n`nReinstall TeXLib to regenerate it.",
        'TeXLib Build', 'OK', 'Error') | Out-Null
    exit 3
}
$Cfg = Import-PowerShellDataFile -Path $ConfigPath

# --- Logging (a per-build log we can open on failure) -----------------------

$Script:LogLines = New-Object System.Collections.Generic.List[string]
function Write-Build {
    param([string]$Message)
    $Script:LogLines.Add($Message)
    Write-Host $Message
}

# --- Toast / notification helpers ------------------------------------------

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

function Show-Toast {
    param([string]$Title, [string]$Message)
    # Best-effort Windows toast via WinRT. Any failure is non-fatal: on errors
    # we also open the .log, which is the reliable signal.
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $texts = $template.GetElementsByTagName('text')
        $texts.Item(0).AppendChild($template.CreateTextNode($Title))  | Out-Null
        $texts.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        $appId = 'TeXLib.Build'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch {
        # Fall through silently; callers that care open the log themselves.
    }
}

# --- Environment: TeX Live on PATH, TEXINPUTS at the (junction) library -----

function Initialize-TexEnvironment {
    $prepend = @()
    if ($Cfg.TexBin)   { $prepend += $Cfg.TexBin }
    if ($Cfg.TlPerlBin) { $prepend += $Cfg.TlPerlBin }
    if ($prepend.Count) {
        $env:PATH = ($prepend -join ';') + ';' + $env:PATH
    }
    # kpathsea splits TEXINPUTS on commas; $Cfg.TexLibRoot is the already
    # comma-free (junction-resolved) path the installer recorded.
    if ($Cfg.TexLibRoot) {
        $env:TEXINPUTS = ".;$($Cfg.TexLibRoot)//;"
    }
}

# --- Magic-comment + source parsing ----------------------------------------

function Resolve-TexRoot {
    param([string]$Path)
    # Honor "% !TeX root = master.tex" (relative to the file's directory),
    # following one level of redirection like LaTeXTools does.
    $head = Get-Content -LiteralPath $Path -TotalCount 20 -ErrorAction SilentlyContinue
    foreach ($line in $head) {
        $m = [regex]::Match($line, '^\s*%\s*!TeX\s+root\s*=\s*(.+?)\s*$', 'IgnoreCase')
        if ($m.Success) {
            $rootRel = $m.Groups[1].Value.Trim('"')
            $rootAbs = if ([System.IO.Path]::IsPathRooted($rootRel)) {
                $rootRel
            } else {
                Join-Path (Split-Path -Parent $Path) $rootRel
            }
            if (Test-Path -LiteralPath $rootAbs) {
                return (Resolve-Path -LiteralPath $rootAbs).Path
            }
        }
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Select-Engine {
    param([string]$Source)
    # %!TeX program / %!TeX TS-program wins; otherwise pdflatex, upgraded to
    # lualatex for the classes that require it.
    $engine = 'pdflatex'
    $m = [regex]::Match($Source, '%\s*!TeX\s+(?:TS-)?program\s*=\s*(\w+)', 'IgnoreCase')
    if ($m.Success) { $engine = $m.Groups[1].Value.ToLower() }

    $dc = [regex]::Match($Source, '\\documentclass(?:\[[^\]]*\])?\{(\w[\w-]*)\}')
    $docclass = if ($dc.Success) { $dc.Groups[1].Value } else { '' }
    if ($engine -eq 'pdflatex' -and $LualatexClasses -contains $docclass) {
        Write-Build "TeXLib: \documentclass{$docclass} requires lualatex -- overriding pdflatex."
        $engine = 'lualatex'
    }
    return $engine
}

function Get-Versions {
    param([string]$Source)
    $m = [regex]::Match($Source, '\\(?:exam)?versions\s*\{([^}]+)\}')
    if (-not $m.Success) { return @() }
    return @($m.Groups[1].Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# --- Aux directory (mirror the <<temp>> hashing so aux is shared with the
#     editor build, keeping cross-references warm) -----------------------------

function Resolve-AuxDir {
    param([string]$RootPath, [string]$TexDir)
    $raw = "$($Cfg.AuxMode)".Trim()
    if (-not $raw -or $raw -eq '<<root>>') { return $null }
    if ($raw -eq '<<temp>>') {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($RootPath)
        $hash = ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        $key = $hash.Substring(0, 12)
        $target = Join-Path ([System.IO.Path]::GetTempPath()) (Join-Path 'texlib-aux' $key)
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        return $target
    }
    if ([System.IO.Path]::IsPathRooted($raw)) { return $raw }
    return [System.IO.Path]::GetFullPath((Join-Path $TexDir $raw))
}

# --- Engine / biber execution ----------------------------------------------

function Invoke-Engine {
    param([string[]]$Arguments, [string]$WorkingDir, [string]$Label)
    Write-Build "  > $Label"
    Push-Location $WorkingDir
    try {
        $out = & $Arguments[0] @($Arguments[1..($Arguments.Length - 1)]) 2>&1 | Out-String
    } finally {
        Pop-Location
    }
    $Script:LogLines.Add($out)
    $Script:LastOutput = $out
    return $out
}

function Test-NeedsRerun {
    $out = $Script:LastOutput
    return ($out -match 'Rerun to get .* right\.') -or ($out -match 'Please \(?re\)?(?:run|rerun) Biber')
}

function Test-BiberNeeded {
    param([string]$Jobname, [string]$SearchDir)
    return Test-Path (Join-Path $SearchDir ($Jobname + '.bcf'))
}

function Get-BiberCommand {
    param([string]$Jobname, [string]$AuxDir, [string]$TexDir)
    $cmd = @('biber')
    if ($AuxDir -and $AuxDir -ne $TexDir) {
        $cmd += "--input-directory=$AuxDir"
        $cmd += "--output-directory=$AuxDir"
    }
    $cmd += $Jobname
    return $cmd
}

function Build-One {
    param(
        [string[]]$Base, [string]$Engine, [string]$ModeName,
        [string]$TexName, [string]$BaseName, [string]$TexDir, [string]$AuxDir
    )
    $macro = $ModeMacros[$ModeName]
    if ($macro) {
        $arg = "$macro\input{$TexName}"
        $label = "$Engine [$ModeName]"
    } else {
        $arg = $TexName
        $label = $Engine
    }
    $cmd = $Base + @($arg)

    $run = 1
    Invoke-Engine -Arguments $cmd -WorkingDir $TexDir -Label "$label run $run..." | Out-Null

    $searchDir = if ($AuxDir) { $AuxDir } else { $TexDir }
    if (Test-BiberNeeded -Jobname $BaseName -SearchDir $searchDir) {
        Invoke-Engine -Arguments (Get-BiberCommand -Jobname $BaseName -AuxDir $AuxDir -TexDir $TexDir) `
            -WorkingDir $TexDir -Label 'biber...' | Out-Null
        $run++
        Invoke-Engine -Arguments $cmd -WorkingDir $TexDir -Label "$label rerun $run (post-biber)..." | Out-Null
    }
    while ($run -lt $MaxReruns -and (Test-NeedsRerun)) {
        $run++
        Invoke-Engine -Arguments $cmd -WorkingDir $TexDir -Label "$label rerun $run..." | Out-Null
    }
}

function Build-Version {
    param(
        [string[]]$Base, [string]$Engine, [string]$Version,
        [string]$TexName, [string]$BaseName, [string]$TexDir, [string]$AuxDir
    )
    $jobname = "${BaseName}_${Version}"
    $arg = "\def\Version{$Version}\input{$TexName}"
    $cmd = $Base + @("--jobname=$jobname", $arg)

    $run = 1
    Invoke-Engine -Arguments $cmd -WorkingDir $TexDir -Label "version $Version run $run..." | Out-Null

    $searchDir = if ($AuxDir) { $AuxDir } else { $TexDir }
    if (Test-BiberNeeded -Jobname $jobname -SearchDir $searchDir) {
        Invoke-Engine -Arguments (Get-BiberCommand -Jobname $jobname -AuxDir $AuxDir -TexDir $TexDir) `
            -WorkingDir $TexDir -Label "biber [$Version]..." | Out-Null
        $run++
        Invoke-Engine -Arguments $cmd -WorkingDir $TexDir -Label "version $Version rerun $run (post-biber)..." | Out-Null
    }
    while ($run -lt $MaxReruns -and (Test-NeedsRerun)) {
        $run++
        Invoke-Engine -Arguments $cmd -WorkingDir $TexDir -Label "version $Version rerun $run..." | Out-Null
    }
}

# --- Post-processing --------------------------------------------------------

function Copy-BackFromAux {
    param([string]$AuxDir, [string]$TexDir, [string]$BaseName)
    if (-not $AuxDir -or $AuxDir -eq $TexDir -or -not (Test-Path $AuxDir)) { return }
    foreach ($pat in @("$BaseName*.pdf", "$BaseName*.synctex.gz", "$BaseName*.spl")) {
        Get-ChildItem -Path $AuxDir -Filter $pat -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Copy-Item $_.FullName (Join-Path $TexDir $_.Name) -Force
            } catch {
                Write-Build "TeXLib: could not copy $($_.Name) back to source: $_"
            }
        }
    }
}

function Split-PdfIfSignaled {
    param([string]$BasePath)
    $spl = "$BasePath.spl"
    $pdf = "$BasePath.pdf"
    if (-not (Test-Path $spl) -or -not (Test-Path $pdf)) { return }
    $content = (Get-Content -LiteralPath $spl -Raw).Trim()
    if ($content -notmatch 'split_page=') { return }
    $splitPage = [int]($content.Split('=', 2)[1].Trim())

    # Use pdftk-free splitting via the bundled pdftex tools is overkill; shell
    # out to a tiny inline helper using the .NET-friendly route is unavailable,
    # so defer to pdftk-style: prefer the same approach the builder used (pypdf)
    # only if a Python is present. Otherwise leave the combined PDF and note it.
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        Write-Build "TeXLib: .spl split requested (split_page=$splitPage) but no Python/pypdf available; leaving combined PDF."
        return
    }
    $script = @"
import sys
from pypdf import PdfReader, PdfWriter
src, page, base = sys.argv[1], int(sys.argv[2]), sys.argv[3]
r = PdfReader(src); total = len(r.pages)
if not (0 < page < total): sys.exit(0)
e = PdfWriter()
for i in range(page): e.add_page(r.pages[i])
with open(base + '_Exam.pdf','wb') as f: e.write(f)
s = PdfWriter()
for i in range(page,total): s.add_page(r.pages[i])
with open(base + '_Solutions.pdf','wb') as f: s.write(f)
"@
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'texlib_split.py'
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & $py.Source $tmp $pdf $splitPage $BasePath 2>&1 | Out-String | ForEach-Object { $Script:LogLines.Add($_) }
    Remove-Item $spl -ErrorAction SilentlyContinue
    Write-Build "TeXLib: split into $(Split-Path $BasePath -Leaf)_Exam.pdf / _Solutions.pdf."
}

function Hide-Synctex {
    param([string]$BasePath)
    $synctex = "$BasePath.synctex.gz"
    if (Test-Path $synctex) { attrib +h "$synctex" 2>$null }
}

# --- Open / report ----------------------------------------------------------

function Open-Pdf {
    param([string]$PdfPath)
    if ($NoOpen) { return }
    if (-not (Test-Path $PdfPath)) { return }
    if ($Cfg.SumatraExe -and (Test-Path $Cfg.SumatraExe)) {
        Start-Process -FilePath $Cfg.SumatraExe -ArgumentList "`"$PdfPath`"" | Out-Null
    } else {
        Start-Process -FilePath $PdfPath | Out-Null
    }
}

function Report-Failure {
    param([string]$BaseName, [string]$LogPath)
    Show-Toast -Title "TeXLib build failed: $BaseName" -Message 'Opening the log...'
    if ($LogPath -and (Test-Path $LogPath)) {
        if ($Cfg.SublimeExe -and (Test-Path $Cfg.SublimeExe)) {
            Start-Process -FilePath $Cfg.SublimeExe -ArgumentList "`"$LogPath`"" | Out-Null
        } else {
            Start-Process -FilePath $LogPath | Out-Null
        }
    }
}

# ===========================================================================
# Main
# ===========================================================================

if (-not (Test-Path -LiteralPath $Path)) {
    Show-Toast -Title 'TeXLib build' -Message "File not found: $Path"
    exit 2
}
if ([System.IO.Path]::GetExtension($Path).ToLower() -ne '.tex') {
    Show-Toast -Title 'TeXLib build' -Message 'Selected file is not a .tex file.'
    exit 2
}

Initialize-TexEnvironment

$rootPath = Resolve-TexRoot -Path $Path
$texDir   = Split-Path -Parent $rootPath
$texName  = Split-Path -Leaf $rootPath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($rootPath)
$basePath = Join-Path $texDir $baseName

$source = Get-Content -LiteralPath $rootPath -Raw -ErrorAction SilentlyContinue
if ($null -eq $source) { $source = '' }

$engine  = Select-Engine -Source $source
$auxDir  = Resolve-AuxDir -RootPath $rootPath -TexDir $texDir

$base = @($engine, '-interaction=nonstopmode', '-synctex=1')
if ($engine -in @('lualatex', 'xelatex')) { $base += '-shell-escape' }
if ($auxDir -and $auxDir -ne $texDir) { $base += "-output-directory=$auxDir" }

Write-Build "TeXLib: building $texName [$Mode] with $engine"

try {
    if ($Mode -eq 'allversions') {
        $versions = Get-Versions -Source $source
        if (-not $versions.Count) {
            Write-Build "TeXLib: 'All Versions' requested but no \versions{...} found -- building once."
            Build-One -Base $base -Engine $engine -ModeName 'default' `
                -TexName $texName -BaseName $baseName -TexDir $texDir -AuxDir $auxDir
        } else {
            Write-Build "TeXLib: building $($versions.Count) version(s): $($versions -join ', ')"
            foreach ($v in $versions) {
                Build-Version -Base $base -Engine $engine -Version $v `
                    -TexName $texName -BaseName $baseName -TexDir $texDir -AuxDir $auxDir
            }
        }
    } else {
        Build-One -Base $base -Engine $engine -ModeName $Mode `
            -TexName $texName -BaseName $baseName -TexDir $texDir -AuxDir $auxDir
    }
} catch {
    Write-Build "TeXLib: engine invocation error: $_"
}

# Post-process.
Copy-BackFromAux -AuxDir $auxDir -TexDir $texDir -BaseName $baseName
Split-PdfIfSignaled -BasePath $basePath
Hide-Synctex -BasePath $basePath

# Determine success by the PDF the user expects. For allversions, the first
# version's PDF stands in for "did anything build."
$primaryPdf = if ($Mode -eq 'allversions') {
    $first = (Get-Versions -Source $source | Select-Object -First 1)
    if ($first) { Join-Path $texDir "${baseName}_${first}.pdf" } else { "$basePath.pdf" }
} else {
    "$basePath.pdf"
}

# Persist a build log next to the aux files (or temp) so failures are inspectable.
$logTarget = if ($auxDir) { Join-Path $auxDir "$baseName.texlib-build.log" } `
             else { Join-Path ([System.IO.Path]::GetTempPath()) "$baseName.texlib-build.log" }
try { Set-Content -LiteralPath $logTarget -Value ($Script:LogLines -join "`r`n") -Encoding UTF8 } catch {}

if (Test-Path $primaryPdf) {
    Open-Pdf -PdfPath $primaryPdf
    if ($Mode -eq 'allversions') {
        Show-Toast -Title "TeXLib: built $baseName" -Message "All versions compiled."
    }
    exit 0
} else {
    # Prefer the engine's own .log (richer than our wrapper log) if present.
    $engineLog = "$basePath.log"
    if ($auxDir -and (Test-Path (Join-Path $auxDir "$baseName.log"))) {
        $engineLog = Join-Path $auxDir "$baseName.log"
    }
    $openLog = if (Test-Path $engineLog) { $engineLog } else { $logTarget }
    Report-Failure -BaseName $baseName -LogPath $openLog
    exit 1
}
