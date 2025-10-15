@echo off
setlocal

set POW=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe

echo Checking ps2exe module...
%POW% -NoProfile -ExecutionPolicy Bypass -Command "try { Set-PSRepository PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { }; if (-not (Get-Module -ListAvailable ps2exe)) { Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber }"
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

