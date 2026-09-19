@echo off
setlocal
title Craft and Defend - Coaster Rails Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-coaster-rails-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\phase1"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running the coaster rail checks (slope chains, the loop drag tool, the mine cart ride).
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --coaster-rails-automation=gate
if errorlevel 1 goto :phase_failed

echo.
echo Rendering a loop with a cart on it beside a slope run.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --coaster-rails-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\coaster-rails.png" goto :image_missing
if /i "%P4_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo COASTER RAILS TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\coaster-rails.png"
echo.
echo COASTER RAILS TEST: PASS
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
echo Coaster rails gate automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo Coaster rails visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing the expected screenshot.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
