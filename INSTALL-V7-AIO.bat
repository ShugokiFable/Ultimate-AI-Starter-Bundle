@echo off
setlocal
cd /d "%~dp0"
title Ultimate AI Starter Bundle v7.9.0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-V7-AIO.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" echo Installation failed with exit code %EXITCODE%.
exit /b %EXITCODE%
