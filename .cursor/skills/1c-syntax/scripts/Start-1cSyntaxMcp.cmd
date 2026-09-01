@echo off
setlocal
set "SCRIPT=%~dp0Start-1cSyntaxMcp.ps1"
if not exist "%SCRIPT%" if defined PLUGIN_ROOT set "SCRIPT=%PLUGIN_ROOT%\.cursor\skills\1c-syntax\scripts\Start-1cSyntaxMcp.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%
