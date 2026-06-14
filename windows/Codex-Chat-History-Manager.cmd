@echo off
cd /d "%USERPROFILE%\.codex\tools\history-manager"
set "NODE_EXE=%USERPROFILE%\.codex\tools\history-manager\runtime\node.exe"
if exist "%NODE_EXE%" (
  "%NODE_EXE%" "%USERPROFILE%\.codex\tools\history-manager\ui\server.mjs"
) else (
  node "%USERPROFILE%\.codex\tools\history-manager\ui\server.mjs"
)
if errorlevel 1 pause
