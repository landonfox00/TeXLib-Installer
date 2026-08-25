<#
.SYNOPSIS
    WPF front-end for install.ps1. Collects options, then runs the real
    installer and shows its progress.

.DESCRIPTION
    This is a FRONT-END, not a second installer. It builds an argument list,
    launches `install.ps1 -Silent` as a child process, and tails that process's
    output into a log pane. Every decision about what to install, what to
    verify, and what to write to the machine stays in install.ps1, which is
    still the only thing CI exercises. If the two ever disagree, install.ps1 is
    right.

    Why -Silent rather than driving the interactive prompts: the prompts exist
    to ask a console user questions the GUI has already answered in its options
    panel, and there is no supported way to feed Read-Host from a parent
    process without a pty. -Silent takes the documented safe defaults (skip any
    component already installed, abort on hash mismatch), which is exactly what
    the GUI wants.

    Why the output is tailed from a FILE rather than read from an event:
    Register-ObjectEvent handlers do not run while a WPF message loop is
    pumping (ShowDialog blocks the runspace, and PowerShell events need the
    pipeline to be idle to fire), so the usual OutputDataReceived pattern
    silently delivers nothing until the window closes. Redirecting the child's
    stdout to a temp file and reading the new bytes on a DispatcherTimer sits
    entirely inside the UI thread and has no such failure mode.

.PARAMETER InstallPath
    Pre-seed the install location field. Same meaning as install.ps1's.

.PARAMETER TeXLibPath
    Pre-seed the library location field. Same meaning as install.ps1's.

.PARAMETER TexLiveScheme
    Pre-select the TeX Live scheme. Same meaning as install.ps1's.

.NOTES
    ASCII-only on purpose. install.bat launches Windows PowerShell 5.1, which
    decodes a BOM-less UTF-8 script as Windows-1252 -- the bug that shipped in
    v0.5.0. Keeping this file ASCII means the question never arises. CI's
    encoding-guard covers it.
