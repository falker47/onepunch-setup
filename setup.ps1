<#
Onepunch-setup - Main GUI installer
WPF GUI in PowerShell to select categories and install apps via winget.
Uses brand theming, two-column layout, search, and logs a JSON summary.
#>

param(
    [switch]$DryRun,
    [switch]$EnableWSL,
    [switch]$AutoReboot,
    [string]$PackagesUrl,
    [string]$LogDir,
    [switch]$ForceDownloadOnly
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Constants
$DefaultPackagesUrl = 'https://raw.githubusercontent.com/falker47/onepunch-setup/main/packages.json'
$DefaultLogDir = Join-Path $env:LOCALAPPDATA 'pc-setup\logs'

# Optional embedded manifest (base64-encoded JSON). Replaced by compile.ps1 if embedding is enabled
$EmbeddedManifestBase64 = '<#EMBED_PACKAGES_JSON#>'

if (-not $PackagesUrl -or [string]::IsNullOrWhiteSpace($PackagesUrl)) {
    $PackagesUrl = $DefaultPackagesUrl
}
if (-not $LogDir -or [string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = $DefaultLogDir
}

# Import utils module (embedded functions instead of external file)
function Start-AdminElevation {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) { return }

    Write-Host 'Elevazione privilegi richiesta, rilancio come amministratore…' -ForegroundColor Yellow

    $psExe = (Get-Process -Id $PID).Path
    $argsList = @()
    # Preserve script and arguments
    if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $argsList += '-ExecutionPolicy', 'Bypass', '-File', ("""{0}""" -f $MyInvocation.MyCommand.Path)
        $BoundParameters.GetEnumerator() | ForEach-Object {
            $k = $_.Key; $v = $_.Value
            if ($v -is [switch]) {
                if ($v.IsPresent) { $argsList += ("-{0}" -f $k) }
            } elseif ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
                $argsList += ("-{0}" -f $k), ("""{0}""" -f $v)
            }
        }
    }

    # Only pass ArgumentList if it has content
    if ($argsList.Count -gt 0) {
        Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argsList | Out-Null
    } else {
        Start-Process -FilePath $psExe -Verb RunAs | Out-Null
    }
    exit 0
}

function Start-Logging {
    param(
        [Parameter(Mandatory=$true)][string]$LogDir
    )
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $LogDir ("setup-{0}.log" -f $ts)
    Start-Transcript -Path $logPath -Force | Out-Null
    return @{ LogPath = $logPath; StartedAt = (Get-Date) }
}

function Stop-Logging {
    param(
        [Parameter(Mandatory=$true)][hashtable]$TranscriptInfo
    )
    try { Stop-Transcript | Out-Null } catch { }
}

function Show-ErrorDialog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Title = 'Errore'
    )
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
}

function Get-Manifest {
    param(
        [Parameter(Mandatory=$true)][string]$PackagesUrl
    )
    # 0) Embedded manifest (if present)
    if ($EmbeddedManifestBase64 -and $EmbeddedManifestBase64 -notlike '<#*#>') {
        try {
            if ($ForceDownloadOnly) {
                & $doDownloadOnly; return
            }
            $bytes = [Convert]::FromBase64String($EmbeddedManifestBase64)
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            return $raw | ConvertFrom-Json
        } catch { }
    }

    # 1) Try to find packages.json in the same directory as the EXE
    $exePath = [System.Reflection.Assembly]::GetExecutingAssembly().Location
    $localPath = if ($exePath) { Join-Path (Split-Path -Parent $exePath) 'packages.json' } else { 'packages.json' }
    
    if (Test-Path $localPath) {
        Write-Verbose "Carico manifest da file locale: $localPath"
        $raw = Get-Content -LiteralPath $localPath -Raw -Encoding UTF8
        return $raw | ConvertFrom-Json
    }
    # 2) Remote fallback
    Write-Verbose "Manifest locale non trovato. Scarico da: $PackagesUrl"
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "packages.json")
    try {
        Invoke-WebRequest -Uri $PackagesUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 60 | Out-Null
        $raw = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
        return $raw | ConvertFrom-Json
    } catch {
        Show-ErrorDialog -Message ("Impossibile scaricare il manifest da: {0}`n{1}" -f $PackagesUrl, $_.Exception.Message) -Title 'Manifest non disponibile'
        throw
    }
}

function Test-Manifest {
    param(
        [Parameter(Mandatory=$true)]$Manifest
    )
    if (-not $Manifest.categories) { throw 'Manifest non valido: manca la proprietà categories' }
    foreach ($categoryName in $Manifest.categories.PSObject.Properties.Name) {
        $category = $Manifest.categories.$categoryName
        if (-not $category.packages -or $category.packages.Count -eq 0) {
            throw ("Categoria '{0}' non valida: packages è vuoto" -f $categoryName)
        }
        foreach ($pkg in $category.packages) {
            if (-not $pkg.name) {
                throw ("Pacchetto in '{0}' non valido: 'name' è richiesto" -f $categoryName)
            }
            $isManual = $false
            if ($null -ne $pkg.PSObject.Properties['manual']) { $isManual = [bool]$pkg.manual }
            if ($isManual) {
                if (-not $pkg.url -or [string]::IsNullOrWhiteSpace([string]$pkg.url)) {
                    throw ("Pacchetto manuale '{0}' in '{1}' non valido: 'url' è richiesto" -f $pkg.name, $categoryName)
                }
            } else {
                if (-not $pkg.id -or [string]::IsNullOrWhiteSpace([string]$pkg.id)) {
                    throw ("Pacchetto in '{0}' non valido: 'id' è richiesto (o impostare manual=true con url)" -f $categoryName)
                }
            }
        }
    }
}

