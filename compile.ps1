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
    [string]$Icon = ".\assets\app.ico"
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
    }
} catch { }

# Build
if (Test-Path $Icon) {
    Invoke-ps2exe .\setup.ps1 $outFile -noConsole -requireAdmin -iconFile $Icon
} else {
    Write-Host ("Icon not found at {0}, building without icon..." -f $Icon) -ForegroundColor Yellow
    Invoke-ps2exe .\setup.ps1 $outFile -noConsole -requireAdmin
}

Write-Host "Done." -ForegroundColor Green