#>
[CmdletBinding()]
param(
    [string]$InstallPath = "",
    [string]$TeXLibPath = "",
    [ValidateSet('full', 'medium', 'basic')]
    [string]$TexLiveScheme = 'full',
    # Build the real window, drive the real controls through an
    # argument-construction truth table, print PASS/FAIL per case, and exit
    # without showing the dialog or spawning a child. This is what lets CI
    # EXECUTE the file a user double-clicks instead of only parsing it.
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# Diagnostic log, opened before anything else can fail. boot_wrapper.ps1 exists
# because a console window that closes on error leaves nothing to diagnose; a
# GUI window that vanishes is the same failure with less warning, so the same
# rule applies here. Every unhandled error lands in this file whether or not
# the window survives long enough to show it.
$GuiLog = Join-Path $env:TEMP ("TeXLib-gui-session-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
function Write-GuiLog([string]$Text) {
    try { Add-Content -Path $GuiLog -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Text) -Encoding UTF8 } catch { $null = $_ }
}
Write-GuiLog "install-gui starting (PID $PID)"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

$ScriptDir   = $PSScriptRoot
$InstallPs1  = Join-Path $ScriptDir "install.ps1"
$ReleaseRoot = Split-Path $ScriptDir -Parent

if (-not (Test-Path $InstallPs1)) {
    [Windows.MessageBox]::Show(
        "Could not find install.ps1 next to this script.`n`nExpected: $InstallPs1`n`nThe release folder is incomplete -- re-extract the ZIP.",
        "TeXLib Installer", 'OK', 'Error') | Out-Null
    exit 11
}

# Read the version out of install.ps1 rather than carrying a second copy that
# can drift. A miss is cosmetic, so it fails soft.
$InstallerVersion = "?"
try {
    $m = Select-String -Path $InstallPs1 -Pattern '^\$InstallerVersion\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($m) { $InstallerVersion = $m.Matches[0].Groups[1].Value }
} catch { $null = $_ }

if (-not $InstallPath) { $InstallPath = Join-Path $env:LOCALAPPDATA "TeXLib" }

# -----------------------------------------------------------------------------
# Phase table
# -----------------------------------------------------------------------------
# Maps a line install.ps1 prints to the label and bar position it means. These
# are matched as substrings against the child's stdout, so they must stay in
# step with install.ps1's Write-Host banners. A marker that stops matching
# costs a progress update, never correctness -- the install itself is driven
# entirely by the child process.
#
# TeX Live gets no percentage on purpose. It is the overwhelming majority of
# the wall clock and its duration depends on which CTAN mirror you are handed,
# so any bar position would be invented. 0.9.1 removed the last invented time
# estimates from this project; the bar goes indeterminate instead and reports
# the elapsed minutes install.ps1 is already printing.
#
# Most markers are printed literally by install.ps1, so CI can assert they are
# still there. Four are composed at runtime from a variable and so appear
# nowhere in install.ps1's source; those carry an `Emit` naming the construct
# that prints them, which is what CI checks instead. Adding a marker without
# either property means CI cannot police it, so don't.
$Phases = @(
    @{ Match = "Running pre-flight checks";      Label = "Running pre-flight checks";              Pct = 3 },
    @{ Match = "Setting up TeXLib";              Label = "Preparing folders";                      Pct = 6 },
    @{ Match = "Downloading sublime_text";       Label = "Downloading Sublime Text";               Pct = 8;
       Emit  = 'Write-Host "Downloading $($Info.File)..."' },
    @{ Match = "Downloading SumatraPDF";         Label = "Downloading SumatraPDF";                 Pct = 10;
       Emit  = 'Write-Host "Downloading $($Info.File)..."' },
    @{ Match = "Downloading install-tl";         Label = "Downloading the TeX Live installer";     Pct = 12;
       Emit  = 'Write-Host "Downloading $($Info.File)..."' },
    @{ Match = "STARTING TEX LIVE INSTALL";      Label = "Installing TeX Live";                    Pct = -1 },
    @{ Match = "[TeX Live] finished";            Label = "TeX Live installed";                     Pct = 78;
       Emit  = '[$Label] finished after' },
    @{ Match = "Deploying TeXLib library";       Label = "Deploying the TeXLib library";           Pct = 82 },
    @{ Match = "Configuring environment";        Label = "Configuring environment";                Pct = 85 },
    @{ Match = "Wiring up Sublime settings";     Label = "Wiring up Sublime settings";             Pct = 87 },
    @{ Match = "Writing program configurations"; Label = "Writing program configuration";          Pct = 90 },
    @{ Match = "Registering file associations";  Label = "Registering file associations";          Pct = 94 },
    @{ Match = "Creating shortcuts";             Label = "Creating shortcuts";                     Pct = 96 },
    @{ Match = "Registering in Installed Apps";  Label = "Registering in Installed Apps";          Pct = 97 },
    @{ Match = "Verifying install with a tiny";  Label = "Verifying with a test compile";          Pct = 98 },
    @{ Match = "Cleaning up temp files";         Label = "Cleaning up";                            Pct = 99 }
)

# install.ps1's Stop-Installer codes, so a failure names the step that failed
# instead of a bare number. Anything not listed falls through to the generic
# message plus the log path, which is always the real answer anyway.
$ExitMeanings = @{
    1  = "Pre-flight checks failed. The report in the log names what is missing."
    2  = "Could not create the install folders. Check the location is writable."
    3  = "The Sublime Text download or extraction failed."
    4  = "The SumatraPDF download or extraction failed."
    5  = "The TeX Live install failed. This is usually a dropped connection to the CTAN mirror."
    7  = "Deploying the TeXLib library failed."
    8  = "Updating your user PATH failed."
    9  = "Setting up the Sublime settings junction failed."
    10 = "Writing the program configuration files failed."
    12 = "The install path contains a space or comma that the library path cannot tolerate."
    13 = "Could not create the %USERPROFILE%\TeXLib junction."
    14 = "Conflicting options were passed to the installer."
    20 = "A pinned download no longer matches its recorded hash."
    22 = "The install no longer matches the manifest written when it was made."
    99 = "The installer crashed before it could report a specific failure."
}

# -----------------------------------------------------------------------------
# Window
# -----------------------------------------------------------------------------
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TeXLib Installer" Width="760" Height="620"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
        Background="#FFF7F7F9" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#FF1F2933" Padding="20,16">
      <StackPanel>
        <TextBlock Text="TeXLib" Foreground="White" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock x:Name="HeaderSub" Foreground="#FFB6C2CF" Margin="0,2,0,0"
                   Text="Sublime Text, SumatraPDF and TeX Live, configured for the TeXLib library."/>
      </StackPanel>
    </Border>

    <!-- OPTIONS -->
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
        <TextBlock Foreground="#FF5A6672" TextWrapping="Wrap" Margin="0,5,0,16"
                   Text="Everything is installed here, for your user only. No administrator rights are needed and nothing outside this folder is replaced."/>

        <TextBlock Text="TeX Live scheme" FontWeight="SemiBold" Margin="0,0,0,4"/>
        <ComboBox x:Name="CmbScheme" Padding="6,5">
          <ComboBoxItem Content="full - everything TeXLib is tested against (about 6 GB)"/>
          <ComboBoxItem Content="medium - a smaller subset (about 1.3 GB)"/>
          <ComboBoxItem Content="basic - minimal (about 0.6 GB)"/>
        </ComboBox>
        <TextBlock x:Name="SchemeNote" Foreground="#FF5A6672" TextWrapping="Wrap" Margin="0,5,0,16"/>

        <Expander x:Name="ExpAdvanced" Header="Advanced" Margin="0,0,0,8">
          <StackPanel Margin="0,10,0,0">
            <TextBlock Text="TeXLib library location" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <TextBox x:Name="TxtLibPath" Padding="6,5" VerticalContentAlignment="Center"/>
            <TextBlock Foreground="#FF5A6672" TextWrapping="Wrap" Margin="0,5,0,12"
                       Text="Leave blank to keep the library inside the install folder, which is what you want unless you are deliberately sharing one library between installs."/>
            <CheckBox x:Name="ChkHideJunction" Content="Hide the %USERPROFILE%\TeXLib junction if one is needed"/>
            <TextBlock Foreground="#FF5A6672" TextWrapping="Wrap" Margin="22,4,0,0"
                       Text="Only applies when the chosen path contains a space or comma. A visible junction is easier to find later, so this is off by default."/>
          </StackPanel>
        </Expander>

        <Border x:Name="PanelDetected" Background="#FFEAF3FB" BorderBrush="#FFA8C9E4" BorderThickness="1"
                Padding="12,10" CornerRadius="3" Margin="0,0,0,16" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Text="Already installed here" FontWeight="SemiBold" Margin="0,0,0,2"/>
            <TextBlock Foreground="#FF3C566E" TextWrapping="Wrap" Margin="0,0,0,8"
                       Text="These are left alone unless you tick them. Reinstalling Sublime Text keeps your settings (they live in the library, reached through the Packages\User junction) and re-fetches the binary plus LaTeXTools."/>
            <CheckBox x:Name="ChkReSublime" Visibility="Collapsed" Margin="0,2,0,0"/>
            <CheckBox x:Name="ChkReSumatra" Visibility="Collapsed" Margin="0,2,0,0"/>
            <CheckBox x:Name="ChkReTexLive" Visibility="Collapsed" Margin="0,2,0,0"/>
          </StackPanel>
        </Border>

        <CheckBox x:Name="ChkDryRun" Content="Dry run - check this machine and report, but change nothing" Margin="0,0,0,4"/>
        <TextBlock Foreground="#FF5A6672" TextWrapping="Wrap" Margin="22,0,0,16"
                   Text="Runs the pre-flight checks and summarises what a real install would do, without downloading or writing anything. Takes seconds. Worth doing first on a machine you have not installed on before."/>

        <Border Background="#FFFFF4CE" BorderBrush="#FFE8C86B" BorderThickness="1" Padding="12,10" CornerRadius="3">
          <TextBlock TextWrapping="Wrap" Foreground="#FF5C4813"
                     Text="A full install downloads about 6 GB from a CTAN mirror and commonly takes 40 to 90 minutes. Most of that is download time, so it depends on which mirror you are handed more than on your machine. You can keep working while it runs."/>
        </Border>
      </StackPanel>
    </ScrollViewer>

    <!-- PROGRESS -->
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
        <!-- HorizontalScrollBarVisibility MUST be Disabled, not Auto, for the
             wrap below to do anything: a ScrollViewer that can scroll
             horizontally measures its child with infinite width, so the TextBox
             would never be constrained to the viewport and would never wrap. -->
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
          <Button x:Name="BtnPrimary" Content="Install" Padding="24,6" FontWeight="SemiBold"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$Win    = [Windows.Markup.XamlReader]::Load($reader)

$TxtInstallPath  = $Win.FindName("TxtInstallPath")
$BtnBrowse       = $Win.FindName("BtnBrowse")
$CmbScheme       = $Win.FindName("CmbScheme")
$SchemeNote      = $Win.FindName("SchemeNote")
$TxtLibPath      = $Win.FindName("TxtLibPath")
$ChkHideJunction = $Win.FindName("ChkHideJunction")
$ChkDryRun       = $Win.FindName("ChkDryRun")
$PanelDetected   = $Win.FindName("PanelDetected")
$ChkReSublime    = $Win.FindName("ChkReSublime")
$ChkReSumatra    = $Win.FindName("ChkReSumatra")
$ChkReTexLive    = $Win.FindName("ChkReTexLive")
$PageOptions     = $Win.FindName("PageOptions")
$PageProgress    = $Win.FindName("PageProgress")
$LblPhase        = $Win.FindName("LblPhase")
$Bar             = $Win.FindName("Bar")
$LblElapsed      = $Win.FindName("LblElapsed")
$TxtLog          = $Win.FindName("TxtLog")
$LogScroller     = $Win.FindName("LogScroller")
$BtnPrimary      = $Win.FindName("BtnPrimary")
$BtnCancel       = $Win.FindName("BtnCancel")
$BtnLog          = $Win.FindName("BtnLog")
$LblFooter       = $Win.FindName("LblFooter")
$HeaderSub       = $Win.FindName("HeaderSub")

$Win.Title = "TeXLib Installer $InstallerVersion"
$LblFooter.Text = "Version $InstallerVersion"
$TxtInstallPath.Text = $InstallPath
$TxtLibPath.Text = $TeXLibPath
$CmbScheme.SelectedIndex = @{ 'full' = 0; 'medium' = 1; 'basic' = 2 }[$TexLiveScheme]

# Shared state for the timer callback. A hashtable because a script-scope
# variable assigned inside an event handler does not survive back to the
# handler's next invocation the way a mutable object's members do.
$S = @{
    Proc      = $null
    OutStream = $null
    ErrStream = $null
    ErrFile   = ""
    OutFile   = ""
    Offset    = 0
    Timer     = $null
    Running   = $false
    Cancelled = $false
    LogPath   = ""
    Started   = $null
    DryRun    = $false
}

# Which components already exist under a given install root, and how big they
# are. The probes mirror install.ps1's own layout ($BaseDir\Sublime Text,
# \Sumatra, \TexLive\<year>) -- if that layout ever moves, these move with it.
# Detection only decides what to OFFER; install.ps1 still decides what to do.
function Get-InstalledComponent {
    param([string]$Root)
    $sublime = Join-Path $Root "Sublime Text\sublime_text.exe"
    $sumatra = Join-Path $Root "Sumatra"
    $texlive = Join-Path $Root "TexLive"
    $texYear = $null
    if (Test-Path $texlive) {
        $texYear = Get-ChildItem $texlive -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | Select-Object -First 1
    }
    [pscustomobject]@{
        Sublime = (Test-Path $sublime)
        Sumatra = ((Test-Path $sumatra) -and @(Get-ChildItem $sumatra -Filter "SumatraPDF*.exe" -ErrorAction SilentlyContinue).Count -gt 0)
        TexLive = ($null -ne $texYear -and (Test-Path (Join-Path $texYear.FullName "bin\windows")))
        TexLiveLabel = if ($texYear) { $texYear.Name } else { "" }
    }
}

function Get-FolderSizeText {
    # Best-effort, and deliberately capped: measuring a 6 GB TeX Live tree of
    # 100k+ files takes real time, and this runs on the UI thread. If it is
    # slow enough to notice, say nothing rather than freeze the window.
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
    if (-not $root) { $PanelDetected.Visibility = 'Collapsed'; return }
    $found = Get-InstalledComponent $root

    $ChkReSublime.Visibility = if ($found.Sublime) { 'Visible' } else { 'Collapsed' }
    $ChkReSumatra.Visibility = if ($found.Sumatra) { 'Visible' } else { 'Collapsed' }
    $ChkReTexLive.Visibility = if ($found.TexLive) { 'Visible' } else { 'Collapsed' }
    if ($found.Sublime) { $ChkReSublime.Content = "Reinstall Sublime Text$(Get-FolderSizeText (Join-Path $root 'Sublime Text'))" }
    if ($found.Sumatra) { $ChkReSumatra.Content = "Reinstall SumatraPDF$(Get-FolderSizeText (Join-Path $root 'Sumatra'))" }
    if ($found.TexLive) { $ChkReTexLive.Content = "Reinstall TeX Live $($found.TexLiveLabel) - re-downloads several GB from CTAN" }

    # A component that is no longer shown must not keep a stale tick, or the
    # user would silently reinstall something they cannot see on the form.
    if (-not $found.Sublime) { $ChkReSublime.IsChecked = $false }
    if (-not $found.Sumatra) { $ChkReSumatra.IsChecked = $false }
    if (-not $found.TexLive) { $ChkReTexLive.IsChecked = $false }

    $PanelDetected.Visibility = if ($found.Sublime -or $found.Sumatra -or $found.TexLive) { 'Visible' } else { 'Collapsed' }
}

function Set-SchemeNote {
    switch ($CmbScheme.SelectedIndex) {
        1 { $SchemeNote.Text = "Smaller on disk, but it saves less time than the size suggests -- the install is dominated by download speed. Run the Doctor afterwards; it names any package TeXLib needs and cannot find." }
        2 { $SchemeNote.Text = "Not viable for TeXLib: basic is missing 30 of the 50 packages the library requires. Pick this only if you intend to add them yourself with tlmgr." }
        default { $SchemeNote.Text = "Recommended. This is what TeXLib is tested against, and it avoids missing-package surprises months from now." }
    }
}
Set-SchemeNote
$CmbScheme.Add_SelectionChanged({ Set-SchemeNote })

$BtnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose where TeXLib should be installed"
    $dlg.ShowNewFolderButton = $true
    if (Test-Path $TxtInstallPath.Text) { $dlg.SelectedPath = $TxtInstallPath.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TxtInstallPath.Text = $dlg.SelectedPath
    }
})

