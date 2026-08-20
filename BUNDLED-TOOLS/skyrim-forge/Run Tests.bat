@echo off
setlocal
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=python"
cd /d "%~dp0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell-Parse-Gate.ps1" || goto fail
"%PY%" -m compileall -q skyrim_forge tests scripts || goto fail
"%PY%" -m unittest discover -s tests -v || goto fail
"%PY%" -m skyrim_forge self-test || goto fail
"%~dp0writer\published\win-x64\SkyrimForge.Native.exe" version || goto fail
"%~dp0writer\published\win-x64\SkyrimForge.Native.exe" self-test || goto fail
echo ALL TESTS PASSED.
pause
exit /b 0
:fail
echo TESTS FAILED.
pause
exit /b 1
