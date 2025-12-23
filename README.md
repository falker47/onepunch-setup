# Onepunch-setup (Windows One‑Click Setup)

A Windows "one-click setup" tool that allows users to select categories and applications from a WPF GUI and install them via **winget**. The catalog is defined in `packages.json` (searched locally first, then falls back to a remote URL). It provides detailed logs and a final JSON summary of the installation process.

## Requirements
- Windows 10/11
- PowerShell 5.1+ (PowerShell 7 recommended)
- Administrator privileges
- **Winget** (App Installer)

## Key Features
- **WPF GUI**: User-friendly interface with collapsible categories, icons, and a search bar.
- **Packages Catalog**: Controlled via `packages.json`. Supports both Winget IDs and manual download URLs.
- **Smart Logic**: Checks if apps are already installed (idempotency), logs extensively, and generates a JSON summary.
- **Customization**: Light/Dark mode with brand colors defined in `BRAND-COLORS.md`.
- **Options**: Toggles for Dry Run, Enable WSL, and Auto Reboot.

---

## File Structure & Purpose

Below is a detailed explanation of each file in this repository:

### Core Application
- **`setup.ps1`**  
  The main application script. It contains the logic for the GUI (WPF), theme management, package installation (calling `winget`), and logging. This is the source code of the "app".

- **`packages.json`**  
  The configuration catalog. It defines the categories (e.g., Browser, Dev) and the list of packages available for installation.
  - Supports `id` for Winget packages.
  - Supports `manual: true` and `url` for direct download links (displayed as "Download only").

- **`utils.psm1`**  
  A PowerShell module containing helper functions used by the main script, such as:
  - `Start-AdminElevation`: Handles auto-elevation to Administrator.
  - `Start-Logging` / `Write-Summary`: Manages execution logs and result summaries.
  - `Install-Package`: Wraps `winget` calls with error handling.

### Building & Distribution
- **`make-dist.ps1`**  
  **For Developers:** This script builds the distribution package for end-users.
  1. Creates an output directory (e.g., `onepunchsetup-installer`).
  2. Copies all necessary assets (`setup.ps1`, `packages.json`, icons, etc.) into an `assets` folder.
  3. Copies the `build-and-run.cmd` launcher to the root.
  4. Zips everything into a single file (e.g., `onepunchsetup-installer.zip`) ready for distribution.

- **`build-and-run.cmd`**  
  **For End Users:** This is the launcher included in the distribution zip.
  1. Checks if the `ps2exe` module is installed (installs it if missing).
  2. Compiles `assets\setup.ps1` into a standalone executable (`onepunch-setup.exe`) on the user's machine.
  3. Automatically runs the generated EXE as Administrator.

- **`compile.ps1`**  
  An optional helper script to manually compile `setup.ps1` into an EXE. It supports embedding `packages.json` directly into the executable for a single-file portable app experience.

### Assets & Docs
- **`assets/`**: Folder containing resources like the application icon (`icon.ico`) and other runtime dependencies.
- **`BRAND-COLORS.md`**: Documentation reference for the color palette used in the GUI theme.
- **`README.md`**: This documentation file.

---

## Quick Start (For Developers)

To run the app directly from source:
```powershell
# Run in PowerShell as Administrator
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

**Common Options:**
```powershell
.\setup.ps1 -DryRun              # Simulate installation without changes
.\setup.ps1 -EnableWSL           # Enable WSL features
.\setup.ps1 -AutoReboot          # Reboot automatically after completion
```

## How to Distribute (Create Installer)

1. Run the distribution script:
   ```powershell
   .\make-dist.ps1
   ```
2. This creates `onepunchsetup-installer.zip`.
3. Send this ZIP to the user.
4. The user unzips it and runs `build-and-run.cmd`.

## Customizing the Catalog

Edit `packages.json` to add or remove apps.
- **Winget app:**
  ```json
  { "name": "Firefox", "id": "Mozilla.Firefox", "selected": false }
  ```
- **Manual download:**
  ```json
  { "name": "Cursor", "manual": true, "url": "https://...", "selected": false }
  ```
