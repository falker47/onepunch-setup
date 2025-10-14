# Onepunch-setup (Windows One‑Click Setup)

Strumento Windows “one‑click setup” per scegliere categorie e app da una GUI e installarle tramite **winget**. Il catalogo è `packages.json` (locale prima, remoto di fallback). Log dettagliati e riepilogo finale.

## Requisiti
- Windows 10/11
- PowerShell 5.1+ (consigliato PowerShell 7)
- Amministratore
- Winget (App Installer)

## Avvio rapido (script)
```powershell
# Esegui in una PowerShell come Amministratore nella cartella del progetto
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```
Opzioni:
```powershell
./setup.ps1 [-DryRun] [-EnableWSL] [-AutoReboot] [-PackagesUrl <url>] [-LogDir <path>]
```

## Manifest remoto (fallback)
Se `packages.json` non è presente accanto allo script, il manifest sarà scaricato da:
`https://raw.githubusercontent.com/falker47/onepunch-setup/main/packages.json`

## Build EXE (opzionale)
```powershell
if (-not (Get-Module -ListAvailable ps2exe)) { Install-Module ps2exe -Scope CurrentUser -Force }
Invoke-ps2exe .\setup.ps1 .\Setup-Windows.exe -noConsole -requireAdmin -iconFile .\assets\app.ico
# Oppure
./build.ps1
```

## Funzionalità
- GUI WPF con categorie espandibili e checkbox per i pacchetti
- Seleziona/Deseleziona categoria (tri‑state), Select All/Deselect All
- Idempotenza (skip se già installati), logging e JSON summary
- Toggle: Dry Run, Enable WSL, Auto Reboot

## Modifica catalogo
`packages.json` supporta:
- winget: `{ "name": "App", "id": "Vendor.App", "selected": true }`
- manuale: `{ "name": "App", "manual": true, "url": "https://…" }`

## Link utili
- Repo: https://github.com/falker47/onepunch-setup
- Manifest remoto: https://raw.githubusercontent.com/falker47/onepunch-setup/main/packages.json


