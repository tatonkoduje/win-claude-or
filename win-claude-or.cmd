@echo off
setlocal
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0win-claude-or.ps1" %*
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0win-claude-or.ps1" %*
)
exit /b %ERRORLEVEL%
