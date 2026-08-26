@echo off
setlocal EnableExtensions
title Skyrim Forge 6.0.0
set "FORGE_PS_GATE=%~dp0PowerShell-Parse-Gate.ps1"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%FORGE_PS_GATE%"
if errorlevel 1 (
  echo.
  echo PowerShell validation failed. Forge will not continue.
  pause
  exit /b 1
)
if /I "%~1"=="--validate-only" exit /b 0
if /I "%~1"=="--menu" goto menu
if not "%~1"=="" goto menu

rem No arguments: do the thing almost everyone who opens this file came to do.
rem This landed on an eleven-item menu whose correct answer was "1" for anyone
rem who had not used Forge before -- and the bundle installer never shows this
rem menu at all, so the only person who ever saw it was a first-timer opening
rem the Forge folder directly. The other ten entries are one keypress away
rem (--menu, or M when this finishes). Install-AI-Bridge installs OR updates
rem and then reconnects every detected AI app, so re-running this is also how
rem you update.
goto autoinstall

:autoinstall
cls
echo.
echo ================================================================
echo  SKYRIM FORGE 6.0.0 - VERIFIED TOOLCHAIN FABRIC
echo ================================================================
echo.
echo  Installing Forge and connecting every detected AI app.
echo  This installs or updates, so it is safe to run again.
echo.
echo  More options:  START-HERE.bat --menu   (or press M at the end)
echo ================================================================
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-AI-Bridge.ps1" -BootstrapPython -Yes
set "BRIDGE_EXIT=%ERRORLEVEL%"
echo.
if not "%BRIDGE_EXIT%"=="0" (
  echo ================================================================
  echo  SETUP FAILED - exit code %BRIDGE_EXIT%
  echo ================================================================
  echo  Read the error above. Two things worth trying:
  echo    * option 2 in the menu, to set your core paths
  echo    * option 4 in the menu, to run the full doctor
  echo.
  choice /C MX /N /M "Press M for the menu, X to exit: "
  if errorlevel 2 exit /b %BRIDGE_EXIT%
  goto menu
)
echo ================================================================
echo  READY - Forge is installed and every detected AI app is wired.
echo ================================================================
echo.
echo  Just talk to your AI app about your mod. It can drive Forge now.
echo.
echo  Optional, only if you want them:
echo    * option 2  set core paths (game, mods, output)
echo    * option 3  point Forge at xEdit, MO2, CK, LOOT, Wrye, Papyrus
echo    * option 8  open the Forge GUI
echo.
choice /C MX /N /M "Press M for more options, X to finish: "
if errorlevel 2 exit /b 0
goto menu

:menu
cls
echo.
echo ================================================================
echo  SKYRIM FORGE 6.0.0 - VERIFIED TOOLCHAIN FABRIC
echo ================================================================
echo.
echo  1. Install/update Forge and connect all detected AI apps
echo  2. Configure core paths
echo  3. Configure xEdit, MO2, CK, LOOT, Wrye and Papyrus
echo  4. Run full doctor
echo  5. Install Forge skill for AI applications
echo  6. Register MCP with AI applications
echo  7. Install or repair Forge xEdit scripts
echo  8. Open Forge GUI
echo  9. Run regression tests
echo  T. Scan/import verified local tools
echo  D. Open documentation
echo  0. Exit
echo.
choice /C 123456789TD0 /N /M "Choose: "
if errorlevel 12 exit /b 0
if errorlevel 11 start "" "%~dp0README.md"&goto menu
if errorlevel 10 powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-Toolchain.ps1"&pause&goto menu
if errorlevel 9 call "%~dp0Run Tests.bat"&goto menu
if errorlevel 8 call "%~dp0Skyrim Forge GUI.bat"&goto menu
if errorlevel 7 call "%~dp0Skyrim Forge.bat" automation-run "%~dp0examples\automation-install-xedit-scripts.job.json" --approve&pause&goto menu
if errorlevel 6 powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-MCP.ps1"&pause&goto menu
if errorlevel 5 powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Forge-Skill.ps1"&pause&goto menu
if errorlevel 4 call "%~dp0Forge Doctor.bat"&goto menu
if errorlevel 3 powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-Automation.ps1"&pause&goto menu
if errorlevel 2 powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-Forge.ps1"&pause&goto menu
if errorlevel 1 goto install
:install
set "SCRIPT=%~dp0Install-AI-Bridge.ps1"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -BootstrapPython -Yes
pause
goto menu
