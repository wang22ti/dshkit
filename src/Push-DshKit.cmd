@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-DshKit.ps1" -Action Push %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo Push failed with exit code %RC%. Close DSH completely and retry.
  pause >nul
) else (
  echo.
  echo Pushed to DshKit. Wait for OneDrive to finish before switching machines.
  timeout /t 5 >nul
)
endlocal
