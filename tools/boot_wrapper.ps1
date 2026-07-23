<#
.SYNOPSIS
    Bootstrap wrapper for install.ps1 / uninstall.ps1 (selected by -Kind).
    Captures ALL output (even errors that happen before the inner script's
    Start-Transcript runs) and guarantees the console window stays open on
    failure.

.DESCRIPTION
    The bare .bat -> PowerShell -File invocation has two failure modes that
    eat your error message:

      1. If the inner script throws before its Start-Transcript runs
         (param-binding issue, locked %LOCALAPPDATA%, environment-variable
         corruption, ...), no log file is created. The user sees red text, the
         window closes, and there is nothing to diagnose.

      2. Even if a log IS written, the .bat does not pause on non-zero exit,
         so a double-click launch closes the window before the user can read
         the error.

    This wrapper fixes both:

      - Tee-Object captures the inner script's combined output stream (every
        PowerShell stream merged via *>&1) into a boot log in %TEMP% that is
        created BEFORE the inner script starts.
      - A top-level try/catch turns any uncaught PowerShell exception into a
        reportable exit code 99 instead of an unrecoverable crash.
      - On any non-zero exit, the wrapper prints the boot-log path and waits
        for the user before returning to the .bat.

.PARAMETER Kind
    'install' or 'uninstall' -- selects the sibling <Kind>.ps1 to run and the
    label used in messages and the boot-log name.

.NOTES
    Sets $env:TEXLIB_INSTALLER_WRAPPED = "1" so the inner script's
    Stop-Installer / Stop-Uninstaller knows not to double up its own
    "Press Enter to close" prompt.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('install', 'uninstall')]
    [string]$Kind,

    [Parameter(ValueFromRemainingArguments = $true)]
    $InnerArgs
)

$Label = if ($Kind -eq 'install') { 'Installer' } else { 'Uninstaller' }

# Tell the inner script we're handling user prompts + exit-code surfacing.
$env:TEXLIB_INSTALLER_WRAPPED = "1"

# tools\boot_wrapper.ps1 lives one directory below the inner scripts.
$ScriptDir = Split-Path $PSScriptRoot -Parent

# Boot log in %TEMP% so a locked install dir does not prevent logging. The
# timestamp prevents collisions if a coworker re-runs after a failure.
$Stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$BootLog = Join-Path $env:TEMP "TeXLib-$Label-boot-$Stamp.log"

# Eagerly touch the boot log so a hard crash inside the pipeline still leaves
# a file behind for the user to attach to a bug report.
try { New-Item -ItemType File -Path $BootLog -Force | Out-Null } catch { $null = $_ }

Write-Host ""
Write-Host "Boot log: $BootLog" -ForegroundColor Gray
Write-Host ""

# -----------------------------------------------------------------------------
# Argument forwarding
# -----------------------------------------------------------------------------
# ValueFromRemainingArguments hands us a flat ARRAY of tokens, and `& $script
# @array` splats them POSITIONALLY -- array splatting never re-interprets
# "-Silent" as a parameter name. Only a HASHTABLE splat binds named parameters.
# So every documented `install.bat -Flag` form was broken: `-Doctor` landed in
# install.ps1's positional [string]$InstallPath (running a full install into a
# folder named "-Doctor"), and uninstall.ps1, having no positional parameter to
# absorb it, aborted outright.
#
# Rebuild the tokens into a named hashtable + positional array, using the inner
# script's OWN parameter metadata to know which names are switches (and so do
# not consume the next token). Kept as a named function, with the metadata
# passed in rather than looked up, so unit-helpers can lift it out by AST and
# test the binding without executing anything.
function ConvertTo-InnerArgumentBinding {
    param(
        [object[]]$Tokens,
        [hashtable]$IsSwitch   # parameter name -> [bool] "is a switch"
    )

    $named = @{}
    $positional = @()
    if (-not $Tokens) { return @{ Named = $named; Positional = $positional } }
    if (-not $IsSwitch) { $IsSwitch = @{} }

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $tok = $Tokens[$i]

        # Anything that isn't a "-name" token is positional.
        if ($tok -isnot [string] -or $tok.Length -lt 2 -or -not $tok.StartsWith('-')) {
            $positional += $tok
            continue
        }

        $name = $tok.Substring(1)
        # PowerShell's -Name:Value form.
        $inline = $null
        $colon = $name.IndexOf(':')
        if ($colon -ge 0) {
            $inline = $name.Substring($colon + 1)
            $name   = $name.Substring(0, $colon)
        }
        if (-not $name) { $positional += $tok; continue }

        # Resolve against the real parameter names: exact (case-insensitive)
        # first, then a UNIQUE prefix, matching how PowerShell itself binds.
        # An unresolved name is still forwarded as named, so the inner script
        # produces its own clear "parameter cannot be found" error rather than
        # silently swallowing the token as a positional value.
        $key = @($IsSwitch.Keys | Where-Object { $_ -ieq $name }) | Select-Object -First 1
        if (-not $key) {
            $prefix = @($IsSwitch.Keys | Where-Object { $_ -ilike "$name*" })
            if ($prefix.Count -eq 1) { $key = $prefix[0] }
        }
        $bindAs = if ($key) { $key } else { $name }

        if ($null -ne $inline) {
            # -Switch:$false is a real idiom; coerce so the hashtable splat gets
            # a boolean rather than a non-empty (hence always-true) string.
            if ($key -and $IsSwitch[$key]) {
                $named[$bindAs] = @('false', '$false', '0') -notcontains $inline.Trim().ToLowerInvariant()
            } else {
                $named[$bindAs] = $inline
            }
            continue
        }

        if ($key -and $IsSwitch[$key]) { $named[$bindAs] = $true; continue }

        # Value-taking (or unknown): consume the next token unless it is itself
        # a flag or we are at the end.
        $next = if ($i + 1 -lt $Tokens.Count) { $Tokens[$i + 1] } else { $null }
        if ($null -ne $next -and -not ($next -is [string] -and $next.Length -ge 2 -and $next.StartsWith('-'))) {
            $named[$bindAs] = $next
            $i++
        } else {
            $named[$bindAs] = $true
        }
    }

    return @{ Named = $named; Positional = $positional }
}

