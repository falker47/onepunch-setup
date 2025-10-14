# Windows One‑Click Setup – Cursor Implementation Brief

> **Goal**: Build a Windows "one‑click setup" tool that lets a user pick software categories and individual apps from a GUI, then installs them via **winget**. The tool reads its catalog from **packages.json** (local first, remote fallback), logs everything, and shows a final summary. Deliver as a PowerShell script (with optional .exe packaging).

---

## 1) Deliverables

- `setup.ps1` – main script with GUI, selection logic, installation, logging, summary.
- `packages.json` – external manifest defining categories & packages (local file, remote fallback).
- `utils.psm1` – helper module (JSON load/validate, logging, winget helpers, summary builder, error handling).
- `logs/` – output folder for transcripts and structured logs.
- `README.md` – quick start and usage instructions (generate a concise version for end users).
- Optional: `Setup-Windows.exe` generated via `ps2exe` with an embedded icon in `assets/`.

**Acceptance Criteria**
- Runs on Windows 10/11 with PowerShell 5.1+ (prefer PS 7 if present).
- Elevates to admin when required.
- GUI allows selecting/deselecting **categories** and **individual packages** (expand/collapse per category).
- Reads `packages.json` from the current directory; if missing, downloads from a configurable GitHub raw URL.
- Idempotent: skips already installed apps.
- Writes human‑readable log and machine‑readable JSON summary in `logs/`.
- Displays an end‑of‑run summary dialog.

---

## 2) System Design

### 2.1 Architecture
```
pc-setup/
  setup.ps1
  utils.psm1
  packages.json              # local manifest; optional at runtime
  assets/
    app.ico                  # optional exe icon
  logs/
    setup-YYYYMMDD-HHMMSS.log
    summary-YYYYMMDD-HHMMSS.json
  README.md
```

### 2.2 Control Flow (High Level)
1. **Ensure Admin** → relaunch elevated if needed.
2. **Locate Manifest** → try `./packages.json`; if absent, fetch remote URL (configurable constant).
3. **Validate Manifest** → schema & required fields.
4. **GUI** → display categories with expandable package lists and checkboxes.
5. **Collect Selections** → categories & per‑package overrides.
6. **Install** → for each selected package, check installed → install via `winget` if missing.
7. **Log** → transcript + per‑package status, errors, durations.
8. **Summary** → show dialog with counts: installed, already present, failed.

---

## 3) Runtime Options & Defaults

Support these optional flags (CLI and GUI toggles):
- `-DryRun` (default: false): simulate without installing.
- `-EnableWSL` (default: false): enable Windows features `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` (no reboot).
- `-AutoReboot` (default: false): reboot after success.
- `-PackagesUrl` (default: GitHub raw URL; use only if local `packages.json` missing).
- `-LogDir` (default: `%LOCALAPPDATA%\pc-setup\logs`).

Behavioral rules:
- **Local-first manifest**. Only download remote if local is missing.
- **Idempotency**: detect by `winget list --id` exact match.
- **Resilience**: if a package fails, continue with the next; record error.

---

## 4) GUI Specification (WPF)

**Requirement:** a simple WPF window created from PowerShell that provides:
- Sidebar or accordion listing **categories**. Click/expand to show packages.
- Each package: `Checkbox` + display name + (optional) ID in muted text.
- Category header has a `Checkbox` to select/deselect all packages in that category.
- Buttons: `Select All`, `Deselect All`, `Install`, `Cancel`.
- Optional toggles (bottom area): `Dry Run`, `Enable WSL`, `Auto Reboot`.
- Status bar region for transient messages (e.g., "Loading manifest…").
- On close/cancel: prompt confirmation if a run is pending.

**UX Details**
- Preselect packages based on `selected: true` in manifest.
- Enable `Install` only if at least one package is selected.
- After `Install`, show a modal with the summary and a link/button to open the log folder.

---

## 5) Manifest Format (`packages.json`)

### 5.1 JSON Schema (informal)
```json
{
  "categories": {
    "<CategoryName>": {
      "description": "string (optional)",
      "packages": [
        {
          "name": "string (required)",
          "id": "string (required winget ID)",
          "selected": true
        }
      ]
    }
  }
}
```

### 5.2 Example
```json
{
  "categories": {
    "Base": {
      "description": "Strumenti essenziali per tutti",
      "packages": [
        { "name": "Google Chrome", "id": "Google.Chrome", "selected": true },
        { "name": "7-Zip", "id": "7zip.7zip", "selected": true },
        { "name": "Notepad++", "id": "Notepad++.Notepad++", "selected": true }
      ]
    },
    "Dev": {
      "description": "Ambiente di sviluppo",
      "packages": [
        { "name": "Visual Studio Code", "id": "Microsoft.VisualStudioCode", "selected": true },
        { "name": "Python 3", "id": "Python.Python.3.12", "selected": true },
        { "name": "Node.js LTS", "id": "OpenJS.NodeJS.LTS", "selected": false },
        { "name": "Docker Desktop", "id": "Docker.DockerDesktop", "selected": false }
      ]
    },
    "Gaming": {
      "description": "Programmi per il gaming",
      "packages": [
        { "name": "Steam", "id": "Valve.Steam", "selected": true },
        { "name": "Discord", "id": "Discord.Discord", "selected": true }
      ]
    },
    "Office": {
      "description": "Suite ufficio e collaborazione",
      "packages": [
        { "name": "Microsoft Teams", "id": "Microsoft.Teams", "selected": true },
        { "name": "OneDrive", "id": "Microsoft.OneDrive", "selected": true }
      ]
    }
  }
}
```

**Validation Rules**
- Each category must contain a non‑empty `packages` array.
- Each package must have `name` and `id` (winget ID). `selected` defaults to `false` if omitted.

