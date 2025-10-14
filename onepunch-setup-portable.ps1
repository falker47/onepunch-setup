# Onepunch-setup Portable Version
# Questa versione evita i problemi di antivirus usando direttamente PowerShell

param(
    [switch]$DryRun,
    [switch]$EnableWSL,
    [switch]$AutoReboot,
    [string]$PackagesUrl,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Constants
$DefaultPackagesUrl = 'https://raw.githubusercontent.com/falker47/onepunch-setup/main/packages.json'
$DefaultLogDir = Join-Path $env:LOCALAPPDATA 'pc-setup\logs'

if (-not $PackagesUrl -or [string]::IsNullOrWhiteSpace($PackagesUrl)) {
    $PackagesUrl = $DefaultPackagesUrl
}
if (-not $LogDir -or [string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = $DefaultLogDir
}

# Import the utils module if available, otherwise use embedded functions
$utilsPath = Join-Path $PSScriptRoot 'utils.psm1'
if (Test-Path $utilsPath) {
    Import-Module $utilsPath -Force
} else {
    # Embedded functions (same as in setup.ps1)
    function Start-AdminElevation {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) { return }

        Write-Host 'Elevazione privilegi richiesta, rilancio come amministratore…' -ForegroundColor Yellow

        $psExe = (Get-Process -Id $PID).Path
        $argsList = @()
        if ($MyInvocation.MyCommand.Path) {
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

        if ($argsList.Count -gt 0) {
            Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argsList | Out-Null
        } else {
            Start-Process -FilePath $psExe -Verb RunAs | Out-Null
        }
        exit 0
    }

    function Start-Logging {
        param([Parameter(Mandatory=$true)][string]$LogDir)
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logPath = Join-Path $LogDir ("setup-{0}.log" -f $ts)
        Start-Transcript -Path $logPath -Force | Out-Null
        return @{ LogPath = $logPath; StartedAt = (Get-Date) }
    }

    function Stop-Logging {
        param([Parameter(Mandatory=$true)][hashtable]$TranscriptInfo)
        try { Stop-Transcript | Out-Null } catch { }
    }

    function Show-ErrorDialog {
        param([Parameter(Mandatory=$true)][string]$Message, [string]$Title = 'Errore')
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
    }

    function Get-Manifest {
        param([Parameter(Mandatory=$true)][string]$PackagesUrl)
        $localPath = Join-Path $PSScriptRoot 'packages.json'
        if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $exePath = [System.Reflection.Assembly]::GetExecutingAssembly().Location
            if ($exePath) {
                $localPath = Join-Path (Split-Path -Parent $exePath) 'packages.json'
            } else {
                $localPath = Join-Path (Get-Location) 'packages.json'
            }
        }
        if (Test-Path $localPath) {
            Write-Host "Carico manifest da file locale: $localPath" -ForegroundColor Cyan
            $raw = Get-Content -LiteralPath $localPath -Raw -Encoding UTF8
            return $raw | ConvertFrom-Json
        }
        Write-Host "Manifest locale non trovato. Scarico da: $PackagesUrl" -ForegroundColor Yellow
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
        param([Parameter(Mandatory=$true)]$Manifest)
        if (-not $Manifest.categories) { throw 'Manifest non valido: manca la proprietà categories' }
        foreach ($categoryName in $Manifest.categories.PSObject.Properties.Name) {
            $category = $Manifest.categories.$categoryName
            if (-not $category.packages -or $category.packages.Count -eq 0) {
                throw ("Categoria '{0}' non valida: packages è vuoto" -f $categoryName)
            }
            foreach ($pkg in $category.packages) {
                if (-not $pkg.name) { throw ("Pacchetto in '{0}' non valido: 'name' è richiesto" -f $categoryName) }
                $isManual = $false
                if ($null -ne $pkg.PSObject.Properties['manual']) { $isManual = [bool]$pkg.manual }
                if ($isManual) {
                    if (-not $pkg.url -or [string]::IsNullOrWhiteSpace([string]$pkg.url)) {
                        throw ("Pacchetto manuale '{0}' in '{1}' non valido: 'url' è richiesto" -f $pkg.name, $categoryName)
                    }
                } else {
                    if (-not $pkg.id -or [string]::IsNullOrWhiteSpace([string]$pkg.id)) {
                        throw ("Pacchetto in '{0}' non valido: 'id' è richiesto (o manual=true con url)" -f $categoryName)
                    }
                }
            }
        }
    }

    function Test-IsInstalled {
        param([Parameter(Mandatory=$true)][string]$Id)
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
        if ($out -match [Regex]::Escape($Id)) { return $true }
        return $false
    }

    function Enable-WSLFeatures {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart -ErrorAction Stop | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction Stop | Out-Null
    }
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

    # Build GUI (WPF) - Same as original setup.ps1 but with fixed search
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Onepunch-setup" Height="620" Width="900" WindowStartupLocation="CenterScreen" Background="{DynamicResource App.Background}" Foreground="{DynamicResource App.Text}">
    <Window.Resources>
        <!-- Theme brushes (DynamicResource for live toggle) -->
        <!-- Light theme default -->
        <SolidColorBrush x:Key="App.Background" Color="#F5F6F7" />
        <SolidColorBrush x:Key="App.Card" Color="#FFFFFF" />
        <SolidColorBrush x:Key="App.Border" Color="#E2E5E9" />
        <SolidColorBrush x:Key="App.Text" Color="#11141A" />
        <SolidColorBrush x:Key="App.MutedText" Color="#6B7280" />
        <SolidColorBrush x:Key="App.Primary" Color="#2563EB" />
        <SolidColorBrush x:Key="App.PrimaryHover" Color="#1D4ED8" />
        <SolidColorBrush x:Key="App.PrimaryText" Color="#FFFFFF" />

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
        <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="12" HorizontalAlignment="Right" >
            <CheckBox x:Name="ChkDryRun" Content="Dry Run" Margin="0,0,16,0"/>
            <CheckBox x:Name="ChkWSL" Content="Enable WSL" Margin="0,0,16,0"/>
            <CheckBox x:Name="ChkReboot" Content="Auto Reboot" Margin="0,0,24,0"/>
            <Button x:Name="BtnSelectAll" Content="Select All" Margin="0,0,8,0"/>
            <Button x:Name="BtnDeselectAll" Content="Deselect All" Margin="0,0,24,0"/>
            <Button x:Name="BtnInstall" Content="Install" Style="{StaticResource PrimaryButton}" IsEnabled="False" MinWidth="140" Padding="16,8" FontSize="14" FontWeight="Bold"/>
        </StackPanel>
        <ScrollViewer x:Name="MainScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Background="{DynamicResource App.Background}">
            <StackPanel x:Name="CategoriesPanel" Margin="12"/>
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

    # Initialize toggles with CLI values
    $controls.ChkDryRun.IsChecked = [bool]$DryRun
    $controls.ChkWSL.IsChecked = [bool]$EnableWSL
    $controls.ChkReboot.IsChecked = [bool]$AutoReboot

    # Build categories UI
    $packageCheckBoxes = New-Object System.Collections.Generic.List[System.Windows.Controls.CheckBox]
    $categoryNodes = New-Object System.Collections.Generic.List[object]

    # Helper to enable/disable Install
    $updateInstallButton = {
        $any = $false
        foreach ($c in $packageCheckBoxes) { if ($c.IsChecked) { $any = $true; break } }
        $controls.BtnInstall.IsEnabled = $any
    }

    foreach ($categoryName in ($manifest.categories.PSObject.Properties.Name | Sort-Object)) {
        $cat = $manifest.categories.$categoryName

        $expander = New-Object System.Windows.Controls.Expander
        $hdrText = New-Object System.Windows.Controls.TextBlock
        $hdrText.Text = $categoryName
        $hdrText.FontSize = 18
        $hdrText.FontWeight = 'Bold'
        $hdrText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'App.Text')
        $expander.Header = $hdrText
        $expander.IsExpanded = $true
        $expander.Margin = '0,0,0,8'
        
        $card = New-Object System.Windows.Controls.Border
        $card.Style = $window.Resources["Card"]
        $catPanel = New-Object System.Windows.Controls.StackPanel
        $catPanel.Margin = '8,4,0,8'

        # Category master checkbox
        $catHeaderPanel = New-Object System.Windows.Controls.StackPanel
        $catHeaderPanel.Orientation = 'Horizontal'
        $catCheck = New-Object System.Windows.Controls.CheckBox
        $catCheck.Content = "Select/Deselect All"
        $catCheck.Margin = '0,0,0,8'
        $catHeaderPanel.Children.Add($catCheck) | Out-Null
        $catPanel.Children.Add($catHeaderPanel) | Out-Null

        foreach ($pkg in $cat.packages) {
            $chk = New-Object System.Windows.Controls.CheckBox
            $display = if ($pkg.id) { "$($pkg.name)  ($($pkg.id))" } else { $pkg.name }
            $textBlock = New-Object System.Windows.Controls.TextBlock
            $textBlock.Text = $display
            $textBlock.TextWrapping = 'Wrap'
            $textBlock.TextTrimming = 'CharacterEllipsis'
            $chk.Content = $textBlock
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
        $controls.CategoriesPanel.Children.Add($card) | Out-Null
        $null = $categoryNodes.Add([pscustomobject]@{ Name=$categoryName; Expander=$expander; Panel=$catPanel; Card=$card })
    }

    foreach ($c in $packageCheckBoxes) {
        $null = $c.Add_Checked($updateInstallButton)
        $null = $c.Add_Unchecked($updateInstallButton)
    }
    & $updateInstallButton

    # Live search filter - FIXED VERSION
    $null = $controls.TxtSearch.Add_TextChanged({ param($sender,$e)
        $q = ($controls.TxtSearch.Text | ForEach-Object { $_.ToString() })
        $q = if ($q) { $q.ToLowerInvariant() } else { '' }
        foreach ($node in $categoryNodes) {
            $anyVisible = $false
            foreach ($child in $node.Panel.Children) {
                if ($child -is [System.Windows.Controls.CheckBox] -and $child -ne $node.Panel.Children[0].Children[0]) {
                    # Get text from TextBlock content properly
                    $textBlock = $child.Content
                    if ($textBlock -is [System.Windows.Controls.TextBlock]) {
                        $text = $textBlock.Text
                    } else {
                        $text = [string]$textBlock
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
            & $set 'App.Background' '#000000'
            & $set 'App.Card'       '#1F2937'
            & $set 'App.Border'     '#374151'
            & $set 'App.Text'       '#FFFFFF'
            & $set 'App.MutedText'  '#9CA3AF'
        } else {
            & $set 'App.Background' '#F5F6F7'
            & $set 'App.Card'       '#FFFFFF'
            & $set 'App.Border'     '#E2E5E9'
            & $set 'App.Text'       '#11141A'
            & $set 'App.MutedText'  '#6B7280'
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
        $controls.CategoriesPanel.Width = $panelWidth
        foreach ($node in $categoryNodes) {
            if ($node.Card) { $node.Card.Width = [math]::Max(200, $vw - 24) }
        }
        foreach ($c in $packageCheckBoxes) {
            if ($c.Content -is [System.Windows.Controls.TextBlock]) {
                ($c.Content).MaxWidth = [math]::Max(200, $vw - 80)
            }
        }
    }
    $null = $controls.MainScroll.Add_SizeChanged($fixWidths)
    $null = $window.Add_ContentRendered($fixWidths)

    # Select/Deselect All
    $null = $controls.BtnSelectAll.Add_Click({ foreach ($c in $packageCheckBoxes) { $c.IsChecked = $true } & $updateInstallButton })
    $null = $controls.BtnDeselectAll.Add_Click({ foreach ($c in $packageCheckBoxes) { $c.IsChecked = $false } & $updateInstallButton })

    # Install click handler - Simplified version for portable
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

        # Simple installation loop
        $total = [double]($selectedPackages.Count)
        $i = 0
        foreach ($pkg in $selectedPackages) {
            $i++
            $pct = [math]::Round(($i/$total)*100)
            $controls.Prg.Value = $pct
            $controls.StatusText.Text = "Installing $($pkg.name)..."
            
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
                } catch {
                    $dur = [int]((Get-Date) - $started).TotalMilliseconds
                    $runState.results += [pscustomobject]@{ id=$null; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$_.Exception.Message; url=$pkg.url }
                }
                continue
            }
            
            # Guard against empty/missing id
            if ([string]::IsNullOrWhiteSpace([string]$pkg.id)) {
                $started = Get-Date
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $runState.results += [pscustomobject]@{ id=$null; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage='Missing winget id' }
                continue
            }
            
            # Check if already installed first
            $started = Get-Date
            if (Test-IsInstalled -Id $pkg.id) {
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='already_present'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null; badge='Already installed' }
                $runState.results += $result
                continue
            }
            
            # Dry run check
            if ($runState.dryRun) {
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='installed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null; dryRun=$true }
                $runState.results += $result
                continue
            }
            
            # Simple winget installation
            try {
                $wingetArgs = @('install','--id', $pkg.id,'--accept-package-agreements','--accept-source-agreements','--silent')
                $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                $exit = $proc.ExitCode
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                if ($exit -eq 0) {
                    $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='installed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$null }
                } else {
                    $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=("ExitCode {0}" -f $exit) }
                }
                $runState.results += $result
            } catch {
                $dur = [int]((Get-Date) - $started).TotalMilliseconds
                $result = [pscustomobject]@{ id=$pkg.id; name=$pkg.name; status='failed'; startedAt=$started.ToString('s'); durationMs=$dur; errorMessage=$_.Exception.Message }
                $runState.results += $result
            }
        }

        $controls.StatusText.Text = 'Completed'
        $controls.BtnInstall.IsEnabled = $true
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