# Re-probe whenever the target changes: what is already installed is a property
# of the path, so the offer has to follow it.
$TxtInstallPath.Add_LostFocus({ Update-Detection })
Update-Detection

function Add-Log([string]$Text) {
    if (-not $Text) { return }
    $TxtLog.AppendText($Text)
    $LogScroller.ScrollToEnd()
}

function Set-Phase([string]$Label, [int]$Pct) {
    $LblPhase.Text = $Label
    if ($Pct -lt 0) {
        $Bar.IsIndeterminate = $true
    } else {
        $Bar.IsIndeterminate = $false
        if ($Pct -gt $Bar.Value) { $Bar.Value = $Pct }
    }
}

function ConvertTo-Arg([string]$Value) {
    # Quote one argument the way CommandLineToArgvW will parse it back.
    # ProcessStartInfo.ArgumentList would do this for us, but that property is
    # .NET Core / .NET 5+; on the .NET Framework that Windows PowerShell 5.1
    # runs on it does not exist at all, and `$psi.ArgumentList.Add(...)` throws
    # "You cannot call a method on a null-valued expression." So we build the
    # single Arguments string by hand. Paths matter here: a release extracted
    # to "Downloads\TeXLib Installer" has a space in the -File path, and a user
    # can type a trailing backslash into the install-location box, which would
    # otherwise escape the closing quote and swallow the next argument.
    if ($Value -eq "") { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'      # backslashes before a quote, then the quote
    $escaped = $escaped -replace '(\\+)$', '$1$1'      # backslashes before the closing quote
    return '"' + $escaped + '"'
}

function Read-NewOutput {
    # Tail whatever the child appended since last tick. Opened shared so the
    # copy task keeps writing while we read.
    if (-not (Test-Path $S.OutFile)) { return "" }
    # CopyToAsync writes through a buffered FileStream, so without this the
    # newest lines sit in memory and the pane lags behind the install.
    try { if ($S.OutStream) { $S.OutStream.Flush() } } catch { $null = $_ }
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

function Stop-Child {
    # Kill the whole tree: install.ps1 spawns install-tl / tlmgr, and killing
    # only powershell.exe leaves a multi-GB download running with nothing
    # watching it.
    if ($S.Proc -and -not $S.Proc.HasExited) {
        try { & taskkill.exe /PID $S.Proc.Id /T /F 2>&1 | Out-Null } catch { $null = $_ }
    }
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
        $LblFooter.Text = "Cancelled -- the install is incomplete"
        Add-Log "`r`n=== Cancelled. Run uninstall.bat to clear a partial install. ===`r`n"
        return
    }
    if ($Code -eq 0) {
        $Bar.Value = 100
        if ($S.DryRun) {
            $LblPhase.Text = "Dry run complete"
            $LblElapsed.Text = "Nothing was downloaded or written. The report below is what a real install would do on this machine."
        } else {
            $LblPhase.Text = "Installation complete"
            $LblElapsed.Text = "Open a NEW terminal before using the tex commands -- the updated PATH is not visible to any window that was already open."
        }
        $LblFooter.Text = "Done"
    } else {
        $Bar.Value = 0
        $what = if ($S.DryRun) { "Dry run failed" } else { "Installation failed" }
        if ($Code -lt 0) {
            $LblPhase.Text = "$what (exit code could not be read)"
            $LblElapsed.Text = "The installer stopped but did not report a code. The log below is the reliable account of what happened."
            $LblFooter.Text = "Failed"
        } else {
            $LblPhase.Text = "$what (exit code $Code)"
            $LblElapsed.Text = if ($ExitMeanings.ContainsKey($Code)) { $ExitMeanings[$Code] } else { "See the log below for what went wrong." }
            $LblFooter.Text = "Failed -- exit code $Code"
        }
    }
}

function Get-InstallArgList {
    # PURE: state in, argument list out -- shared by the real Run handler and
    # -SelfTest, so CI checks the same construction the click performs. The
    # visibility gate on the Reinstall entries is load-bearing: a hidden
    # checkbox is one the user cannot see to untick, and letting it through
    # silently re-downloads a 6 GB TeX Live tree.
    param(
        [string]$InstallTo, [string]$Scheme, [string]$LibPath,
        [bool]$HideJunction, [bool]$DryRun,
        [bool]$ReSublime, [bool]$ReSublimeVisible,
        [bool]$ReSumatra, [bool]$ReSumatraVisible,
        [bool]$ReTexLive, [bool]$ReTexLiveVisible
    )
    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $InstallPs1,
        "-Silent", "-InstallPath", $InstallTo, "-TexLiveScheme", $Scheme
    )
    if ($LibPath)      { $argList += @("-TeXLibPath", $LibPath) }
    if ($HideJunction) { $argList += "-HideJunction" }
    if ($DryRun)       { $argList += "-DryRun" }
    $reinstall = @()
    if ($ReSublime -and $ReSublimeVisible) { $reinstall += 'Sublime' }
    if ($ReSumatra -and $ReSumatraVisible) { $reinstall += 'SumatraPDF' }
    if ($ReTexLive -and $ReTexLiveVisible) { $reinstall += 'TeXLive' }
    if ($reinstall.Count -gt 0) { $argList += @("-Reinstall", ($reinstall -join ",")) }
    return $argList
}

