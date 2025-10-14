<#!
Onepunch-setup - Compile script
Use this command to build the EXE: .\compile.ps1

Usage examples (run in PowerShell as Administrator):
  # Default build → .\onepunch-setup.exe
  .\compile.ps1

  # Custom name and icon
  .\compile.ps1 -Name "Onepunch-setup" -Icon ".\assets\app.ico"

This script will:
  - Ensure TLS 1.2
  - Ensure ps2exe module is installed
  - Stop any running output EXE with the same name
  - Build the EXE from setup.ps1 (-noConsole, -requireAdmin)
!#>

param(
    [string]$Name = "onepunch-setup",
    [string]$Icon = ".\\assets\\icon.ico",
    [switch]$EmbedManifest
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Default EmbedManifest to true when not explicitly provided
if (-not $PSBoundParameters.ContainsKey('EmbedManifest')) { $EmbedManifest = $true }

# Ensure ps2exe is available
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe..." -ForegroundColor Yellow
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default -ErrorAction SilentlyContinue | Out-Null
    }
    try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}

$outFile = Join-Path $PSScriptRoot ("{0}.exe" -f $Name)
Write-Host ("Output → {0}" -f $outFile) -ForegroundColor Cyan

# Stop running instance if any (only if output exists)
try {
    if (Test-Path $outFile) {
        $resolved = Resolve-Path $outFile
        Get-Process | Where-Object { $_.Path -and $_.Path -ieq $resolved } |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $outFile) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $outFile = Join-Path $PSScriptRoot ("{0}-{1}.exe" -f $Name, $stamp)
            Write-Host ("Target locked, building as → {0}" -f $outFile) -ForegroundColor Yellow
        }
    }
} catch { }

# Prepare source path (optionally with embedded manifest)
$source = Join-Path $PSScriptRoot 'setup.ps1'
$tempSource = $null
if ($EmbedManifest) {
    $pkgPath = Join-Path $PSScriptRoot 'packages.json'
    if (Test-Path $pkgPath) {
        $json = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $tempSource = Join-Path $env:TEMP ('setup_embed_' + [Guid]::NewGuid().ToString() + '.ps1')
        $content = Get-Content -LiteralPath $source -Raw -Encoding UTF8
        $content = $content.Replace('<#EMBED_PACKAGES_JSON#>', $b64)
        $content | Out-File -LiteralPath $tempSource -Encoding UTF8
        $source = $tempSource
        Write-Host 'Embedded packages.json into setup.ps1 for this build.' -ForegroundColor Green
    } else {
        Write-Host 'Embed requested but packages.json not found. Skipping embedding.' -ForegroundColor Yellow
    }
}

# Build
if (Test-Path $Icon) {
    Invoke-ps2exe $source $outFile -noConsole -requireAdmin -iconFile $Icon
} else {
    Write-Host ("Icon not found at {0}, building without icon..." -f $Icon) -ForegroundColor Yellow
    Invoke-ps2exe $source $outFile -noConsole -requireAdmin
}

if ($tempSource -and (Test-Path $tempSource)) { Remove-Item -LiteralPath $tempSource -Force -ErrorAction SilentlyContinue }

Write-Host "Done." -ForegroundColor Green