---

## 6) Implementation Details

### 6.1 Admin & Execution Policy
- If not elevated, relaunch the script with `-Verb RunAs` and preserve arguments.
- Temporarily set `-ExecutionPolicy Bypass` on invocation.

### 6.2 Winget Detection & Install
- Check `Get-Command winget`. If missing, show a modal: "Installare 'App Installer' dal Microsoft Store" and exit.
- Detect installed package via `winget list --id <ID>` exact match.
- Install with `winget install --id <ID> --accept-package-agreements --accept-source-agreements -h 0`.

### 6.3 Logging & Summary
- Start transcript to `%LOCALAPPDATA%\pc-setup\logs\setup-YYYYMMDD-HHMMSS.log`.
- Maintain a run object to record per‑package status: `installed|already_present|failed`, duration, error message if any.
- At end, write `summary-YYYYMMDD-HHMMSS.json` with counts and itemized results.
- Show a WPF modal summary with counts and a button to open the log folder.

### 6.4 Remote Manifest Fallback
- Constant: `$DefaultPackagesUrl = "https://raw.githubusercontent.com/<USER>/<REPO>/main/packages.json"` (set placeholder; make configurable via `-PackagesUrl`).
- If `./packages.json` is missing: download to a temp path (or to current folder) and proceed.
- If download fails: show error dialog and exit.

### 6.5 Error Handling
- Package install failures are non‑fatal; continue.
- Fatal errors (no admin, no winget, invalid manifest) → show dialog and exit with non‑zero code.
- Use `try/catch` around each external call; record `$LASTEXITCODE` where relevant.

### 6.6 Idempotency Strategy
- Before installing a package: call `winget list --id <ID>`.
- If present: mark as `already_present` and skip.

### 6.7 CLI Parsing
- Define `[switch]$DryRun, [switch]$EnableWSL, [switch]$AutoReboot, [string]$PackagesUrl, [string]$LogDir` in `setup.ps1`.
- GUI toggles should bind to the same flags.

### 6.8 Optional Features
- **Enable WSL**: run `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart` and `VirtualMachinePlatform` when the toggle is on.
- **Auto Reboot**: if enabled and not DryRun, show a 10‑second countdown and call `Restart-Computer`.

---

## 7) Code Quality & Style
- Use a **module** (`utils.psm1`) for reusable helpers: `Ensure-Admin`, `Get-Manifest`, `Validate-Manifest`, `Start-Logging`, `Install-Package`, `Is-Installed`, `Write-Summary`.
- Prefer **Write-Host** with minimal coloring for user messages; structured data goes to summary JSON.
- Functions names: PascalCase; parameters with type annotations where sensible.
- Handle Unicode safely (UTF‑8) for JSON I/O.

---

## 8) Packaging to EXE (Optional)
- Add dev dependency: `ps2exe` (PowerShell module).
- Build command:
  ```powershell
  # inside project root
  if (-not (Get-Module -ListAvailable ps2exe)) { Install-Module ps2exe -Scope CurrentUser -Force }
  Invoke-ps2exe .\setup.ps1 .\Setup-Windows.exe -noConsole -requireAdmin -iconFile .\assets\app.ico
  ```
- Keep `.ps1` as the canonical source; `.exe` is for convenient distribution.

---

## 9) Testing Plan

**Unit-ish** (manual):
- Launch with `-DryRun` and ensure GUI selections affect the summary as expected.
- Provide a `packages.json` with 1–2 categories and a mix of selected/unselected.
- Simulate an already installed app and confirm it is skipped.
- Remove local `packages.json` and verify remote fetch path & failure dialog.

**Acceptance**:
- Fresh Windows user: select Base + Dev, deselect Docker, run → installs only selected, shows summary, logs created.

---

## 10) Tasks for Cursor (Do step‑by‑step)

1. **Scaffold the repo** exactly as in §2.1.
2. Implement `utils.psm1` with:
   - `Ensure-Admin`, `Start-Logging`, `Stop-Logging`
   - `Get-Manifest($PackagesUrl)` → local‑first, otherwise download.
   - `Validate-Manifest($manifest)` → enforce schema in §5.
   - `Is-Installed($id)` & `Install-Package($id, $DryRun)`.
   - `Write-Summary($RunState, $LogDir)` → write JSON; return counts.
3. In `setup.ps1`:
   - Parse switches/params (§3).
   - Call admin check, logging, manifest load/validate.
   - **Build WPF GUI** per §4 with expand/collapse categories and package checkboxes.
   - Bind GUI selections to an in‑memory structure to compute final package list.
   - Execute the install loop with idempotency and error capture.
   - Show summary modal with counts and a button to open the `logs/` directory.
4. Add a minimal `packages.json` sample (§5.2).
5. Generate a short **end‑user README** (separate from this brief) with: download → run → select → install.
6. Optional: add the `ps2exe` packaging script under a `build.ps1`.

---

## 11) Non‑Goals (for now)
- macOS/Linux support.
- Account login automation (2FA, credentials).
- Complex system tweaks beyond WSL/VM features.

---

## 12) Configuration Constants (placeholders to set)
- `DefaultPackagesUrl` → `https://raw.githubusercontent.com/Falker47/pc-setup/main/packages.json` (update later).
- `DefaultLogDir` → `%LOCALAPPDATA%\pc-setup\logs`.

---

## 13) Future Enhancements
- Persist last selections in a local config file to pre‑tick recent choices.
- Add search/filter in the GUI.
- Progress bar and per‑package live status.
- Category import/export presets ("Base+Dev", "Gaming only").
- YAML manifest support.

---

### End of Brief

> Build clean, modular, and resilient. Favor readability and robust UX over micro‑optimizations.

