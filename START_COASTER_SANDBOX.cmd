@echo off
setlocal
title Craft and Defend - Coaster Sandbox
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "SANDBOX_ROOT=%~dp0artifacts\coaster-sandbox"
mkdir "%SANDBOX_ROOT%" 2>nul
echo.
echo Starting the coaster sandbox: new game, premade loop and slope run beside the spawn,
echo infinite rails / slopes / loops / carts / kettles / blocks / tools in the pack.
echo Saves for this sandbox live in %SANDBOX_ROOT% (your normal saves are untouched).
start "" "%~dp0builds\CraftAndDefend\CraftAndDefend.exe" --log-file "%SANDBOX_ROOT%\sandbox.log" -- --f0-data-root="%SANDBOX_ROOT%" --coaster-sandbox
exit /b 0

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
pause
exit /b 1
