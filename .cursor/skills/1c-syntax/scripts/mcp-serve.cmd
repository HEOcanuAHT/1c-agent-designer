@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mcp-serve.ps1"
exit /b %ERRORLEVEL%
