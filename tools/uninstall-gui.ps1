<#
.SYNOPSIS
    WPF front-end for uninstall.ps1. Shows what is installed, lets you pick
    what goes, then runs the real uninstaller and shows its progress.

.DESCRIPTION
    A FRONT-END, not a second uninstaller -- the same arrangement as
    install-gui.ps1, and for the same reason. It builds an argument list, runs
    `uninstall.ps1 -Silent` as a child process, and tails that process's output
    into a log pane. Every decision about what to delete stays in
    uninstall.ps1, which is the only thing CI exercises.

    uninstall.ps1 has always offered this choice at the console: interactive
    runs confirm Sublime Text, SumatraPDF, TeX Live and the library separately,
    so you can drop the editor and keep the 6 GB TeX Live tree. All this adds
    is a window over the switches that choice already had -- -KeepSublime,
    -KeepSumatra, -KeepTeXLive, -RemoveLibrary, -RemoveJunction.

    Tick boxes are phrased as "remove X" while the switches they map to are
    phrased as "keep X". The inversion is deliberate: a checked box meaning
    "this gets deleted" is the reading people expect from an uninstaller, and
    getting that backwards deletes a 6 GB tree someone meant to keep.

.NOTES
    ASCII-only, for the same Windows PowerShell 5.1 decoding reason as
    install.ps1 and install-gui.ps1. CI's gui job covers it.
