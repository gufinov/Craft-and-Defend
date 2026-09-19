@echo off
setlocal
title Craft and Defend - P3D Tools and World Feedback Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-p3d-usability-%RANDOM%%RANDOM%"
set "PHASE_ROOT=%TEST_ROOT%\phase1"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%PHASE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running atomic 5x crafting, held-item, axe, placement and iron discovery checks.
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%PHASE_ROOT%\phase1.log" -- --f0-data-root="%PHASE_ROOT%" --p3d-usability-automation=phase1
if errorlevel 1 goto :phase_failed

echo.
echo Rendering the held axe, iron marker and block placement ghost.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p3d-usability-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p3d-held-axe-iron-marker.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3d-held-block-placement-ghost.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3j-drag-build-ghost.png" goto :image_missing
if /i "%P3D_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P3D USABILITY TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p3d-held-axe-iron-marker.png"
start "" "%VISUAL_ROOT%\p3d-held-block-placement-ghost.png"
start "" "%VISUAL_ROOT%\p3j-drag-build-ghost.png"
echo.
echo P3D USABILITY TEST: PASS
echo The three rendered evidence images are opening now.
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
echo P3D gameplay automation failed. Review: %PHASE_ROOT%\phase1.log
pause
exit /b 1

:visual_failed
echo.
echo P3D visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing both expected screenshots.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
