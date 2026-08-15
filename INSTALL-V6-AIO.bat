@echo off
title Skyrim AI V5 AIO Installer
cd /d "%~dp0"
echo.
echo  Skyrim AI V5 ? All-In-One Installer
echo  ==================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-V6-AIO.ps1" %*
echo.
echo Exit code: %ERRORLEVEL%
pause
