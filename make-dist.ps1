<#
Onepunch-setup - Distribution packer
Creates a self-contained zip for end users with this layout:
  - build-and-run.cmd (root)
  - assets/ (contains setup.ps1, portable script, packages.json, docs, icon)
End users extract the zip and double-click build-and-run.cmd to compile and run locally.
#>

param(
    [string]$Output = "onepunchsetup-installer.zip"
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $root "onepunchsetup-installer"
$assetsDir = Join-Path $distDir "assets"

# Clean dist
if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

# Copy required assets
$files = @(
    'setup.ps1',
    'onepunch-setup-portable.ps1',
    'packages.json',
    'README.md',
    'BRAND-COLORS.md'
)
foreach ($f in $files) {
    $src = Join-Path $root $f
    if (Test-Path $src) { Copy-Item $src -Destination $assetsDir -Force }
}

# Optional icon (flat in assets)
$iconSrc = Join-Path $root 'assets\icon.ico'
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc -Destination (Join-Path $assetsDir 'icon.ico') -Force
}

# Copy runner CMD to root of dist
Copy-Item (Join-Path $root 'build-and-run.cmd') -Destination (Join-Path $distDir 'build-and-run.cmd') -Force

# Copy packages.json to root so the compiled EXE finds it locally (otherwise it falls back to GitHub)
Copy-Item (Join-Path $root 'packages.json') -Destination (Join-Path $distDir 'packages.json') -Force

# Create instructions file in root of dist
$instructions = @"
Onepunch-setup - Istruzioni

Prerequisiti:
- Windows 10/11, permessi Amministratore
- PowerShell 5.1+ (ok anche PowerShell 7)
- Winget (App Installer), connessione Internet

Installazione / Avvio:
1) Estrai lo zip in una cartella.
2) Fai doppio click su "build-and-run.cmd" (root dello zip).
   - Il tool installerà automaticamente ps2exe se manca.
   - Compilerà localmente l'eseguibile da assets\setup.ps1 e lo avvierà come Amministratore.
3) Se compare SmartScreen/AV, consenti l'esecuzione: l'eseguibile è stato generato in locale.

Uso dell'app:
- Le categorie sono collassate: clicca il titolo (con icona) per aprire.
- Seleziona le app con le checkbox; usa "Select/Deselect All" in grassetto per la categoria.
- Ricerca live in alto; bottone Install (rosso) avvia l'installazione.
- Badge: "Install" = via winget; "Download only" = apre il link del setup.
- Toggle: Dry Run, Enable WSL, Auto Reboot. Tema Light/Dark con palette brand.

Aggiornare il catalogo:
- Modifica assets\packages.json (tutte non selezionate di default). Riavvia l'app.

Supporto:
- Log e riepilogo JSON vengono generati automaticamente nella cartella locali dell'utente.
"@

$instrPath = Join-Path $distDir 'ISTRUZIONI.txt'
$instructions | Out-File -LiteralPath $instrPath -Encoding UTF8 -Force

# Produce ZIP
if (Test-Path $Output) { Remove-Item -Force $Output }
$zipPath = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $root $Output }

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
[System.IO.Compression.ZipFile]::CreateFromDirectory($distDir, $zipPath)

Write-Host "Created package: $zipPath" -ForegroundColor Green
