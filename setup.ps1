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

    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argsList | Out-Null
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
            return [pscustomobject]@{ id=$Id; name=$Name; status='already_present'; startedAt=$started.ToString('s'); durationMs=0; errorMessage=$null }
        }
        if ($DryRun) {
            return [pscustomobject]@{ id=$Id; name=$Name; status='installed'; startedAt=$started.ToString('s'); durationMs=0; errorMessage=$null; dryRun=$true }
        }
        $wingetArgs = @('install','--id', $Id,'--accept-package-agreements','--accept-source-agreements','--silent')
        $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        $exit = $proc.ExitCode
        $dur = [int]((Get-Date) - $started).TotalMilliseconds
        if ($exit -eq 0) {
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
        Title="Onepunch-setup" Height="560" Width="820" WindowStartupLocation="CenterScreen">
    <DockPanel LastChildFill="True">
        <StatusBar DockPanel.Dock="Bottom">
            <StatusBarItem>
                <TextBlock x:Name="StatusText" Text=""/>
            </StatusBarItem>
        </StatusBar>
        <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="8" HorizontalAlignment="Right" >
            <CheckBox x:Name="ChkDryRun" Content="Dry Run" Margin="0,0,16,0"/>
            <CheckBox x:Name="ChkWSL" Content="Enable WSL" Margin="0,0,16,0"/>
            <CheckBox x:Name="ChkReboot" Content="Auto Reboot" Margin="0,0,16,0"/>
            <Button x:Name="BtnSelectAll" Content="Select All" Width="90" Margin="0,0,8,0"/>
            <Button x:Name="BtnDeselectAll" Content="Deselect All" Width="110" Margin="0,0,8,0"/>
            <Button x:Name="BtnInstall" Content="Install" Width="90" IsEnabled="False"/>
        </StackPanel>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="CategoriesPanel" Margin="8"/>
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

    # Initialize toggles with CLI values
    $controls.ChkDryRun.IsChecked = [bool]$DryRun
    $controls.ChkWSL.IsChecked = [bool]$EnableWSL
    $controls.ChkReboot.IsChecked = [bool]$AutoReboot

    # Build categories UI
    $packageCheckBoxes = New-Object System.Collections.Generic.List[System.Windows.Controls.CheckBox]

    # Helper to enable/disable Install
    $updateInstallButton = {
        $any = $false
        foreach ($c in $packageCheckBoxes) { if ($c.IsChecked) { $any = $true; break } }
        $controls.BtnInstall.IsEnabled = $any
    }

    foreach ($categoryName in ($manifest.categories.PSObject.Properties.Name | Sort-Object)) {
        $cat = $manifest.categories.$categoryName

        $expander = New-Object System.Windows.Controls.Expander
        $expander.Header = $categoryName
        $expander.IsExpanded = $true
        $expander.Margin = '0,0,0,8'

        $catPanel = New-Object System.Windows.Controls.StackPanel
        $catPanel.Margin = '8,4,0,8'

        # Category master checkbox
        $catHeaderPanel = New-Object System.Windows.Controls.StackPanel
        $catHeaderPanel.Orientation = 'Horizontal'
        $catCheck = New-Object System.Windows.Controls.CheckBox
        $catCheck.Content = "Seleziona/Deseleziona categoria"
        $catCheck.Margin = '0,0,0,8'
        $catHeaderPanel.Children.Add($catCheck) | Out-Null
        $catPanel.Children.Add($catHeaderPanel) | Out-Null

        foreach ($pkg in $cat.packages) {
            $chk = New-Object System.Windows.Controls.CheckBox
            $display = if ($pkg.id) { "$($pkg.name)  ($($pkg.id))" } else { $pkg.name }
            $chk.Content = $display
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
        $controls.CategoriesPanel.Children.Add($expander) | Out-Null
    }

    foreach ($c in $packageCheckBoxes) {
        $null = $c.Add_Checked($updateInstallButton)
        $null = $c.Add_Unchecked($updateInstallButton)
    }
    & $updateInstallButton

    # Select/Deselect All
    $null = $controls.BtnSelectAll.Add_Click({ foreach ($c in $packageCheckBoxes) { $c.IsChecked = $true } & $updateInstallButton })
    $null = $controls.BtnDeselectAll.Add_Click({ foreach ($c in $packageCheckBoxes) { $c.IsChecked = $false } & $updateInstallButton })


    # Install click handler
    $null = $controls.BtnInstall.Add_Click({
        $controls.BtnInstall.IsEnabled = $false
        $controls.StatusText.Text = 'Installazione in corso…'

        $selectedPackages = @()
        foreach ($c in $packageCheckBoxes) {
            if ($c.IsChecked) { $selectedPackages += $c.Tag }
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

        foreach ($pkg in $selectedPackages) {
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
            $result = Install-Package -Id $pkg.id -Name $pkg.name -DryRun:$runState.dryRun
            $runState.results += $result
        }

        $counts = Write-Summary -RunState $runState -LogDir $LogDir

        $controls.StatusText.Text = 'Completato'

        $message = "Installati: $($counts.installed)\nGià presenti: $($counts.already_present)\nFalliti: $($counts.failed)\n\nAprire la cartella log?"
        $res = [System.Windows.MessageBox]::Show($message, 'Onepunch-setup - Sommario', 'YesNo', 'Information')
        if ($res -eq 'Yes') { Start-Process explorer.exe $LogDir }

        if ($runState.autoReboot -and -not $runState.dryRun) {
            $r = [System.Windows.MessageBox]::Show('Riavviare ora il computer?','Auto Reboot','YesNo','Question')
            if ($r -eq 'Yes') { Restart-Computer -Force }
        }
    })

    # Window close prompt
    $window.Add_Closing({
        # allow immediate close if not installing currently
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


