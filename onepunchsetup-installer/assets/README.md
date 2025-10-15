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
## Distribuzione (ZIP per utenti finali)
Per ridurre falsi positivi AV, distribuisci uno ZIP che compila localmente:
1) Crea lo ZIP:
```powershell
powershell -ExecutionPolicy Bypass -File .\make-dist.ps1 -Output onepunchsetup.zip
```
2) L’utente estrae `onepunchsetup.zip` e fa doppio click su `build-and-run.cmd` (compila e avvia usando i file in `assets/`).

## Manifest remoto (fallback)
Se `packages.json` non è presente accanto allo script, il manifest sarà scaricato da:
`https://raw.githubusercontent.com/falker47/onepunch-setup/main/packages.json`

## Build EXE (opzionale)
```powershell
# Converte lo script in EXE (usa icona se presente)
if (-not (Get-Module -ListAvailable ps2exe)) { Install-Module ps2exe -Scope CurrentUser -Force }
Invoke-ps2exe .\setup.ps1 .\onepunch-setup.exe -noConsole -requireAdmin -iconFile .\assets\icon.ico

# Oppure usa lo script di compilazione con embedding del manifest
powershell -ExecutionPolicy Bypass -File .\compile.ps1 -EmbedPackagesJson
```

## Funzionalità
- GUI WPF con categorie collassate di default, header con icona e titolo
- Layout a 2 colonne indipendenti (spazi verticali fissi per colonna)
- Ricerca live, badge “Install” (winget) / “Download only” (link diretto)
- Seleziona/Deseleziona categoria (tri‑state) con testo in grassetto; default: tutte non selezionate
- Light/Dark mode con palette brand da `BRAND-COLORS.md`; credit link in basso
- Idempotenza (skip se già installati), logging e riepilogo JSON finale
- Toggle: Dry Run, Enable WSL, Auto Reboot; abilitazione WSL opzionale

## Modifica catalogo
`packages.json` supporta:
- winget: `{ "name": "App", "id": "Vendor.App", "selected": true }`
- manuale: `{ "name": "App", "manual": true, "url": "https://…" }`

Note:
- Tutte le app sono non selezionate di default (puoi impostare `selected: true` dove serve).
- Per app senza ID winget (es. Cursor, GIMP) usa `manual: true` + `url` (comparirà “Download only”).

## Packaging MSI (per ridurre falsi positivi AV)
- Consigliato: WiX Toolset v4 (`dotnet-wix`) o MSIX.
- Passi tipici: includi `onepunch-setup.exe`, crea Feature/Component, scorciatoie, compila con `wix build`.
- Firma EXE e MSI (Authenticode con `signtool`) e distribuisci via HTTPS.

## Link utili
- Repo: https://github.com/falker47/onepunch-setup
- Manifest remoto: https://raw.githubusercontent.com/falker47/onepunch-setup/main/packages.json


