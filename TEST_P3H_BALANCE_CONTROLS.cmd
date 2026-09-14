@echo off
setlocal
title Craft and Defend - P3H Balance and Controls Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-p3h-balance-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\gate"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running balance-catalogue, counted-fuel, save/restore and W/R rotation checks.
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p3h-balance-controls-automation=gate
if errorlevel 1 goto :gate_failed

echo.
echo Rendering the Furnace fuel ratio and directional Keybinds screen.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p3h-balance-controls-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p3h-furnace-fuel-ratio.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3h-directional-controls.png" goto :image_missing
if /i "%P3H_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P3H BALANCE AND CONTROLS TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p3h-furnace-fuel-ratio.png"
start "" "%VISUAL_ROOT%\p3h-directional-controls.png"
echo.
echo P3H BALANCE AND CONTROLS TEST: PASS
echo The two rendered evidence images are opening now.
echo Evidence folder: %TEST_ROOT%
pause
exit /b 0

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
pause
exit /b 1

:gate_failed
echo.
echo P3H balance and controls automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo P3H balance and controls visual failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing both expected screenshots.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
