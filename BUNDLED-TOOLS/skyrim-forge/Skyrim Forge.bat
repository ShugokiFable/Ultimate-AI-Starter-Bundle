@echo off
setlocal
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" (echo Forge is not installed. Run START-HERE.bat.& exit /b 1)
"%PY%" -m skyrim_forge %*