function Get-InstallArgListFromControls {
    # The one place control state is read for the argument list.
    param([string]$InstallTo, [string]$Scheme)
    Get-InstallArgList -InstallTo $InstallTo -Scheme $Scheme `
        -LibPath $TxtLibPath.Text.Trim() `
        -HideJunction ([bool]$ChkHideJunction.IsChecked) `
        -DryRun ([bool]$S.DryRun) `
        -ReSublime ([bool]$ChkReSublime.IsChecked) -ReSublimeVisible ($ChkReSublime.Visibility -eq 'Visible') `
        -ReSumatra ([bool]$ChkReSumatra.IsChecked) -ReSumatraVisible ($ChkReSumatra.Visibility -eq 'Visible') `
        -ReTexLive ([bool]$ChkReTexLive.IsChecked) -ReTexLiveVisible ($ChkReTexLive.Visibility -eq 'Visible')
}

function Start-Install {
    $installTo = $TxtInstallPath.Text.Trim()
    if (-not $installTo) {
        [Windows.MessageBox]::Show("Choose an install location first.", "TeXLib Installer", 'OK', 'Warning') | Out-Null
        return
    }

    $scheme = @('full', 'medium', 'basic')[$CmbScheme.SelectedIndex]
    $S.DryRun = [bool]$ChkDryRun.IsChecked

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $S.OutFile = Join-Path $env:TEMP "TeXLib-gui-$stamp.out.log"
    $S.LogPath = $S.OutFile
    $S.Offset  = 0
    $S.Cancelled = $false
    $S.Started = Get-Date

    $S.ErrFile = Join-Path $env:TEMP "TeXLib-gui-$stamp.err.log"

    # Launched through ProcessStartInfo rather than Start-Process, for two
    # reasons that pull in the same direction:
    #
    #   1. Start-Process -RedirectStandardOutput forces UseShellExecute=$false,
    #      and -WindowStyle Hidden is silently IGNORED when UseShellExecute is
    #      $false. CreateNoWindow is the only flag that actually suppresses the
    #      child's console, and it is reachable only from ProcessStartInfo.
    #   2. -File, not -Command. A script's `exit N` becomes the process exit
    #      code under -File; under -Command it does not survive the call, and a
    #      child that really exited 3 was observed coming back as 1. Getting the
    #      exit code wrong is how a failed install gets reported as a good one,
    #      which this file has already been bitten by once.
    #
    # ProcessStartInfo cannot redirect to a FILE, only to a pipe -- so .NET
    # copies each pipe to a file for us. CopyToAsync is pure .NET and needs no
    # PowerShell event handler, which matters because Register-ObjectEvent
    # handlers do not run while ShowDialog is pumping the message loop.
    $argList = Get-InstallArgListFromControls -InstallTo $installTo -Scheme $scheme

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "powershell.exe"
    $psi.Arguments              = (($argList | ForEach-Object { ConvertTo-Arg $_ }) -join " ")
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.WorkingDirectory       = $ReleaseRoot

    $PageOptions.Visibility  = 'Collapsed'
    $PageProgress.Visibility = 'Visible'
    $BtnPrimary.IsEnabled = $false
    $BtnPrimary.Content = if ($S.DryRun) { "Checking..." } else { "Installing..." }
    $BtnCancel.Content = "Cancel"
    Set-Phase $(if ($S.DryRun) { "Checking this machine" } else { "Starting the installer" }) 1
    # Skip 5: the first five entries are the powershell.exe bootstrap
    # (-NoProfile -ExecutionPolicy Bypass -File <path>), not installer options.
    Add-Log ("> install.ps1 " + (($argList | Select-Object -Skip 5) -join " ") + "`r`n`r`n")

    try {
        Write-GuiLog ("starting child: " + ($argList -join " "))
        $S.Proc = [System.Diagnostics.Process]::Start($psi)
        # Touch .Handle while the process is still alive. A Process object that
        # has not kept the handle open reports $null for .ExitCode once the
        # child exits -- even after WaitForExit() -- and $null coerces to 0
        # through Complete-Run's [int] parameter, so a FAILED install would be
        # reported as a successful one.
        $null = $S.Proc.Handle

        # Copy each pipe straight to a file, bytes as they come. Deliberately
        # NOT PowerShell's own redirection (`*>` / Out-File): in Windows
        # PowerShell 5.1 those default to UTF-16LE, which puts a 0x00 after
        # every ASCII character, and the tailer below -- reading UTF-8 -- then
        # renders "C:\Users" as "C : \ U s e r s". Raw pipe bytes from a
        # console child are single-byte and read back correctly as UTF-8, which
        # install.ps1's ASCII-only output is a subset of.
        $S.OutStream = [IO.File]::Open($S.OutFile, 'Create', 'Write', 'ReadWrite')
        $S.ErrStream = [IO.File]::Open($S.ErrFile, 'Create', 'Write', 'ReadWrite')
        $null = $S.Proc.StandardOutput.BaseStream.CopyToAsync($S.OutStream)
        $null = $S.Proc.StandardError.BaseStream.CopyToAsync($S.ErrStream)
    } catch {
        Write-GuiLog "failed to start child: $_"
        Add-Log "Could not start the installer: $_`r`n"
        Complete-Run 11
        return
    }

    $S.Running = $true
    $S.Timer = New-Object Windows.Threading.DispatcherTimer
    $S.Timer.Interval = [TimeSpan]::FromMilliseconds(400)
    # EVERYTHING in the tick is wrapped. An exception escaping a DispatcherTimer
    # handler goes to WPF's unhandled-exception path, which tears the process
    # down -- the window simply vanishes mid-install with no message and no
    # trace, which is the exact failure boot_wrapper.ps1 was written to prevent
    # on the console side. A trapped error stops the run, says so, and is
    # written to the session log.
    $S.Timer.Add_Tick({
      try {
        $chunk = Read-NewOutput
        if ($chunk) {
            Add-Log $chunk
            foreach ($line in ($chunk -split "`r?`n")) {
                foreach ($p in $Phases) {
                    # .Contains, NOT -like: install.ps1 prints "[TeX Live] finished",
                    # and -like would read "[TeX Live]" as a wildcard character class,
                    # so that marker could never match. Plain substring matching also
                    # keeps any future marker containing [ ] * ? safe by default.
                    if ($line.Contains($p.Match)) { Set-Phase $p.Label $p.Pct }
                }
                if ($line -match '\[TeX Live\] still going\.\.\. ([\d.]+) min elapsed') {
                    $LblElapsed.Text = "TeX Live: $($Matches[1]) minutes elapsed. Most of this is download time from the CTAN mirror."
                }
            }
        }
        if ($S.Proc.HasExited) {
            Start-Sleep -Milliseconds 250      # let the copy tasks drain the pipes
            Add-Log (Read-NewOutput)
            foreach ($st in @($S.OutStream, $S.ErrStream)) {
                if ($st) { try { $st.Flush(); $st.Dispose() } catch { $null = $_ } }
            }
            $S.OutStream = $null; $S.ErrStream = $null
            Add-Log (Read-NewOutput)           # anything the final flush released
            try {
                if ((Test-Path $S.ErrFile) -and (Get-Item $S.ErrFile).Length -gt 0) {
                    Add-Log "`r`n--- error output ---`r`n"
                    Add-Log ([IO.File]::ReadAllText($S.ErrFile))
                }
            } catch { $null = $_ }
            # Belt and braces: if the handle trick above ever fails us, report
            # an unknown code rather than silently calling a failure a success.
            $code = if ($null -ne $S.Proc.ExitCode) { [int]$S.Proc.ExitCode } else { -1 }
            Write-GuiLog "child exited with $code"
            Complete-Run $code
        }
      } catch {
        Write-GuiLog "TICK ERROR: $($_.Exception.GetType().Name): $($_.Exception.Message)"
        Write-GuiLog $_.ScriptStackTrace
        try { $S.Timer.Stop() } catch { $null = $_ }
        $S.Running = $false
        Add-Log "`r`n=== The installer window hit an internal error ===`r`n$($_.Exception.Message)`r`n`r`nThe install itself may still have completed -- check the log.`r`nDetails: $GuiLog`r`n"
        $BtnCancel.Visibility = 'Collapsed'
        $BtnLog.Visibility = 'Visible'
        $BtnPrimary.Content = "Close"
        $BtnPrimary.IsEnabled = $true
        $LblPhase.Text = "Interrupted by an internal error"
        $Bar.IsIndeterminate = $false
      }
    })
    $S.Timer.Start()
}

