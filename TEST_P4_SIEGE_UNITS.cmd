@echo off
setlocal
title Craft and Defend - P4 Siege Units Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-p4-siege-units-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\phase1"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running the siege unit checks (content, cannon, turret catapult, rail kettle, ballista presentation, wave drill).
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p4-siege-units-automation=gate
if errorlevel 1 goto :phase_failed

echo.
echo Checkpointing a running wave, then restoring it in a clean process (T141).
"%EXE%" --headless --log-file "%GATE_ROOT%\save.log" -- --f0-data-root="%GATE_ROOT%" --p4-siege-units-automation=save
if errorlevel 1 goto :phase_failed
"%EXE%" --headless --log-file "%GATE_ROOT%\restore.log" -- --f0-data-root="%GATE_ROOT%" --p4-siege-units-automation=restore
if errorlevel 1 goto :phase_failed

echo.
echo Rendering the five siege machines in one view.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p4-siege-units-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p4-siege-units.png" goto :image_missing
if /i "%P4_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P4 SIEGE UNITS TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p4-siege-units.png"
echo.
echo P4 SIEGE UNITS TEST: PASS
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
echo P4 siege units gate automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo P4 siege units visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing the expected screenshot.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
