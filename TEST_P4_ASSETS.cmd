@echo off
setlocal
title Craft and Defend - P4 Core and Lights Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-p4-assets-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\phase1"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running the core and light checks (asset attributes, placement, lights).
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p4-assets-automation=gate
if errorlevel 1 goto :phase_failed

echo.
echo Rendering both cores, the campfire, the lanterns, the torch and the light blocks at sunset.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p4-assets-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p4-assets.png" goto :image_missing
if /i "%P4_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P4 CORE AND LIGHTS TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p4-assets.png"
echo.
echo P4 CORE AND LIGHTS TEST: PASS
echo The rendered evidence image is opening now.
echo Evidence folder: %TEST_ROOT%
pause
exit /b 0

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
pause
exit /b 1

:phase_failed
echo.
echo P4 core and lights gate automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo P4 core and lights visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing the expected screenshot.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