#>
[CmdletBinding()]
param(
    [string]$InstallPath = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

$ScriptDir    = $PSScriptRoot
$UninstallPs1 = Join-Path $ScriptDir "uninstall.ps1"

if (-not (Test-Path $UninstallPs1)) {
    [Windows.MessageBox]::Show(
        "Could not find uninstall.ps1 next to this script.`n`nExpected: $UninstallPs1`n`nThe release folder is incomplete -- re-extract the ZIP.",
        "TeXLib Uninstaller", 'OK', 'Error') | Out-Null
    exit 11
}

$UninstallerVersion = "?"
try {
    $m = Select-String -Path $UninstallPs1 -Pattern '^\$UninstallerVersion\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($m) { $UninstallerVersion = $m.Matches[0].Groups[1].Value }
} catch { $null = $_ }

if (-not $InstallPath) { $InstallPath = Join-Path $env:LOCALAPPDATA "TeXLib" }

# Phase markers, same contract as install-gui.ps1: a marker printed literally by
# uninstall.ps1 is checked as a substring by CI; one composed at runtime carries
# an Emit naming the construct that prints it.
# Ordered as uninstall.ps1 actually runs: close locking programs, remove the
# components, then the junction, the Installed Apps entry, shortcuts, PATH and
# finally the file associations. The four component lines are composed from a
# -Label parameter ("Removing $Label ($Path)...") and so appear nowhere in
# uninstall.ps1's source, hence the Emit -- same contract as install-gui.ps1.
$Phases = @(
    @{ Match = "programs are running";   Label = "Closing programs that hold file locks"; Pct = 5 },
    @{ Match = "Removing Sublime Text";  Label = "Removing Sublime Text";        Pct = 20;
       Emit  = 'Write-Host "Removing $Label ($Path)..."' },
    @{ Match = "Removing SumatraPDF";    Label = "Removing SumatraPDF";          Pct = 30;
       Emit  = 'Write-Host "Removing $Label ($Path)..."' },
    @{ Match = "Removing TeX Live";      Label = "Removing TeX Live";            Pct = -1;
       Emit  = 'Write-Host "Removing $Label ($Path)..."' },
    @{ Match = "Removing TeXLib library"; Label = "Removing the TeXLib library"; Pct = 72;
       Emit  = 'Write-Host "Removing $Label ($Path)..."' },
    @{ Match = "Removing user-root junction"; Label = "Retiring the user-root junction"; Pct = 78 },
    @{ Match = "Installed Apps entry";   Label = "Removing the Installed Apps entry"; Pct = 82 },
    @{ Match = "Removing shortcuts";     Label = "Removing shortcuts";           Pct = 88 },
    @{ Match = "Cleaning user PATH";     Label = "Cleaning up PATH";             Pct = 92 },
    @{ Match = "Removing file associations"; Label = "Removing file associations"; Pct = 96 }
)

$ExitMeanings = @{
    1 = "Nothing to uninstall was found at that location."
    2 = "Something could not be deleted. A file is probably still in use -- close Sublime Text and SumatraPDF and try again."
}

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TeXLib Uninstaller" Width="760" Height="620"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
        Background="#FFF7F7F9" FontFamily="Segoe UI" FontSize="13">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#FF5A2330" Padding="20,16">
      <StackPanel>
        <TextBlock Text="Uninstall TeXLib" Foreground="White" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock Foreground="#FFE0BFC6" Margin="0,2,0,0"
                   Text="Choose what to remove. Anything left unticked stays exactly where it is."/>
      </StackPanel>
    </Border>

    <ScrollViewer x:Name="PageOptions" Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="20,18">
      <StackPanel>
        <TextBlock Text="Install location" FontWeight="SemiBold" Margin="0,0,0,4"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="TxtInstallPath" Grid.Column="0" Padding="6,5" VerticalContentAlignment="Center"/>
          <Button x:Name="BtnBrowse" Grid.Column="1" Content="Browse..." Margin="8,0,0,0" Padding="14,5"/>
        </Grid>
        <TextBlock x:Name="LblFound" Foreground="#FF5A6672" TextWrapping="Wrap" Margin="0,5,0,16"/>

        <TextBlock Text="Remove" FontWeight="SemiBold" Margin="0,0,0,6"/>
        <CheckBox x:Name="ChkSublime" Margin="0,3,0,0"/>
        <CheckBox x:Name="ChkSumatra" Margin="0,3,0,0"/>
        <CheckBox x:Name="ChkTexLive" Margin="0,3,0,0"/>
        <CheckBox x:Name="ChkLibrary" Margin="0,3,0,0"/>
        <TextBlock x:Name="LblLibraryNote" Foreground="#FF5A6672" TextWrapping="Wrap" Margin="22,3,0,12"/>

        <Expander x:Name="ExpAdvanced" Header="Advanced" Margin="0,4,0,12">
          <StackPanel Margin="0,10,0,0">
            <CheckBox x:Name="ChkJunction" Content="Also remove the %USERPROFILE%\TeXLib junction"/>
            <TextBlock Foreground="#FF5A6672" TextWrapping="Wrap" Margin="22,4,0,10"
                       Text="Left alone by default when the uninstaller cannot prove this installer created it. A developer machine often has one pointing at a real library, and unlinking it breaks every TeX build that resolves through that path. Check where it points before ticking this."/>
            <CheckBox x:Name="ChkForce" Content="Close running Sublime Text / SumatraPDF without asking"/>
            <TextBlock Foreground="#FF5A6672" TextWrapping="Wrap" Margin="22,4,0,0"
                       Text="They hold file locks that would otherwise fail the removal. Save your work first."/>
          </StackPanel>
        </Expander>

        <Border x:Name="PanelWarn" Background="#FFFDE7E9" BorderBrush="#FFE2A2AC" BorderThickness="1"
                Padding="12,10" CornerRadius="3">
          <TextBlock x:Name="LblWarn" TextWrapping="Wrap" Foreground="#FF6B2733"/>
        </Border>
      </StackPanel>
    </ScrollViewer>

    <Grid x:Name="PageProgress" Grid.Row="1" Margin="20,18" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <TextBlock x:Name="LblPhase" Grid.Row="0" FontWeight="SemiBold" FontSize="15" Text="Starting..."/>
      <ProgressBar x:Name="Bar" Grid.Row="1" Height="18" Margin="0,10,0,0" Minimum="0" Maximum="100" Value="0"/>
      <TextBlock x:Name="LblElapsed" Grid.Row="2" Foreground="#FF5A6672" Margin="0,6,0,10" Text=""/>
      <Border Grid.Row="3" BorderBrush="#FFD8DCE2" BorderThickness="1" Background="White">
        <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <TextBox x:Name="TxtLog" IsReadOnly="True" BorderThickness="0" Background="White"
                   FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" Padding="8"/>
        </ScrollViewer>
      </Border>
    </Grid>

    <Border Grid.Row="2" Background="#FFEFF1F4" BorderBrush="#FFD8DCE2" BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <TextBlock x:Name="LblFooter" VerticalAlignment="Center" Foreground="#FF5A6672"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnLog" Content="Open log" Padding="14,6" Margin="0,0,8,0" Visibility="Collapsed"/>
          <Button x:Name="BtnCancel" Content="Cancel" Padding="16,6" Margin="0,0,8,0"/>
          <Button x:Name="BtnPrimary" Content="Uninstall" Padding="24,6" FontWeight="SemiBold"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$Win    = [Windows.Markup.XamlReader]::Load($reader)

$TxtInstallPath = $Win.FindName("TxtInstallPath")
$BtnBrowse      = $Win.FindName("BtnBrowse")
$LblFound       = $Win.FindName("LblFound")
$ChkSublime     = $Win.FindName("ChkSublime")
$ChkSumatra     = $Win.FindName("ChkSumatra")
$ChkTexLive     = $Win.FindName("ChkTexLive")
$ChkLibrary     = $Win.FindName("ChkLibrary")
$LblLibraryNote = $Win.FindName("LblLibraryNote")
$ChkJunction    = $Win.FindName("ChkJunction")
$ChkForce       = $Win.FindName("ChkForce")
$PanelWarn      = $Win.FindName("PanelWarn")
$LblWarn        = $Win.FindName("LblWarn")
$PageOptions    = $Win.FindName("PageOptions")
$PageProgress   = $Win.FindName("PageProgress")
$LblPhase       = $Win.FindName("LblPhase")
$Bar            = $Win.FindName("Bar")
$LblElapsed     = $Win.FindName("LblElapsed")
$TxtLog         = $Win.FindName("TxtLog")
$LogScroller    = $Win.FindName("LogScroller")
$BtnPrimary     = $Win.FindName("BtnPrimary")
$BtnCancel      = $Win.FindName("BtnCancel")
$BtnLog         = $Win.FindName("BtnLog")
$LblFooter      = $Win.FindName("LblFooter")

$Win.Title = "TeXLib Uninstaller $UninstallerVersion"
$LblFooter.Text = "Version $UninstallerVersion"
$TxtInstallPath.Text = $InstallPath

$S = @{
    Proc = $null; OutFile = ""; ErrFile = ""; Offset = 0
    Timer = $null; Running = $false; Cancelled = $false; LogPath = ""
    OutStream = $null; ErrStream = $null
}

$GuiLog = Join-Path $env:TEMP ("TeXLib-guiuninstall-session-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
function Write-GuiLog([string]$Text) {
    try { Add-Content -Path $GuiLog -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Text) -Encoding UTF8 } catch { $null = $_ }
}
Write-GuiLog "uninstall-gui starting (PID $PID)"

function ConvertTo-Arg([string]$Value) {
    # Same quoting as install-gui.ps1: ProcessStartInfo.ArgumentList does not
    # exist on the .NET Framework that Windows PowerShell 5.1 runs on, so the
    # Arguments string is built by hand. An install path with a space, or a
    # trailing backslash typed into the box, both break a naive join.
    if ($Value -eq "") { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Get-FolderSizeText {
    # Capped, same as the installer's: enumerating a 6 GB TeX Live tree on the
    # UI thread would freeze the window, so give up quietly instead.
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $bytes = 0
        foreach ($f in [IO.Directory]::EnumerateFiles($Path, '*', 'AllDirectories')) {
            $bytes += (New-Object IO.FileInfo $f).Length
            if ($sw.ElapsedMilliseconds -gt 1200) { return "" }
        }
        if ($bytes -ge 1GB) { return (" ({0:N1} GB)" -f ($bytes / 1GB)) }
        return (" ({0:N0} MB)" -f ($bytes / 1MB))
    } catch { return "" }
}

function Update-Detection {
    $root = $TxtInstallPath.Text.Trim()
    $sublime = Join-Path $root "Sublime Text\sublime_text.exe"
    $sumatra = Join-Path $root "Sumatra"
    $texRoot = Join-Path $root "TexLive"
    $library = Join-Path $root "Library"

    $hasSublime = Test-Path $sublime
    $hasSumatra = (Test-Path $sumatra) -and @(Get-ChildItem $sumatra -Filter "SumatraPDF*.exe" -ErrorAction SilentlyContinue).Count -gt 0
    $texYear = if (Test-Path $texRoot) { Get-ChildItem $texRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 } else { $null }
    $hasTexLive = ($null -ne $texYear)
    $hasLibrary = Test-Path $library

    foreach ($pair in @(
        @{ Box = $ChkSublime; Has = $hasSublime; Text = "Sublime Text$(Get-FolderSizeText (Join-Path $root 'Sublime Text'))" },
        @{ Box = $ChkSumatra; Has = $hasSumatra; Text = "SumatraPDF$(Get-FolderSizeText $sumatra)" },
        @{ Box = $ChkTexLive; Has = $hasTexLive; Text = "TeX Live$(if ($texYear) { " $($texYear.Name)" })$(Get-FolderSizeText $texRoot)" },
        @{ Box = $ChkLibrary; Has = $hasLibrary; Text = "The TeXLib library$(Get-FolderSizeText $library)" }
    )) {
        $pair.Box.Content    = $pair.Text
        $pair.Box.IsEnabled  = $pair.Has
        # Default to removing what is there -- this is an uninstaller, and the
        # console's own defaults remove the programs and a library inside the
        # install root. Nothing absent is ever pre-ticked.
        $pair.Box.IsChecked  = $pair.Has
        if (-not $pair.Has) { $pair.Box.Content = "$($pair.Text) - not installed here" }
    }

    $LblLibraryNote.Text = if ($hasLibrary) {
        "This is the deployed copy inside the install root. Your own documents are not stored here, but anything you edited in place is."
    } else { "" }

    $anything = $hasSublime -or $hasSumatra -or $hasTexLive -or $hasLibrary
    $LblFound.Text = if ($anything) {
        "Found a TeXLib install here."
    } else {
        "Nothing recognisable as a TeXLib install was found at this path. Check the location, or there may be nothing left to remove."
    }
    $BtnPrimary.IsEnabled = $anything
    Update-Warning
}

function Update-Warning {
    $going = @()
    if ($ChkSublime.IsChecked -and $ChkSublime.IsEnabled) { $going += "Sublime Text" }
    if ($ChkSumatra.IsChecked -and $ChkSumatra.IsEnabled) { $going += "SumatraPDF" }
    if ($ChkTexLive.IsChecked -and $ChkTexLive.IsEnabled) { $going += "TeX Live" }
    if ($ChkLibrary.IsChecked -and $ChkLibrary.IsEnabled) { $going += "the TeXLib library" }

    if ($going.Count -eq 0) {
        $LblWarn.Text = "Nothing is ticked, so nothing will be removed. The shortcuts, file associations and PATH entry are cleaned up either way."
    } else {
        $t = "Will remove: $($going -join ', ')."
        if ($ChkTexLive.IsChecked -and $ChkTexLive.IsEnabled) {
            $t += " Reinstalling TeX Live later means re-downloading several GB from CTAN, typically 30-60 minutes -- untick it to keep the tree and save that."
        }
        $LblWarn.Text = $t
    }
}

foreach ($b in @($ChkSublime, $ChkSumatra, $ChkTexLive, $ChkLibrary)) {
    $b.Add_Checked({ Update-Warning })
    $b.Add_Unchecked({ Update-Warning })
}

$BtnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose the TeXLib install to remove"
    if (Test-Path $TxtInstallPath.Text) { $dlg.SelectedPath = $TxtInstallPath.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TxtInstallPath.Text = $dlg.SelectedPath
        Update-Detection
    }
})
$TxtInstallPath.Add_LostFocus({ Update-Detection })

