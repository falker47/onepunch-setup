@echo off
setlocal

set POW=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe

echo Checking ps2exe module...
%POW% -NoProfile -ExecutionPolicy Bypass -Command "if (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue) { exit 0 } else { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -Scope CurrentUser -ErrorAction Stop }; if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Default -ErrorAction SilentlyContinue }; Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue; Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber -Confirm:$false -ErrorAction Stop; exit 0 } catch { exit 1 } }"
if errorlevel 1 (
  echo Failed to prepare ps2exe. Press a key to exit.
  pause >nul
  exit /b 1
)

echo Compiling onepunch-setup.exe ...
if exist "%~dp0assets\icon.ico" (
  %POW% -NoProfile -ExecutionPolicy Bypass -Command "Invoke-ps2exe .\assets\setup.ps1 .\onepunch-setup.exe -noConsole -requireAdmin -iconFile .\assets\icon.ico"
) else (
  %POW% -NoProfile -ExecutionPolicy Bypass -Command "Invoke-ps2exe .\assets\setup.ps1 .\onepunch-setup.exe -noConsole -requireAdmin"
)
if errorlevel 1 (
  echo Compilation failed. Press a key to exit.
  pause >nul
  exit /b 1
)

echo Launching onepunch-setup.exe as Administrator ...
%POW% -NoProfile -ExecutionPolicy Bypass -Command "Start-Process \"%~dp0onepunch-setup.exe\" -Verb RunAs"

endlocal

