@echo off
setlocal
title Craft and Defend - P3K Blueprint Test
rem Runners live in tools\runners; ROOT is the repository root two levels up.
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI\"
cd /d "%ROOT%"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%ROOT%artifacts\manual-p3k-blueprints-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\phase1"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%ROOT%builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running blueprint catalogue, tower stacking, trimming, blocking and cancel checks.
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p3k-blueprint-automation=gate
if errorlevel 1 goto :phase_failed

echo.
echo Rendering a stamped foundation + segment + cap tower and a blueprint ghost.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p3k-blueprint-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p3k-stamped-tower.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3k-blueprint-ghost.png" goto :image_missing
if /i "%P3K_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P3K BLUEPRINT TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p3k-stamped-tower.png"
start "" "%VISUAL_ROOT%\p3k-blueprint-ghost.png"
echo.
echo P3K BLUEPRINT TEST: PASS
echo The two rendered evidence images are opening now.
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
echo P3D gameplay automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo P3K visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing both expected screenshots.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