function Add-Log([string]$Text) {
    if (-not $Text) { return }
    $TxtLog.AppendText($Text)
    $LogScroller.ScrollToEnd()
}

function Set-Phase([string]$Label, [int]$Pct) {
    $LblPhase.Text = $Label
    if ($Pct -lt 0) { $Bar.IsIndeterminate = $true }
    else {
        $Bar.IsIndeterminate = $false
        if ($Pct -gt $Bar.Value) { $Bar.Value = $Pct }
    }
}

function Read-NewOutput {
    if (-not (Test-Path $S.OutFile)) { return "" }
    $chunk = ""
    try {
        $fs = [IO.File]::Open($S.OutFile, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -gt $S.Offset) {
                $null = $fs.Seek($S.Offset, 'Begin')
                $buf = New-Object byte[] ($fs.Length - $S.Offset)
                $read = $fs.Read($buf, 0, $buf.Length)
                $S.Offset += $read
                $chunk = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
            }
        } finally { $fs.Dispose() }
    } catch { $null = $_ }
    return $chunk
}

function Complete-Run([int]$Code) {
    $S.Running = $false
    if ($S.Timer) { $S.Timer.Stop() }
    $Bar.IsIndeterminate = $false
    $BtnCancel.Visibility = 'Collapsed'
    $BtnLog.Visibility = 'Visible'
    $BtnPrimary.Content = "Close"
    $BtnPrimary.IsEnabled = $true

    if ($S.Cancelled) {
        $Bar.Value = 0
        $LblPhase.Text = "Cancelled"
        $LblElapsed.Text = "Whatever had already been removed is gone; the rest is untouched. Re-run to finish."
        $LblFooter.Text = "Cancelled"
        return
    }
    if ($Code -eq 0) {
        $Bar.Value = 100
        $LblPhase.Text = "Uninstall complete"
        $LblElapsed.Text = "Anything you chose to keep is still in place."
        $LblFooter.Text = "Done"
    } else {
        $Bar.Value = 0
        $LblPhase.Text = "Uninstall failed (exit code $Code)"
        $LblElapsed.Text = if ($ExitMeanings.ContainsKey($Code)) { $ExitMeanings[$Code] } else { "See the log below for what went wrong." }
        $LblFooter.Text = "Failed -- exit code $Code"
    }
}

