param(
    [string]$Icon = '.\assets\app.ico'
)

if (-not (Get-Module -ListAvailable ps2exe)) {
    Write-Host 'Installing ps2exe module for current user…' -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
}

$exeOut = Join-Path $PSScriptRoot 'Setup-Windows-Fixed.exe'
Write-Host ("Building EXE → {0}" -f $exeOut) -ForegroundColor Cyan

if (Test-Path $Icon) {
    Invoke-ps2exe .\setup.ps1 $exeOut -noConsole -requireAdmin -iconFile $Icon
} else {
    Write-Host ("Icon not found at {0}. Building without icon…" -f $Icon) -ForegroundColor Yellow
    Invoke-ps2exe .\setup.ps1 $exeOut -noConsole -requireAdmin
}

Write-Host 'Done.' -ForegroundColor Green


