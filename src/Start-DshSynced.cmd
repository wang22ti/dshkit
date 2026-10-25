@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DshSynced.ps1" %*
if errorlevel 1 (
  echo.
  echo DSH sync launcher failed. Check %LOCALAPPDATA%\DshKit\managed-launch-last.log
  pause >nul
)
endlocal