$RC = 0
try {
    $InnerScript = Join-Path $ScriptDir "$Kind.ps1"
    if (-not (Test-Path $InnerScript)) {
        throw "$Kind.ps1 not found at $InnerScript. Is this a complete release archive?"
    }

    # A no-arg launch (the normal double-click path) leaves $InnerArgs = $null
    # under WinPS 5.1 -- ValueFromRemainingArguments binds nothing to $null, not
    # an empty array. Splatting $null passes a single positional $null to the
    # inner script; uninstall.ps1 has only [switch]$Silent (no positional-capable
    # param), so it aborts with "A positional parameter cannot be found that
    # accepts argument '$null'" BEFORE doing anything. (install.ps1 dodged this
    # by luck -- its [string]$InstallPath positional absorbed the stray $null.)
    # Coerce to an empty array so the splat forwards zero args, as intended.
    if ($null -eq $InnerArgs) { $InnerArgs = @() }

    # Ask the inner script which of its parameters are switches. If this fails
    # for any reason, fall back to the old positional splat: a boot wrapper must
    # degrade rather than refuse to launch.
    $IsSwitch = @{}
    try {
        $InnerCmd = Get-Command -Name $InnerScript -CommandType ExternalScript -ErrorAction Stop
        foreach ($kv in $InnerCmd.Parameters.GetEnumerator()) {
            $IsSwitch[$kv.Key] = [bool]$kv.Value.SwitchParameter
        }
    } catch {
        Write-Host "  [warn] Could not read $Kind.ps1 parameters ($($_.Exception.Message));" -ForegroundColor Yellow
        Write-Host "         forwarding arguments positionally." -ForegroundColor Yellow
    }

    # *>&1 merges every output stream into the success stream so Tee-Object
    # captures host writes, warnings, verbose, AND error records to the boot
    # log without losing colors on the live console.
    if ($IsSwitch.Count -gt 0) {
        $Binding    = ConvertTo-InnerArgumentBinding -Tokens $InnerArgs -IsSwitch $IsSwitch
        $NamedArgs  = $Binding.Named
        $PositionalArgs = @($Binding.Positional)
        & $InnerScript @NamedArgs @PositionalArgs *>&1 | Tee-Object -FilePath $BootLog
    } else {
        & $InnerScript @InnerArgs *>&1 | Tee-Object -FilePath $BootLog
    }
    $RC = $LASTEXITCODE
    if ($null -eq $RC) { $RC = 0 }

} catch {
    $msg = @"

FATAL: wrapper caught an uncaught exception from $Kind.ps1:

$($_ | Out-String)

Script stack trace:
$($_.ScriptStackTrace)
"@
    Add-Content -Path $BootLog -Value $msg
    Write-Host $msg -ForegroundColor Red
    $RC = 99
}

if ($RC -ne 0) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " $Label exited with code $RC."                                 -ForegroundColor Red
    Write-Host ""
    Write-Host " Boot log (always present, captures pre-transcript errors):"   -ForegroundColor Yellow
    Write-Host "   $BootLog"                                                   -ForegroundColor Yellow
    if ($Kind -eq 'install') {
        Write-Host ""
        Write-Host " Install log (if Start-Transcript reached it):"            -ForegroundColor Yellow
        Write-Host "   %LOCALAPPDATA%\TeXLib\Logs\install-<timestamp>.log"     -ForegroundColor Yellow
        Write-Host "   (or %TEMP%\TeXLib-Install\install-<timestamp>.log if the" -ForegroundColor Yellow
        Write-Host "    install dir didn't exist yet)"                         -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host " Please attach the boot log when reporting:"                   -ForegroundColor Yellow
    Write-Host "   https://github.com/landonfox00/TeXLib-Installer/issues"     -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "Boot log saved to: $BootLog" -ForegroundColor Gray
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
exit $RC