$BtnPrimary.Add_Click({
    if ($S.Running) { return }
    if ($BtnPrimary.Content -eq "Close") { $Win.Close(); return }
    Start-Install
})

$BtnCancel.Add_Click({
    if (-not $S.Running) { $Win.Close(); return }
    $ans = [Windows.MessageBox]::Show(
        "Stop the install?`n`nWhatever has been written so far stays on disk. Run uninstall.bat afterwards to clear it out.",
        "TeXLib Installer", 'YesNo', 'Warning')
    if ($ans -eq 'Yes') {
        $S.Cancelled = $true
        Stop-Child
    }
})

$BtnLog.Add_Click({
    if ($S.LogPath -and (Test-Path $S.LogPath)) { Start-Process notepad.exe $S.LogPath }
})

# Closing the window mid-install must not orphan a 6 GB download.
$Win.Add_Closing({
    # Not named $sender/$e: $sender is an automatic variable, and shadowing it
    # inside an event handler is the kind of thing that works until it doesn't.
    param($EventSource, $CancelArgs)
    $null = $EventSource
    if ($S.Running) {
        $ans = [Windows.MessageBox]::Show(
            "The install is still running. Close and stop it?",
            "TeXLib Installer", 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { $CancelArgs.Cancel = $true; return }
        $S.Cancelled = $true
        Stop-Child
    }
})

$HeaderSub.Text = "Sublime Text, SumatraPDF and TeX Live, configured for the TeXLib library."

# Last line of defence. Anything that still escapes to the dispatcher would
# otherwise close the window with no message at all; this turns it into
# something the user can read and report, and leaves it in the session log.
$Win.Dispatcher.Add_UnhandledException({
    param($EventSource, $ErrorArgs)
    $null = $EventSource
    Write-GuiLog "UNHANDLED: $($ErrorArgs.Exception.GetType().Name): $($ErrorArgs.Exception.Message)"
    try {
        [Windows.MessageBox]::Show(
            "The installer window hit an unexpected error.`n`n$($ErrorArgs.Exception.Message)`n`nDetails were written to:`n$GuiLog",
            "TeXLib Installer", 'OK', 'Error') | Out-Null
    } catch { $null = $_ }
    $ErrorArgs.Handled = $true      # keep the window alive so the log stays reachable
})

if ($SelfTest) {
    # Everything real has happened by this point: WPF loaded, XAML parsed,
    # every FindName resolved, handlers wired, detection ran. What remains is
    # the dialog loop and the child process, which a headless runner cannot
    # have -- so drive the REAL controls and check the argument list each
    # state produces.
    $Fails = 0
    function Assert-Args {
        param([string]$Name, [string[]]$Got, [string[]]$MustHave, [string[]]$MustNotHave)
        $ok = $true
        foreach ($m in $MustHave)    { if ($Got -notcontains $m) { $ok = $false } }
        foreach ($m in $MustNotHave) { if ($Got -contains $m)    { $ok = $false } }
        if ($ok) { Write-Host "  PASS  $Name" -ForegroundColor Green }
        else {
            Write-Host "  FAIL  $Name" -ForegroundColor Red
            Write-Host "        got: $($Got -join ' ')" -ForegroundColor Red
            $script:Fails++
        }
    }
    $installTo = 'C:\SelfTestRoot'
    Write-Host "install-gui self-test (window built, controls live):"

    $TxtLibPath.Text = ''
    $ChkHideJunction.IsChecked = $false
    $S.DryRun = $false
    foreach ($c in @($ChkReSublime, $ChkReSumatra, $ChkReTexLive)) { $c.IsChecked = $false; $c.Visibility = 'Collapsed' }
    Assert-Args "defaults -> silent full-scheme install, nothing extra" (Get-InstallArgListFromControls -InstallTo $installTo -Scheme 'full') `
        @('-Silent','-InstallPath',$installTo,'-TexLiveScheme','full',$InstallPs1) @('-Reinstall','-DryRun','-HideJunction','-TeXLibPath')

    $TxtLibPath.Text = 'C:\Somewhere\TeXLib'
    $ChkHideJunction.IsChecked = $true
    $S.DryRun = $true
    Assert-Args "library path + junction + dry-run forwarded" (Get-InstallArgListFromControls -InstallTo $installTo -Scheme 'medium') `
        @('-TeXLibPath','C:\Somewhere\TeXLib','-HideJunction','-DryRun','-TexLiveScheme','medium') @()

    # The visibility gate: a ticked but HIDDEN Reinstall box must not reach
    # the child -- a hidden checkbox is one the user cannot see to untick,
    # and TeXLive on that list is a silent 6 GB re-download.
    $TxtLibPath.Text = ''; $ChkHideJunction.IsChecked = $false; $S.DryRun = $false
    $ChkReTexLive.IsChecked = $true; $ChkReTexLive.Visibility = 'Collapsed'
    Assert-Args "ticked but hidden Reinstall box stays out" (Get-InstallArgListFromControls -InstallTo $installTo -Scheme 'full') `
        @() @('-Reinstall')

    $ChkReTexLive.Visibility = 'Visible'
    $Got = Get-InstallArgListFromControls -InstallTo $installTo -Scheme 'full'
    Assert-Args "ticked and visible Reinstall box goes through" $Got @('-Reinstall','TeXLive') @()

    Write-Host ("self-test: {0}" -f $(if ($Fails -eq 0) { "all cases pass" } else { "$Fails case(s) FAILED" }))
    exit $(if ($Fails -eq 0) { 0 } else { 1 })
}

Write-GuiLog "showing window"
$null = $Win.ShowDialog()
Write-GuiLog "window closed"