function Stop-Child {
    if ($S.Proc -and -not $S.Proc.HasExited) {
        try { & taskkill.exe /PID $S.Proc.Id /T /F 2>&1 | Out-Null } catch { $null = $_ }
    }
}

function Start-Uninstall {
    $root = $TxtInstallPath.Text.Trim()
    if (-not $root) {
        [Windows.MessageBox]::Show("Choose the install location first.", "TeXLib Uninstaller", 'OK', 'Warning') | Out-Null
        return
    }

    # Ticked means REMOVE; the switches mean KEEP. Invert here, once, where it
    # is easy to check -- and only for components that are actually present, so
    # an absent one never contributes a switch.
    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $UninstallPs1,
        "-Silent", "-InstallPath", $root
    )
    if (-not ($ChkSublime.IsChecked -and $ChkSublime.IsEnabled)) { $argList += "-KeepSublime" }
    if (-not ($ChkSumatra.IsChecked -and $ChkSumatra.IsEnabled)) { $argList += "-KeepSumatra" }
    if (-not ($ChkTexLive.IsChecked -and $ChkTexLive.IsEnabled)) { $argList += "-KeepTeXLive" }
    if ($ChkLibrary.IsChecked -and $ChkLibrary.IsEnabled)        { $argList += "-RemoveLibrary" }
    if ($ChkJunction.IsChecked)                                  { $argList += "-RemoveJunction" }
    if ($ChkForce.IsChecked)                                     { $argList += "-Force" }

    $going = @()
    if ($ChkSublime.IsChecked -and $ChkSublime.IsEnabled) { $going += "Sublime Text" }
    if ($ChkSumatra.IsChecked -and $ChkSumatra.IsEnabled) { $going += "SumatraPDF" }
    if ($ChkTexLive.IsChecked -and $ChkTexLive.IsEnabled) { $going += "TeX Live" }
    if ($ChkLibrary.IsChecked -and $ChkLibrary.IsEnabled) { $going += "the TeXLib library" }
    $summary = if ($going.Count) { $going -join ", " } else { "nothing (shortcuts, associations and PATH only)" }
    $ans = [Windows.MessageBox]::Show(
        "Remove $summary from`n$root ?`n`nThis cannot be undone.",
        "TeXLib Uninstaller", 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $S.OutFile = Join-Path $env:TEMP "TeXLib-guiuninstall-$stamp.out.log"
    $S.ErrFile = Join-Path $env:TEMP "TeXLib-guiuninstall-$stamp.err.log"
    $S.LogPath = $S.OutFile
    $S.Offset = 0
    $S.Cancelled = $false

    $PageOptions.Visibility = 'Collapsed'
    $PageProgress.Visibility = 'Visible'
    $BtnPrimary.IsEnabled = $false
    $BtnPrimary.Content = "Removing..."
    Set-Phase "Starting the uninstaller" 2
    Add-Log ("> uninstall.ps1 " + (($argList | Select-Object -Skip 5) -join " ") + "`r`n`r`n")

    # Identical launch mechanics to install-gui.ps1, and for the same reasons:
    # CreateNoWindow is the only thing that actually suppresses the child's
    # console (Start-Process -WindowStyle Hidden is ignored once
    # UseShellExecute is $false); -File so the script's `exit N` survives as the
    # process exit code; pipes copied to files by .NET rather than PowerShell
    # redirection, which writes UTF-16LE in 5.1 and would render every path as
    # "C : \ U s e r s" in the log pane.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "powershell.exe"
    $psi.Arguments              = (($argList | ForEach-Object { ConvertTo-Arg $_ }) -join " ")
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    try {
        Write-GuiLog ("starting child: " + ($argList -join " "))
        $S.Proc = [System.Diagnostics.Process]::Start($psi)
        # Touch .Handle while the child is alive or .ExitCode comes back $null,
        # which coerces to 0 and reports a failed uninstall as a good one.
        $null = $S.Proc.Handle
        $S.OutStream = [IO.File]::Open($S.OutFile, 'Create', 'Write', 'ReadWrite')
        $S.ErrStream = [IO.File]::Open($S.ErrFile, 'Create', 'Write', 'ReadWrite')
        $null = $S.Proc.StandardOutput.BaseStream.CopyToAsync($S.OutStream)
        $null = $S.Proc.StandardError.BaseStream.CopyToAsync($S.ErrStream)
    } catch {
        Write-GuiLog "failed to start child: $_"
        Add-Log "Could not start the uninstaller: $_`r`n"
        Complete-Run 11
        return
    }
    $S.Running = $true

    $S.Timer = New-Object Windows.Threading.DispatcherTimer
    $S.Timer.Interval = [TimeSpan]::FromMilliseconds(400)
    # The whole tick is wrapped: an exception escaping a DispatcherTimer handler
    # goes to WPF's unhandled-exception path and tears the process down, so the
    # window vanishes mid-uninstall with no message and no trace.
    $S.Timer.Add_Tick({
      try {
        $chunk = Read-NewOutput
        if ($chunk) {
            Add-Log $chunk
            foreach ($line in ($chunk -split "`r?`n")) {
                foreach ($p in $Phases) {
                    # .Contains, never -like: a marker carrying [ ] * ? would be
                    # read as wildcard syntax and could never match.
                    if ($line.Contains($p.Match)) { Set-Phase $p.Label $p.Pct }
                }
            }
        }
        if ($S.Proc.HasExited) {
            Start-Sleep -Milliseconds 150
            Add-Log (Read-NewOutput)
            foreach ($s in @($S.OutStream, $S.ErrStream)) {
                if ($s) { try { $s.Dispose() } catch { $null = $_ } }
            }
            $S.OutStream = $null; $S.ErrStream = $null
            try {
                if ((Test-Path $S.ErrFile) -and (Get-Item $S.ErrFile).Length -gt 0) {
                    Add-Log "`r`n--- stderr ---`r`n"
                    Add-Log ([IO.File]::ReadAllText($S.ErrFile))
                }
            } catch { $null = $_ }
            $code = if ($null -ne $S.Proc.ExitCode) { [int]$S.Proc.ExitCode } else { -1 }
            Write-GuiLog "child exited with $code"
            Complete-Run $code
        }
      } catch {
        Write-GuiLog "tick failed: $_"
        Add-Log "`r`n[gui] Stopped watching the uninstaller: $_`r`n[gui] Session log: $GuiLog`r`n"
        Complete-Run(-1)
      }
    })
    $S.Timer.Start()
}

$BtnPrimary.Add_Click({
    if ($S.Running) { return }
    if ($BtnPrimary.Content -eq "Close") { $Win.Close(); return }
    Start-Uninstall
})

$BtnCancel.Add_Click({
    if (-not $S.Running) { $Win.Close(); return }
    $ans = [Windows.MessageBox]::Show(
        "Stop the uninstall?`n`nWhatever has already been removed stays removed.",
        "TeXLib Uninstaller", 'YesNo', 'Warning')
    if ($ans -eq 'Yes') { $S.Cancelled = $true; Stop-Child }
})

$BtnLog.Add_Click({
    if ($S.LogPath -and (Test-Path $S.LogPath)) { Start-Process notepad.exe $S.LogPath }
})

$Win.Add_Closing({
    param($sender, $e)
    if ($S.Running) {
        $ans = [Windows.MessageBox]::Show("The uninstall is still running. Close and stop it?",
               "TeXLib Uninstaller", 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { $e.Cancel = $true; return }
        $S.Cancelled = $true
        Stop-Child
    }
})

Update-Detection
$null = $Win.ShowDialog()
