@echo off
setlocal
set "PSModulePath="
cd /d "%~dp0"
title Ultimate AI Starter Bundle v8.7.9
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-AIO.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo [ERROR] Installation failed with exit code %EXITCODE%.
  echo [ERROR] Durable diagnostics were written to:
  echo         "%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\INSTALL-FAILED.txt"
  echo         "%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\INSTALL-LAST.log"
  if /I not "%UABS_NO_PAUSE%"=="1" pause
) else (
  echo [OK] Installation complete.
  echo [OK] Review the NEXT STEPS above before closing this window.
  if /I not "%UABS_NO_PAUSE%"=="1" pause
)
exit /b %EXITCODE%
