@echo off
title Ultimate AI Starter Bundle - Remote Installer
echo.
echo  Ultimate AI Starter Bundle Remote Installer
echo  ============================================
echo  This downloads the latest release from GitHub and
echo  runs the full installer (skills, tools, MCP, gates,
echo  SOUL + AIO preamble for every agent).
echo.
echo  Press Ctrl+C to cancel.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1 | iex"
echo.
echo Exit code: %ERRORLEVEL%
pause