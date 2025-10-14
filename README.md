# Onepunch-setup (Windows One‑Click Setup)

Un tool Windows che permette di selezionare categorie di software e singole app da una GUI, poi le installa tramite **winget**. Il tool legge il catalogo da **packages.json** (locale prima, fallback remoto), logga tutto e mostra un riepilogo finale.

## Quick Start

1) Right-click `setup.ps1` → Run with PowerShell (as Administrator).
2) Pick categories and apps in the GUI.
3) Click Install. Review summary; open logs if needed.

## Features

- Local‑first `packages.json` (remote fallback URL is configurable).
- Idempotent installs via winget (skips already installed).
- Optional toggles: Dry Run, Enable WSL, Auto Reboot.
- Logs transcript and JSON summary under `%LOCALAPPDATA%\pc-setup\logs`.

## CLI Options
```powershell
./setup.ps1 [-DryRun] [-EnableWSL] [-AutoReboot] [-PackagesUrl <url>] [-LogDir <path>]
```

## Remote manifest fallback
- If `packages.json` is missing next to `setup.ps1`, the script downloads from the default URL.

## Build EXE (optional)
```powershell
if (-not (Get-Module -ListAvailable ps2exe)) { Install-Module ps2exe -Scope CurrentUser -Force }
Invoke-ps2exe .\setup.ps1 .\Setup-Windows.exe -noConsole -requireAdmin -iconFile .\assets\app.ico
```

Or simply run the helper:
```powershell
./build.ps1
```

## GitHub Setup

1. **Create repository**: Create a new GitHub repo named `pc-setup`
2. **Upload files**: Upload all files except `*.exe` and `logs/` folder
3. **Update URL**: Edit `setup.ps1` line 13 to match your GitHub username:
   ```powershell
   $DefaultPackagesUrl = 'https://raw.githubusercontent.com/YOUR_USERNAME/pc-setup/main/packages.json'
   ```
4. **Test**: Run the script without local `packages.json` to test remote loading

## Customization

Edit `packages.json` to add/remove software categories and packages. Each package needs:
- `name`: Display name
- `id`: winget package ID (find with `winget search <name>`)
- `selected`: true/false for default selection


