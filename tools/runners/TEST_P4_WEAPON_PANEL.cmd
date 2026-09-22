@echo off
setlocal
title Craft and Defend - P4 Weapon Panel Test
rem Runners live in tools\runners; ROOT is the repository root two levels up.
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI\"
cd /d "%ROOT%"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%ROOT%artifacts\manual-p4-weapon-panel-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\phase1"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%ROOT%builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running the siege weapon panel and Chest panel checks (load, unload, stance, filter, supply, deposit, withdraw).
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p4-weapon-panel-automation=gate
if errorlevel 1 goto :phase_failed

echo.
echo Rendering the weapon panel and the Chest panel with real mouse clicks.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p4-weapon-panel-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p4-weapon-panel.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p4-chest-panel.png" goto :image_missing
if /i "%P4_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P4 WEAPON PANEL TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p4-weapon-panel.png"
start "" "%VISUAL_ROOT%\p4-chest-panel.png"
echo.
echo P4 WEAPON PANEL TEST: PASS
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
echo P4 weapon panel gate automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo P4 weapon panel visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing both expected screenshots.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
