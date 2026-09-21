@echo off
setlocal
title Craft and Defend - CoasterCraft
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "CC_ROOT=%~dp0artifacts\coastercraft"
mkdir "%CC_ROOT%" 2>nul
echo.
echo Starting CoasterCraft: a new bare 60 x 100 stone plate, infinite rails / slopes / loops /
echo switches / crossings / curves / climbs / carts / cars / kettles / blocks / tools, no monsters.
echo Escape opens its own pause menu (Save, Save and Restart, Save and Exit to Menu, Save and Quit).
echo Saves for this mode live in %CC_ROOT%\coastercraft (your normal saves are untouched).
start "" "%~dp0builds\CraftAndDefend\CraftAndDefend.exe" --log-file "%CC_ROOT%\coastercraft.log" -- --f0-data-root="%CC_ROOT%" --coastercraft
exit /b 0

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
pause
exit /b 1
