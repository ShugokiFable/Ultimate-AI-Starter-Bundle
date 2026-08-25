@echo off
setlocal
cd /d "%~dp0"
title Ultimate AI Starter Bundle v8.0.4
call "%~dp0START-HERE.bat" %*
exit /b %ERRORLEVEL%
