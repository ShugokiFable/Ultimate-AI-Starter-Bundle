@echo off
setlocal
cd /d "%~dp0"
title Ultimate AI Starter Bundle v7.9.7
call "%~dp0START-HERE.bat" %*
exit /b %ERRORLEVEL%