function Test-IsInstalled {
    param(
        [Parameter(Mandatory=$true)][string]$Id
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'winget'
    $psi.Arguments = "list --id ""$Id"""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    if ($out -match '(?im)^No installed package found matching input criteria') { return $false }
    # If table has at least one non-header line and contains the ID, consider installed
    if ($out -match [Regex]::Escape($Id)) { return $true }
    return $false
}

function Install-Package {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Name,
        [switch]$DryRun
    )
    $started = Get-Date
    try {
        if (Test-IsInstalled -Id $Id) {
            return [pscustomobject]@{ id=$Id; name=$Name; status='already_present'; startedAt=$started.ToString('s'); durationMs=0; errorMessage=$null; badge='Already installed' }
        }
        if ($DryRun) {
            return [pscustomobject]@{ id=$Id; name=$Name; status='installed'; startedAt=$started.ToString('s'); durationMs=0; errorMessage=$null; dryRun=$true }
        }
        # Non-blocking winget installation with timeout
        $maxWaitTime = 300000 # 5 minutes default
        if ($Id -match 'Spotify|Blender|VisualStudio|Docker|WinRAR|Notepad\+\+') {
            $maxWaitTime = 600000 # 10 minutes for large packages
        }
        
        $wingetArgs = @('install','--id', $Id,'--accept-package-agreements','--accept-source-agreements','--silent')
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'winget'
        $psi.Arguments = ($wingetArgs -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null
        
        # Non-blocking wait with timeout
        $startTime = Get-Date
        while (-not $proc.HasExited) {
            # Check for timeout
            $elapsedMs = [int]((Get-Date) - $startTime).TotalMilliseconds
            if ($elapsedMs -gt $maxWaitTime) {
                # Timeout reached, kill the process
                try {
                    $proc.Kill()
                    $proc.WaitForExit(5000)
                } catch {
                    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                }
                break
            }
            
            # Update every 500ms to keep responsive
            Start-Sleep -Milliseconds 500
        }
        
        # Wait for process to exit completely
        if (-not $proc.HasExited) {
            $proc.WaitForExit(10000) # Wait up to 10 seconds
        }
        
        $exit = $proc.ExitCode
        $dur = [int]((Get-Date) - $started).TotalMilliseconds
        
        # Check if process was killed due to timeout
        if ($elapsedMs -gt $maxWaitTime) {
            $timeoutMinutes = [math]::Round($maxWaitTime / 60000, 1)
            return [pscustomobject]@{ id=$Id; name=$Name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage="Installation timeout ($timeoutMinutes minutes)" }
        } elseif ($exit -eq 0) {
            return [pscustomobject]@{ id=$Id; name=$Name; status='installed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null }
        } else {
            return [pscustomobject]@{ id=$Id; name=$Name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=("ExitCode {0}" -f $exit) }
        }
    } catch {
        $dur = [int]((Get-Date) - $started).TotalMilliseconds
        return [pscustomobject]@{ id=$Id; name=$Name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$_.Exception.Message }
    }
}

function Write-Summary {
    param(
        [Parameter(Mandatory=$true)]$RunState,
        [Parameter(Mandatory=$true)][string]$LogDir
    )
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $summaryPath = Join-Path $LogDir ("summary-{0}.json" -f $ts)
    $counts = [ordered]@{
        installed = ($RunState.results | Where-Object { $_.status -eq 'installed' }).Count
        already_present = ($RunState.results | Where-Object { $_.status -eq 'already_present' }).Count
        manual = ($RunState.results | Where-Object { $_.status -eq 'manual' }).Count
        failed = ($RunState.results | Where-Object { $_.status -eq 'failed' }).Count
    }
    $summary = [ordered]@{
        startedAt = $RunState.startedAt
        finishedAt = (Get-Date).ToString('s')
        dryRun = $RunState.dryRun
        enableWSL = $RunState.enableWSL
        autoReboot = $RunState.autoReboot
        counts = $counts
        results = $RunState.results
    }
    ($summary | ConvertTo-Json -Depth 10) | Out-File -FilePath $summaryPath -Encoding utf8
    Write-Host ("Sommario scritto in: {0}" -f $summaryPath) -ForegroundColor Green
    return [pscustomobject]$counts
}

function Enable-WSLFeatures {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart -ErrorAction Stop | Out-Null
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction Stop | Out-Null
}

# Ensure admin and execution context
Start-AdminElevation

# Winget presence check
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    [System.Windows.MessageBox]::Show("'winget' non trovato. Installa 'App Installer' dal Microsoft Store e riprova.", "Onepunch-setup", 'OK', 'Error') | Out-Null
    exit 2
}

# Start logging
$TranscriptInfo = Start-Logging -LogDir $LogDir

try {
    # Load manifest (local-first, then remote)
    $manifest = Get-Manifest -PackagesUrl $PackagesUrl
    Test-Manifest -Manifest $manifest

    # Build GUI (WPF)
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Onepunch-setup" Height="620" Width="900" WindowStartupLocation="CenterScreen" Background="{DynamicResource App.Background}" Foreground="{DynamicResource App.Text}">
    <Window.Resources>
        <!-- Theme brushes (DynamicResource for live toggle) -->
        <!-- Light theme default (Brand) -->
        <SolidColorBrush x:Key="App.Background" Color="#FDCA56" />
        <SolidColorBrush x:Key="App.Card" Color="#F5F5F5" />
        <SolidColorBrush x:Key="App.Border" Color="#DB1E1F" />
        <SolidColorBrush x:Key="App.Text" Color="#000000" />
        <SolidColorBrush x:Key="App.MutedText" Color="#666666" />
        <SolidColorBrush x:Key="App.Primary" Color="#FDCA56" />
        <SolidColorBrush x:Key="App.PrimaryHover" Color="#F4C430" />
        <SolidColorBrush x:Key="App.PrimaryText" Color="#000000" />
        <!-- Secondary (Red) for Install button -->
        <SolidColorBrush x:Key="App.Secondary" Color="#DB1E1F" />
        <SolidColorBrush x:Key="App.SecondaryHover" Color="#C41E3A" />
        <SolidColorBrush x:Key="App.SecondaryText" Color="#FFFFFF" />

        <!-- Button style -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource App.Primary}"/>
            <Setter Property="Foreground" Value="{DynamicResource App.PrimaryText}"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="BorderBrush" Value="{DynamicResource App.Primary}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="{DynamicResource App.PrimaryHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Install button: red with red hover (brand secondary) -->
        <Style x:Key="InstallButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="{DynamicResource App.Secondary}"/>
            <Setter Property="Foreground" Value="{DynamicResource App.SecondaryText}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource App.Secondary}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="{DynamicResource App.SecondaryHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Ensure text is bound to theme color across common controls -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
        </Style>
        <Style TargetType="Expander">
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
        </Style>
        <Style TargetType="StatusBar">
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
        </Style>
        <!-- Default buttons (non-primary) inherit theme colors -->
        <Style TargetType="Button" BasedOn="{x:Null}">
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
            <Setter Property="Background" Value="{DynamicResource App.Card}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource App.Border}"/>
        </Style>

        <!-- TextBox style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource App.Card}"/>
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource App.Border}"/>
        </Style>

        <!-- Toggle (Dark mode) as pill switch -->
        <Style x:Key="PillToggle" TargetType="CheckBox">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid>
                            <Border x:Name="Track" Width="44" Height="24" CornerRadius="12" Background="{DynamicResource App.Border}"/>
                            <Ellipse x:Name="Thumb" Width="18" Height="18" Fill="{DynamicResource App.Card}" Margin="3" HorizontalAlignment="Left"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Track" Property="Background" Value="{DynamicResource App.Primary}"/>
                                <Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="Thumb" Property="Fill" Value="{DynamicResource App.PrimaryText}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Track" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Card style for category containers -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{DynamicResource App.Card}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource App.Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
            <Setter Property="VerticalAlignment" Value="Top"/>
        </Style>

        <!-- Expander header text style -->
        <Style TargetType="TextBlock" x:Key="CategoryHeaderText">
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{DynamicResource App.Text}"/>
        </Style>
    </Window.Resources>
    <DockPanel LastChildFill="True">
        <!-- Header with title and search -->
        <Grid DockPanel.Dock="Top" Margin="12,12,12,8">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <!-- Title row -->
            <Grid>
                <TextBlock Text="Onepunch-setup" FontSize="24" FontWeight="Bold" Foreground="{DynamicResource App.Text}"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock Text="☀" FontSize="14" VerticalAlignment="Center" Foreground="{DynamicResource App.Text}"/>
                    <CheckBox x:Name="ChkTheme" Style="{StaticResource PillToggle}" Margin="8,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Text="🌙" FontSize="14" VerticalAlignment="Center" Foreground="{DynamicResource App.Text}"/>
                </StackPanel>
            </Grid>
            <!-- Search row -->
            <Grid Grid.Row="1" Margin="0,8,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="🔍" FontSize="14" VerticalAlignment="Center" Foreground="{DynamicResource App.MutedText}" Margin="0,0,8,0"/>
                <TextBox Grid.Column="1" x:Name="TxtSearch" Height="28" VerticalAlignment="Center" Padding="6" ToolTip="Search packages..." Margin="0,0,12,0"/>
            </Grid>
        </Grid>
        <StatusBar DockPanel.Dock="Bottom" Background="{DynamicResource App.Card}" Visibility="Collapsed">
            <StatusBarItem>
                <TextBlock x:Name="StatusText" Text=""/>
            </StatusBarItem>
            <StatusBarItem>
                <ProgressBar x:Name="Prg" Width="200" Height="14" Minimum="0" Maximum="100"/>
            </StatusBarItem>
            <StatusBarItem>
                <ProgressBar x:Name="PrgItem" Width="120" Height="14" Minimum="0" Maximum="100" IsIndeterminate="False"/>
            </StatusBarItem>
        </StatusBar>
        <Grid DockPanel.Dock="Bottom" Margin="12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="CreditText" Foreground="{DynamicResource App.Text}" VerticalAlignment="Center"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <CheckBox x:Name="ChkDryRun" Content="Dry Run" Margin="0,0,16,0" VerticalAlignment="Center"/>
                <CheckBox x:Name="ChkWSL" Content="Enable WSL" Margin="0,0,16,0" VerticalAlignment="Center"/>
                <CheckBox x:Name="ChkReboot" Content="Auto Reboot" Margin="0,0,24,0" VerticalAlignment="Center"/>
                <Button x:Name="BtnSelectAll" Content="Select All" Margin="0,0,8,0"/>
                <Button x:Name="BtnDeselectAll" Content="Deselect All" Margin="0,0,24,0"/>
                <Button x:Name="BtnInstall" Content="Install" Style="{StaticResource InstallButton}" IsEnabled="False" MinWidth="140" Padding="16,8" FontSize="14" FontWeight="Bold"/>
            </StackPanel>
        </Grid>
        <ScrollViewer x:Name="MainScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Background="{DynamicResource App.Background}">
            <Grid x:Name="CategoriesPanel" Margin="12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel x:Name="LeftColumn" Grid.Column="0"/>
                <StackPanel x:Name="RightColumn" Grid.Column="1" Margin="12,0,0,0"/>
            </Grid>
        </ScrollViewer>
    </DockPanel>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{}
    $window.FindName("StatusText") | ForEach-Object { $controls.StatusText = $_ }
    $window.FindName("ChkDryRun") | ForEach-Object { $controls.ChkDryRun = $_ }
    $window.FindName("ChkWSL") | ForEach-Object { $controls.ChkWSL = $_ }
    $window.FindName("ChkReboot") | ForEach-Object { $controls.ChkReboot = $_ }
    $window.FindName("BtnSelectAll") | ForEach-Object { $controls.BtnSelectAll = $_ }
    $window.FindName("BtnDeselectAll") | ForEach-Object { $controls.BtnDeselectAll = $_ }
    $window.FindName("BtnInstall") | ForEach-Object { $controls.BtnInstall = $_ }
    $window.FindName("CategoriesPanel") | ForEach-Object { $controls.CategoriesPanel = $_ }
    $window.FindName("TxtSearch") | ForEach-Object { $controls.TxtSearch = $_ }
    $window.FindName("Prg") | ForEach-Object { $controls.Prg = $_ }
    $window.FindName("PrgItem") | ForEach-Object { $controls.PrgItem = $_ }
    $window.FindName("ChkTheme") | ForEach-Object { $controls.ChkTheme = $_ }
    $window.FindName("MainScroll") | ForEach-Object { $controls.MainScroll = $_ }
    $window.FindName("CreditText") | ForEach-Object { $controls.CreditText = $_ }

    # Initialize toggles with CLI values
    $controls.ChkDryRun.IsChecked = [bool]$DryRun
    $controls.ChkWSL.IsChecked = [bool]$EnableWSL
    $controls.ChkReboot.IsChecked = [bool]$AutoReboot

    # Build categories UI
    $packageCheckBoxes = New-Object System.Collections.Generic.List[System.Windows.Controls.CheckBox]
    $categoryNodes = New-Object System.Collections.Generic.List[object]

    function Get-CategoryIcon([string]$name) {
        switch -Regex ($name) {
            'dev|code|program'      { return '🛠' }
            'browser|web|internet'  { return '🌐' }
            'media|audio|video'     { return '🎬' }
            'design|image|photo'    { return '🎨' }
            'security|antivirus'    { return '🔒' }
            'gaming|game'           { return '🎮' }
            'utility|utilities'     { return '💡' }
            'system|tools'          { return '⚙️' }
            'cloud|sync|drive'      { return '☁️' }
            'chat|comm|mail'        { return '💬' }
            'ai|ml|model'           { return '🤖' }
            default                 { return '📦' }
        }
    }

    # Helper to enable/disable Install
    $updateInstallButton = {
        $any = $false
        foreach ($c in $packageCheckBoxes) { if ($c.IsChecked) { $any = $true; break } }
        $controls.BtnInstall.IsEnabled = $any
    }

    $categoryNames = @($manifest.categories.PSObject.Properties.Name | Sort-Object)
    $midpoint = [math]::Ceiling($categoryNames.Count / 2)
    $idx = 0
    foreach ($categoryName in $categoryNames) {
        $cat = $manifest.categories.$categoryName

        $expander = New-Object System.Windows.Controls.Expander
        $headerPanel = New-Object System.Windows.Controls.StackPanel
        $headerPanel.Orientation = 'Horizontal'
        $iconBlock = New-Object System.Windows.Controls.TextBlock
        $iconBlock.Text = (Get-CategoryIcon $categoryName)
        $iconBlock.FontSize = 18
        $iconBlock.Margin = '0,0,8,0'
        $iconBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'App.Text')
        $hdrText = New-Object System.Windows.Controls.TextBlock
        $hdrText.Text = $categoryName
        $hdrText.FontSize = 18
        $hdrText.FontWeight = 'Bold'
        $hdrText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'App.Text')
        $headerPanel.Children.Add($iconBlock) | Out-Null
        $headerPanel.Children.Add($hdrText) | Out-Null
        $expander.Header = $headerPanel
        $expander.IsExpanded = $false
        $expander.Margin = '0,0,0,8'
        
        $card = New-Object System.Windows.Controls.Border
        $card.Style = $window.Resources["Card"]
        $catPanel = New-Object System.Windows.Controls.StackPanel
        $catPanel.Margin = '8,4,0,8'

        # Category master checkbox
        $catHeaderPanel = New-Object System.Windows.Controls.StackPanel
        $catHeaderPanel.Orientation = 'Horizontal'
        $catCheck = New-Object System.Windows.Controls.CheckBox
        $catLbl = New-Object System.Windows.Controls.TextBlock
        $catLbl.Text = "Select/Deselect All"
        $catLbl.FontWeight = 'Bold'
        $catCheck.Content = $catLbl
        $catCheck.Margin = '0,0,0,8'
        $catHeaderPanel.Children.Add($catCheck) | Out-Null
        $catPanel.Children.Add($catHeaderPanel) | Out-Null

        foreach ($pkg in $cat.packages) {
            $chk = New-Object System.Windows.Controls.CheckBox
            $display = if ($pkg.id) { "$($pkg.name)  ($($pkg.id))" } else { $pkg.name }
            $nameText = New-Object System.Windows.Controls.TextBlock
            $nameText.Text = $display
            $nameText.TextWrapping = 'Wrap'
            $nameText.TextTrimming = 'CharacterEllipsis'

            # Row with badge indicating install type
            $row = New-Object System.Windows.Controls.StackPanel
            $row.Orientation = 'Horizontal'
            $row.Children.Add($nameText) | Out-Null

            $isManual = $false
            if ($null -ne $pkg.PSObject.Properties['manual']) { $isManual = [bool]$pkg.manual }
            $badge = New-Object System.Windows.Controls.Border
            $badge.CornerRadius = '12'
            $badge.Padding = '6,2'
            $badge.Margin = '8,0,0,0'
            if ($isManual) {
                $badge.Background = $window.Resources['App.Secondary']
                $badge.BorderBrush = $window.Resources['App.Secondary']
                $badge.BorderThickness = '1'
                $badgeLabel = New-Object System.Windows.Controls.TextBlock
                $badgeLabel.Text = 'Download only'
                $badgeLabel.Foreground = $window.Resources['App.SecondaryText']
                $badge.Child = $badgeLabel
            } else {
                $badge.Background = $window.Resources['App.Card']
                $badge.BorderBrush = $window.Resources['App.Border']
                $badge.BorderThickness = '1'
                $badgeLabel = New-Object System.Windows.Controls.TextBlock
                $badgeLabel.Text = 'Install'
                $badgeLabel.Foreground = $window.Resources['App.Text']
                $badge.Child = $badgeLabel
            }
            $row.Children.Add($badge) | Out-Null

            # MaxWidth is adjusted later via a global resize handler
            $chk.Content = $row
            if ($pkg.description) { $chk.ToolTip = $pkg.description }
            $chk.Tag = [pscustomobject]@{ Pkg=$pkg; Master=$catCheck; Panel=$catPanel }
            $chk.IsChecked = [bool]$pkg.selected
            $chk.Margin = '8,2,0,2'
            $packageCheckBoxes.Add($chk) | Out-Null
            $catPanel.Children.Add($chk) | Out-Null

            # Update master state when a child changes
            $null = $chk.Add_Checked({ param($sender,$e)
                $ctx = $sender.Tag
                $total = 0; $checked = 0
                foreach ($child in $ctx.Panel.Children) {
                    if ($child -is [System.Windows.Controls.CheckBox] -and $child -ne $ctx.Master) {
                        $total++
                        if ($child.IsChecked) { $checked++ }
                    }
                }
                $m = $ctx.Master
                $m.IsThreeState = $true
                if ($checked -eq 0) { $m.IsChecked = $false }
                elseif ($checked -eq $total) { $m.IsChecked = $true }
                else { $m.IsChecked = $null }
                & $updateInstallButton
            })
            $null = $chk.Add_Unchecked({ param($sender,$e)
                $ctx = $sender.Tag
                $total = 0; $checked = 0
                foreach ($child in $ctx.Panel.Children) {
                    if ($child -is [System.Windows.Controls.CheckBox] -and $child -ne $ctx.Master) {
                        $total++
                        if ($child.IsChecked) { $checked++ }
                    }
                }
                $m = $ctx.Master
                $m.IsThreeState = $true
                if ($checked -eq 0) { $m.IsChecked = $false }
                elseif ($checked -eq $total) { $m.IsChecked = $true }
                else { $m.IsChecked = $null }
                & $updateInstallButton
            })
        }

        # Localize references to avoid late-binding closure issues
        # Store context on master for event handlers
        $catCheck.Tag = [pscustomobject]@{ Panel=$catPanel; Master=$catCheck }
        $catCheck.IsThreeState = $true

        # Click handler to enforce two-state toggle; indeterminate is only set by child changes
        $null = $catCheck.Add_Click({ param($sender,$e)
            $ctx = $sender.Tag
            # Determine current child selection
            $total = 0; $checked = 0
            foreach ($child in $ctx.Panel.Children) {
                if ($child -is [System.Windows.Controls.CheckBox] -and $child -ne $ctx.Master) {
                    $total++
                    if ($child.IsChecked) { $checked++ }
                }
            }
            # If not all selected, select all; else deselect all
            $selectAll = $checked -lt $total
            foreach ($child in $ctx.Panel.Children) {
                if ($child -is [System.Windows.Controls.CheckBox] -and $child -ne $ctx.Master) {
                    $child.IsChecked = $selectAll
                }
            }
            # Set master strictly to true/false to avoid cycling
            $sender.IsChecked = [bool]$selectAll
            $e.Handled = $true
            & $updateInstallButton
        })

        $expander.Content = $catPanel
        $card.Child = $expander
        # Place card by splitting the list into two equal columns (first half left, second half right)
        $leftCol = $window.FindName('LeftColumn')
        $rightCol = $window.FindName('RightColumn')
        if ($idx -lt $midpoint) { $leftCol.Children.Add($card) | Out-Null } else { $rightCol.Children.Add($card) | Out-Null }
        $null = $categoryNodes.Add([pscustomobject]@{ Name=$categoryName; Expander=$expander; Panel=$catPanel; Card=$card })
        $idx++
    }

    foreach ($c in $packageCheckBoxes) {
        $null = $c.Add_Checked($updateInstallButton)
        $null = $c.Add_Unchecked($updateInstallButton)
    }
    & $updateInstallButton

    # Set credit text with current year and hyperlink
    try {
        $year = (Get-Date).Year
        $controls.CreditText.Inlines.Clear()
        $hl = New-Object System.Windows.Documents.Hyperlink
        $hl.NavigateUri = [Uri]"https://falker47.github.io/Nexus-portfolio/"
        $hl.Inlines.Add((New-Object System.Windows.Documents.Run ("© $year Maurizio Falconi - falker47"))) | Out-Null
        $null = $hl.Add_Click({ Start-Process "https://falker47.github.io/Nexus-portfolio/" })
        $controls.CreditText.Inlines.Add($hl) | Out-Null
    } catch { }

    # Live search filter
    $null = $controls.TxtSearch.Add_TextChanged({ param($sender,$e)
        $q = ($controls.TxtSearch.Text | ForEach-Object { $_.ToString() })
        $q = if ($q) { $q.ToLowerInvariant() } else { '' }
        foreach ($node in $categoryNodes) {
            $anyVisible = $false
            foreach ($child in $node.Panel.Children) {
                if ($child -is [System.Windows.Controls.CheckBox] -and $child -ne $node.Panel.Children[0].Children[0]) {
                    # Extract display text from TextBlock or first TextBlock in a row panel
                    $content = $child.Content
                    if ($content -is [System.Windows.Controls.TextBlock]) {
                        $text = $content.Text
                    } elseif ($content -is [System.Windows.Controls.Panel]) {
                        $text = ''
                        foreach ($c2 in $content.Children) {
                            if ($c2 -is [System.Windows.Controls.TextBlock]) { $text = $c2.Text; break }
                        }
                    } else {
                        $text = [string]$content
                    }
                    $match = ($q -eq '' -or $text.ToLowerInvariant().Contains($q))
                    $child.Visibility = if ($match) { 'Visible' } else { 'Collapsed' }
                    if ($match) { $anyVisible = $true }
                }
            }
            $node.Expander.Visibility = if ($anyVisible -or ($q -eq '')) { 'Visible' } else { 'Collapsed' }
        }
    })

    # Dark mode toggle: replace brushes (avoid editing frozen objects)
    function New-Brush([string]$hex) {
        # hex like #RRGGBB or #AARRGGBB
        if ($hex.Length -eq 7) {
            $r = [Convert]::ToByte($hex.Substring(1,2),16)
            $g = [Convert]::ToByte($hex.Substring(3,2),16)
            $b = [Convert]::ToByte($hex.Substring(5,2),16)
            return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($r,$g,$b))
        } else {
            $a = [Convert]::ToByte($hex.Substring(1,2),16)
            $r = [Convert]::ToByte($hex.Substring(3,2),16)
            $g = [Convert]::ToByte($hex.Substring(5,2),16)
            $b = [Convert]::ToByte($hex.Substring(7,2),16)
            return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb($a,$r,$g,$b))
        }
    }

    function Set-Theme([bool]$dark) {
        $dict = $window.Resources
        $set = {
            param($k,$hex)
            if ($dict.Contains($k)) { $null = $dict.Remove($k) }
            $null = $dict.Add($k, (New-Brush $hex))
        }
        if ($dark) {
            # Dark theme (Brand)
            & $set 'App.Background' '#000000'
            & $set 'App.Card'       '#333333'
            & $set 'App.Border'     '#FDCA56'
            & $set 'App.Text'       '#FFFFFF'
            & $set 'App.MutedText'  '#999999'
            & $set 'App.Primary'    '#FDCA56'
            & $set 'App.PrimaryHover' '#F4C430'
            & $set 'App.PrimaryText' '#000000'
            & $set 'App.Secondary'  '#DB1E1F'
            & $set 'App.SecondaryHover' '#C41E3A'
            & $set 'App.SecondaryText' '#FFFFFF'
        } else {
            # Light theme (Brand): yellow background, whitesmoke card, red borders
            & $set 'App.Background' '#FDCA56'
            & $set 'App.Card'       '#F5F5F5'
            & $set 'App.Border'     '#DB1E1F'
            & $set 'App.Text'       '#000000'
            & $set 'App.MutedText'  '#666666'
            & $set 'App.Primary'    '#FDCA56'
            & $set 'App.PrimaryHover' '#F4C430'
            & $set 'App.PrimaryText' '#000000'
            & $set 'App.Secondary'  '#DB1E1F'
            & $set 'App.SecondaryHover' '#C41E3A'
            & $set 'App.SecondaryText' '#FFFFFF'
        }
    }

    $null = $controls.ChkTheme.Add_Checked({ Set-Theme $true })
    $null = $controls.ChkTheme.Add_Unchecked({ Set-Theme $false })

    # Initialize theme based on system setting: AppsUseLightTheme (1=light, 0=dark)
    try {
        $appsLight = Get-ItemProperty -Path 'HKCU:Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ($appsLight.AppsUseLightTheme -eq 0) {
            $controls.ChkTheme.IsChecked = $true
            Set-Theme $true
        } else {
            $controls.ChkTheme.IsChecked = $false
            Set-Theme $false
        }
    } catch {
        # Fallback to light theme
        $controls.ChkTheme.IsChecked = $false
        Set-Theme $false
    }

    # Ensure no horizontal scroll: resize content to viewport
    $fixWidths = {
        $vw = [int]$controls.MainScroll.ViewportWidth
        if ($vw -le 0) { return }
        $panelWidth = [math]::Max(200, $vw - 16)
        # Two cards per row: compute width accounting for margins and scrollbar
        $sideMargin = 12
        $gap = 12
        $scrollbarAllowance = 20
        $availablePerItem = [int](($vw - (2*$sideMargin) - $scrollbarAllowance) / 2)
        $itemWidth = [math]::Max(260 + $gap, $availablePerItem)
        $cardWidth = $itemWidth - $gap
        if ($controls.CategoriesPanel -is [System.Windows.Controls.WrapPanel]) {
            $controls.CategoriesPanel.ItemWidth = $itemWidth
        }
        foreach ($node in $categoryNodes) {
            if ($node.Card) { $node.Card.Width = $cardWidth; $node.Card.HorizontalAlignment = 'Left' }
        }
        foreach ($c in $packageCheckBoxes) {
            $content = $c.Content
            $maxTextWidth = [math]::Max(140, $cardWidth - 80)
            if ($content -is [System.Windows.Controls.TextBlock]) {
                $content.MaxWidth = $maxTextWidth
            } elseif ($content -is [System.Windows.Controls.Panel]) {
                foreach ($child in $content.Children) {
                    if ($child -is [System.Windows.Controls.TextBlock]) { $child.MaxWidth = $maxTextWidth; break }
                }
            }
        }
    }
    $null = $controls.MainScroll.Add_SizeChanged($fixWidths)
    $null = $window.Add_ContentRendered($fixWidths)

    # Select/Deselect All
    $null = $controls.BtnSelectAll.Add_Click({ foreach ($c in $packageCheckBoxes) { $c.IsChecked = $true } & $updateInstallButton })
    $null = $controls.BtnDeselectAll.Add_Click({ foreach ($c in $packageCheckBoxes) { $c.IsChecked = $false } & $updateInstallButton })


    # Install click handler
    $null = $controls.BtnInstall.Add_Click({
        $controls.BtnInstall.IsEnabled = $false
        $controls.StatusText.Text = 'Installing…'

        $selectedPackages = @()
        foreach ($c in $packageCheckBoxes) {
            if ($c.IsChecked -and $c.Tag -and $c.Tag.PSObject.Properties['Pkg']) { $selectedPackages += $c.Tag.Pkg }
        }

        $runState = [ordered]@{
            startedAt = (Get-Date).ToString('s')
            dryRun = [bool]$controls.ChkDryRun.IsChecked
            enableWSL = [bool]$controls.ChkWSL.IsChecked
            autoReboot = [bool]$controls.ChkReboot.IsChecked
            results = @()
        }

        if ($runState.enableWSL -and -not $runState.dryRun) {
            try { Enable-WSLFeatures } catch { Write-Host $_ -ForegroundColor Yellow }
        }

        # Build a dedicated progress window with rows: name | per-item progress | status icon
        $progressXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Installing packages" Height="540" Width="720" WindowStartupLocation="CenterScreen" Background="{DynamicResource App.Background}" Foreground="{DynamicResource App.Text}">
  <Border Background="{DynamicResource App.Card}" BorderBrush="{DynamicResource App.Border}" BorderThickness="1" Margin="12" Padding="8">
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <StackPanel x:Name="RowsPanel"/>
    </ScrollViewer>
  </Border>
</Window>
"@
        $pr = New-Object System.Xml.XmlNodeReader ([xml]$progressXaml)
        $progressWindow = [Windows.Markup.XamlReader]::Load($pr)
        $rowsPanel = $progressWindow.FindName('RowsPanel')

        # Ensure theme brushes are available in this window
        foreach ($k in @('App.Background','App.Card','App.Border','App.Text','App.MutedText','App.Primary','App.PrimaryHover','App.PrimaryText')) {
            if ($window.Resources.Contains($k)) {
                if ($progressWindow.Resources.Contains($k)) { $null = $progressWindow.Resources.Remove($k) }
                $null = $progressWindow.Resources.Add($k, $window.Resources[$k])
            }
        }

        # Pre-step: winget availability check row
        $wgGrid = New-Object System.Windows.Controls.Grid
        $wgGrid.Margin = '0,6,0,6'
        $wgGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='*' })) | Out-Null
        $wgGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='150' })) | Out-Null
        $wgGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='50' })) | Out-Null
        $wgGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='40' })) | Out-Null

        $wgLbl = New-Object System.Windows.Controls.TextBlock
        $wgLbl.Text = 'Winget check'
        $wgLbl.Foreground = $progressWindow.Resources['App.Text']
        [System.Windows.Controls.Grid]::SetColumn($wgLbl,0)

        $wgPb = New-Object System.Windows.Controls.ProgressBar
        $wgPb.Minimum = 0; $wgPb.Maximum = 100; $wgPb.Height = 14; $wgPb.Margin = '8,0,4,0'
        [System.Windows.Controls.Grid]::SetColumn($wgPb,1)

        $wgPct = New-Object System.Windows.Controls.TextBlock
        $wgPct.Text = ''
        $wgPct.HorizontalAlignment = 'Center'
        $wgPct.VerticalAlignment = 'Center'
        $wgPct.FontSize = 11
        $wgPct.Foreground = $progressWindow.Resources['App.Text']
        [System.Windows.Controls.Grid]::SetColumn($wgPct,2)

        $wgIco = New-Object System.Windows.Controls.TextBlock
        $wgIco.Text = '⏳'
        $wgIco.HorizontalAlignment = 'Center'
        $wgIco.Foreground = $progressWindow.Resources['App.Text']
        [System.Windows.Controls.Grid]::SetColumn($wgIco,3)

        $wgGrid.Children.Add($wgLbl) | Out-Null
        $wgGrid.Children.Add($wgPb) | Out-Null
        $wgGrid.Children.Add($wgPct) | Out-Null
        $wgGrid.Children.Add($wgIco) | Out-Null
        $rowsPanel.Children.Add($wgGrid) | Out-Null

        $doDownloadOnly = {
            foreach ($pkg in $selectedPackages) {
                # Row per package (minimal)
                $g = New-Object System.Windows.Controls.Grid
                $g.Margin = '0,6,0,6'
                $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='*' })) | Out-Null
                $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='150' })) | Out-Null
                $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='50' })) | Out-Null
                $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='40' })) | Out-Null

                $t = New-Object System.Windows.Controls.TextBlock
                $t.Text = [string]$pkg.name
                $t.Foreground = $progressWindow.Resources['App.Text']
                [System.Windows.Controls.Grid]::SetColumn($t,0)

                $pbi = New-Object System.Windows.Controls.ProgressBar
                $pbi.Minimum = 0; $pbi.Maximum = 100; $pbi.Height = 14; $pbi.Margin = '8,0,4,0'
                $pbi.Value = 100
                [System.Windows.Controls.Grid]::SetColumn($pbi,1)

                $pct = New-Object System.Windows.Controls.TextBlock
                $pct.Text = '100%'
                $pct.HorizontalAlignment = 'Center'
                $pct.VerticalAlignment = 'Center'
                $pct.FontSize = 11
                $pct.Foreground = $progressWindow.Resources['App.Text']
                [System.Windows.Controls.Grid]::SetColumn($pct,2)

                $ico = New-Object System.Windows.Controls.TextBlock
                $ico.Text = '📝'
                $ico.HorizontalAlignment = 'Center'
                $ico.Foreground = $progressWindow.Resources['App.Text']
                [System.Windows.Controls.Grid]::SetColumn($ico,3)

                $g.Children.Add($t) | Out-Null
                $g.Children.Add($pbi) | Out-Null
                $g.Children.Add($pct) | Out-Null
                $g.Children.Add($ico) | Out-Null
                $rowsPanel.Children.Add($g) | Out-Null

                # Open URL: manual url if present, otherwise a search query
                try {
                    if ($null -ne $pkg.PSObject.Properties['downloadUrl'] -and $pkg.downloadUrl) {
                        Start-Process ([string]$pkg.downloadUrl) | Out-Null
                    } elseif ($null -ne $pkg.PSObject.Properties['manual'] -and [bool]$pkg.manual -and $pkg.url) {
                        Start-Process $pkg.url | Out-Null
                    } else {
                        $q = [Uri]::EscapeDataString('download ' + [string]$pkg.name)
                        Start-Process ("https://www.bing.com/search?q=$q") | Out-Null
                    }
                } catch { }

                $progressWindow.Dispatcher.Invoke({}, 'Background')
            }
        }

        # Perform winget check (non-interactive)
        try {
            $psiWG = New-Object System.Diagnostics.ProcessStartInfo
            $psiWG.FileName = 'winget'
            $psiWG.Arguments = '--info'
            $psiWG.UseShellExecute = $false
            $psiWG.RedirectStandardOutput = $true
            $psiWG.RedirectStandardError = $true
            $psiWG.CreateNoWindow = $true
            $pWG = New-Object System.Diagnostics.Process
            $pWG.StartInfo = $psiWG
            $null = $pWG.Start()
            $null = $pWG.WaitForExit(15000)
            if (-not $pWG.HasExited) { try { $pWG.Kill() } catch {} }
            if ($pWG.ExitCode -eq 0) {
                $wgPb.IsIndeterminate = $false; $wgPb.Value = 100; $wgPct.Text = 'OK'; $wgIco.Text = '✅'
            } else {
                $wgPb.IsIndeterminate = $false; $wgPb.Value = 0; $wgPct.Text = 'ERR'; $wgIco.Text = '❌'
                $res = [System.Windows.MessageBox]::Show("Winget non disponibile o non funzionante. Scegli un'azione:`n`nYes = Apri App Installer nello Store`nNo = Procedi con 'Download only' per le app selezionate`nCancel = Annulla", 'Winget richiesto', 'YesNoCancel', 'Warning')
                if ($res -eq 'Yes') { try { Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" } catch { } ; return }
                elseif ($res -eq 'No') { & $doDownloadOnly; return }
                else { return }
            }
        } catch {
            $wgPb.IsIndeterminate = $false; $wgPb.Value = 0; $wgPct.Text = 'ERR'; $wgIco.Text = '❌'
            $res2 = [System.Windows.MessageBox]::Show("Winget non disponibile. Scegli un'azione:`n`nYes = Apri App Installer nello Store`nNo = Procedi con 'Download only' per le app selezionate`nCancel = Annulla", 'Winget richiesto', 'YesNoCancel', 'Warning')
            if ($res2 -eq 'Yes') { try { Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" } catch { } ; return }
            elseif ($res2 -eq 'No') { & $doDownloadOnly; return }
            else { return }
        }

        $rowControls = @()
        foreach ($pkg in $selectedPackages) {
            $grid = New-Object System.Windows.Controls.Grid
            $grid.Margin = '0,6,0,6'
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='*' })) | Out-Null
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='150' })) | Out-Null
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='50' })) | Out-Null
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width='40' })) | Out-Null

            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = [string]$pkg.name
            $lbl.TextWrapping = 'Wrap'
            $lbl.Foreground = $progressWindow.Resources['App.Text']
            [System.Windows.Controls.Grid]::SetColumn($lbl,0)

            $pbi = New-Object System.Windows.Controls.ProgressBar
            $pbi.Minimum = 0; $pbi.Maximum = 100; $pbi.Height = 14; $pbi.Margin = '8,0,4,0'
            [System.Windows.Controls.Grid]::SetColumn($pbi,1)

            $pct = New-Object System.Windows.Controls.TextBlock
            $pct.Text = '0%'
            $pct.HorizontalAlignment = 'Center'
            $pct.VerticalAlignment = 'Center'
            $pct.FontSize = 11
            $pct.Foreground = $progressWindow.Resources['App.Text']
            [System.Windows.Controls.Grid]::SetColumn($pct,2)

            $ico = New-Object System.Windows.Controls.TextBlock
            $ico.Text = '⏳'
            $ico.HorizontalAlignment = 'Center'
            $ico.Foreground = $progressWindow.Resources['App.Text']
            [System.Windows.Controls.Grid]::SetColumn($ico,3)

            $grid.Children.Add($lbl) | Out-Null
            $grid.Children.Add($pbi) | Out-Null
            $grid.Children.Add($pct) | Out-Null
            $grid.Children.Add($ico) | Out-Null
            $rowsPanel.Children.Add($grid) | Out-Null
            $rowControls += [pscustomobject]@{ name=$pkg.name; id=$pkg.id; progress=$pbi; percent=$pct; icon=$ico }
        }

        $null = $progressWindow.Show()

        $total = [double]($selectedPackages.Count)
        $i = 0
        foreach ($pkg in $selectedPackages) {
            $i++
            $pct = [math]::Round(($i/$total)*100)
            $controls.Prg.Value = $pct
            $controls.PrgItem.Value = 0
            $row = $rowControls | Where-Object { $_.name -eq $pkg.name }
            
            # Update UI immediately for this package
            if ($row) {
                $row.progress.IsIndeterminate = $true
                $row.percent.Text = '0%'
                $row.icon.Text = '⏳'
            }
            $progressWindow.Dispatcher.Invoke({}, 'Background')
            
            $isManual = $false
            if ($null -ne $pkg.PSObject.Properties['manual']) { $isManual = [bool]$pkg.manual }
            if ($isManual) {
                $started = Get-Date
                try {
                    if (-not $runState.dryRun) {
                        if ($pkg.url) { Start-Process $pkg.url | Out-Null }
                    }
                    $dur = [int]((Get-Date) - $started).TotalMilliseconds
                    $runState.results += [pscustomobject]@{ id=$null; name=$pkg.name; status='manual'; startedAt=$started.ToString('s'); durationMs=$dur; url=$pkg.url }
                    if ($row) { 
                        $row.progress.IsIndeterminate = $false
                        $row.progress.Value = 100
                        $row.percent.Text = '100%'
                        $row.icon.Text = '📝'
                    }
                } catch {
                    $dur = [int]((Get-Date) - $started).TotalMilliseconds
                    $runState.results += [pscustomobject]@{ id=$null; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$_.Exception.Message; url=$pkg.url }
                    if ($row) { 
                        $row.progress.IsIndeterminate = $false
                        $row.progress.Value = 0
                        $row.percent.Text = '0%'
                        $row.icon.Text = '❌'
                    }
                }
                $progressWindow.Dispatcher.Invoke({}, 'Background')
                continue
            }
            
            # Guard against empty/missing id
            if ([string]::IsNullOrWhiteSpace([string]$pkg.id)) {
                $started = Get-Date
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $runState.results += [pscustomobject]@{ id=$null; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage='Missing winget id' }
                if ($row) { 
                    $row.progress.IsIndeterminate = $false
                    $row.progress.Value = 0
                    $row.percent.Text = '0%'
                    $row.icon.Text = '❌'
                }
                $progressWindow.Dispatcher.Invoke({}, 'Background')
                continue
            }
            
            # Check if already installed first
            $started = Get-Date
            if (Test-IsInstalled -Id $pkg.id) {
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='already_present'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null; badge='Already installed' }
                $runState.results += $result
                if ($row) { 
                    $row.progress.IsIndeterminate = $false
                    $row.progress.Value = 100
                    $row.percent.Text = '100%'
                    $row.icon.Text = '✅'
                }
                $progressWindow.Dispatcher.Invoke({}, 'Background')
                continue
            }
            
            # Dry run check
            if ($runState.dryRun) {
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='installed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null; dryRun=$true }
                $runState.results += $result
                if ($row) { 
                    $row.progress.IsIndeterminate = $false
                    $row.progress.Value = 100
                    $row.percent.Text = '100%'
                    $row.icon.Text = '✅'
                }
                $progressWindow.Dispatcher.Invoke({}, 'Background')
                continue
            }
            
            # Non-blocking winget installation with real-time progress tracking
            try {
                # Determine timeout based on package size/complexity
                $maxWaitTime = 300000 # 5 minutes default
                if ($pkg.id -match 'Spotify|Blender|VisualStudio|Docker|WinRAR|Notepad\+\+') {
                    $maxWaitTime = 600000 # 10 minutes for large packages
                }
                
                $wingetArgs = @('install','--id', $pkg.id,'--accept-package-agreements','--accept-source-agreements','--silent')
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'winget'
                $psi.Arguments = ($wingetArgs -join ' ')
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true
                
                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                $proc.Start() | Out-Null
                
                # Track this process for cleanup
                $script:activeProcesses += $proc
                
                # Progress tracking variables
                $progressPercent = 0
                $lastUpdate = Get-Date
                $startTime = Get-Date
                $estimatedDuration = 60000 # 60 seconds default estimate for large packages
                $realProgressFound = $false
                
                # Non-blocking wait with simulated progress based on time
                while (-not $proc.HasExited) {
                    # Check for timeout
                    $elapsedMs = [int]((Get-Date) - $startTime).TotalMilliseconds
                    if ($elapsedMs -gt $maxWaitTime) {
                        # Timeout reached, kill the process
                        try {
                            $proc.Kill()
                            $proc.WaitForExit(5000)
                        } catch {
                            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                        }
                        break
                    }
                    
                    # Calculate progress based on elapsed time
                    $timeBasedProgress = [math]::Min([math]::Round(($elapsedMs / $estimatedDuration) * 100), 95)
                    
                    # Try to read output for real progress indicators
                    while ($proc.StandardOutput.Peek() -ne -1) {
                        $line = $proc.StandardOutput.ReadLine()
                        if ($line) {
                            # Parse winget output for download progress
                            $progressMatch = $line | Select-String -Pattern 'Downloaded\s+([\d.]+)\s+MB\s+of\s+([\d.]+)\s+MB'
                            if ($progressMatch) {
                                $downloadedMB = [double]$progressMatch.Matches[0].Groups[1].Value
                                $totalMB = [double]$progressMatch.Matches[0].Groups[2].Value
                                if ($totalMB -gt 0) {
                                    $progressPercent = [math]::Round(($downloadedMB / $totalMB) * 100)
                                    $realProgressFound = $true
                                }
                            }
                            
                            # Alternative patterns for different winget output formats
                            $altMatch = $line | Select-String -Pattern '(\d+)%\s+([\d.]+)\s+MB\s+/\s+([\d.]+)\s+MB'
                            if ($altMatch) {
                                $progressPercent = [int]$altMatch.Matches[0].Groups[1].Value
                                $realProgressFound = $true
                            }
                            
                            # Additional patterns for winget progress
                            $percentMatch = $line | Select-String -Pattern '(\d+)%'
                            if ($percentMatch) {
                                $newPercent = [int]$percentMatch.Matches[0].Groups[1].Value
                                # Only update if it's higher than current progress
                                if ($newPercent -gt $progressPercent) {
                                    $progressPercent = $newPercent
                                    $realProgressFound = $true
                                }
                            }
                            
                            # Look for completion indicators
                            if ($line -match 'Successfully installed|Installation completed') {
                                $progressPercent = 100
                                $realProgressFound = $true
                            }
                        }
                    }
                    
                    # Use time-based progress only if no real progress found yet
                    if (-not $realProgressFound) {
                        $progressPercent = $timeBasedProgress
                    }
                    
                    # Update UI with current progress
                    if ($row) { 
                        $row.progress.IsIndeterminate = $false
                        $row.progress.Value = $progressPercent
                        $row.percent.Text = "$progressPercent%"
                    }
                    
                    # Force UI update every 200ms
                    if (((Get-Date) - $lastUpdate).TotalMilliseconds -ge 200) {
                        $progressWindow.Dispatcher.Invoke({}, 'Background')
                        $lastUpdate = Get-Date
                    }
                    
                    Start-Sleep -Milliseconds 100
                }
                
                # Clean up process tracking
                $script:activeProcesses = $script:activeProcesses | Where-Object { $_ -ne $proc }
                
                # Wait for process to exit completely
                if (-not $proc.HasExited) {
                    $proc.WaitForExit(10000) # Wait up to 10 seconds
                }
                
                $exit = $proc.ExitCode
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                
                # Check if process was killed due to timeout
                if ($elapsedMs -gt $maxWaitTime) {
                    $timeoutMinutes = [math]::Round($maxWaitTime / 60000, 1)
                    $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage="Installation timeout ($timeoutMinutes minutes)" }
                    if ($row) { 
                        $row.progress.IsIndeterminate = $false
                        $row.progress.Value = 0
                        $row.percent.Text = '0%'
                        $row.icon.Text = '⏰'
                    }
                } elseif ($exit -eq 0) {
                    $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='installed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null }
                    if ($row) { 
                        $row.progress.IsIndeterminate = $false
                        $row.progress.Value = 100
                        $row.percent.Text = '100%'
                        $row.icon.Text = '✅'
                    }
                } else {
                    $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=("ExitCode {0}" -f $exit) }
                    if ($row) { 
                        $row.progress.IsIndeterminate = $false
                        $row.progress.Value = 0
                        $row.percent.Text = '0%'
                        $row.icon.Text = '❌'
                    }
                }
                $runState.results += $result
                
            } catch {
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$_.Exception.Message }
                $runState.results += $result
                if ($row) { 
                    $row.progress.IsIndeterminate = $false
                    $row.progress.Value = 0
                    $row.percent.Text = '0%'
                    $row.icon.Text = '❌'
                }
            }
            
            # Force UI update after each package
            $progressWindow.Dispatcher.Invoke({}, 'Background')
        }

        $counts = Write-Summary -RunState $runState -LogDir $LogDir
        $controls.StatusText.Text = 'Completed'
    })

    # Global variable to track active processes
    $script:activeProcesses = @()
    
    # Window close prompt
    $window.Add_Closing({
        param($sender, $e)
        
        # Kill all active winget processes
        foreach ($proc in $script:activeProcesses) {
            if ($proc -and -not $proc.HasExited) {
                try {
                    $proc.Kill()
                    $proc.WaitForExit(5000) # Wait up to 5 seconds
                } catch {
                    # Force kill if graceful kill fails
                    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                }
            }
        }
        $script:activeProcesses.Clear()
        
        # Allow immediate close
        $e.Cancel = $false
    })

    $window.ShowDialog() | Out-Null

}
catch {
    Show-ErrorDialog -Message ($_.Exception.Message) -Title 'Errore Onepunch-setup'
    exit 3
}
finally {
    Stop-Logging -TranscriptInfo $TranscriptInfo
}