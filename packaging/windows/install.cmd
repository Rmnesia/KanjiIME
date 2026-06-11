@echo off
setlocal

set "SCRIPT=%~dp0install.ps1"
if not exist "%SCRIPT%" (
  echo KanjiIME setup file is missing: %SCRIPT%
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
  echo.
  echo KanjiIME setup failed. See %TEMP%\KanjiIME-Setup.log
  pause
)

exit /b %EXITCODE%
