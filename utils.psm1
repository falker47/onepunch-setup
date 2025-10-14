Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

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
    $localPath = Join-Path $PSScriptRoot 'packages.json'
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        # Fallback when PSScriptRoot is empty (e.g., when running as EXE)
        $exePath = [System.Reflection.Assembly]::GetExecutingAssembly().Location
        if ($exePath) {
            $localPath = Join-Path (Split-Path -Parent $exePath) 'packages.json'
        } else {
            # Last resort: try current directory
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
    param(
        [Parameter(Mandatory=$true)]$Manifest
    )
    if (-not $Manifest.categories) { throw 'Manifest non valido: manca la proprietà categories' }
    foreach ($kvp in $Manifest.categories.GetEnumerator()) {
        $categoryName = $kvp.Key
        $category = $kvp.Value
        if (-not $category.packages -or $category.packages.Count -eq 0) {
            throw ("Categoria '{0}' non valida: packages è vuoto" -f $categoryName)
        }
        foreach ($pkg in $category.packages) {
            if (-not $pkg.name -or -not $pkg.id) {
                throw ("Pacchetto in '{0}' non valido: 'name' e 'id' sono richiesti" -f $categoryName)
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
        $wingetArgs = @('install','--id', $Id,'--accept-package-agreements','--accept-source-agreements','-h','0')
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
    ($summary | ConvertTo-Json -Depth 10 -Compress:$false) | Out-File -FilePath $summaryPath -Encoding utf8
    Write-Host ("Sommario scritto in: {0}" -f $summaryPath) -ForegroundColor Green
    return [pscustomobject]$counts
}

function Enable-WSLFeatures {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart -ErrorAction Stop | Out-Null
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction Stop | Out-Null
}

Export-ModuleMember -Function Start-AdminElevation, Start-Logging, Stop-Logging, Get-Manifest, Test-Manifest, Test-IsInstalled, Install-Package, Write-Summary, Enable-WSLFeatures, Show-ErrorDialog


