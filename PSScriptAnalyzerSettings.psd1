@{
    # Project-wide PSScriptAnalyzer settings for TeXLib-Installer.
    # Picked up automatically by `Invoke-ScriptAnalyzer -Path . -Settings PSScriptAnalyzerSettings.psd1`.

    ExcludeRules = @(
        # We use Write-Host intentionally throughout install.ps1 and the helper
        # scripts. The installer is interactive and prints colored progress to
        # the console as its primary output channel. Write-Output would let the
        # caller pipe the output (irrelevant here, and would break the colored
        # rendering); Write-Information requires explicit -InformationAction by
        # the caller to surface anything. Write-Host is the idiomatic choice
        # for installer-style scripts, and PSScriptAnalyzer's blanket warning
        # against it is well-known to be too aggressive for this use case.
        'PSAvoidUsingWriteHost'
    )

    Severity = @('Error', 'Warning')
}
