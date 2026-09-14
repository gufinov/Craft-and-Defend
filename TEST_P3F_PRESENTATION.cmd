@echo off
setlocal
title Craft and Defend - P3F Presentation Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-p3f-presentation-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\gate"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running recipe progression, true-alpha catalog, held-scale, swing and block texture checks.
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p3f-presentation-automation=gate
if errorlevel 1 goto :gate_failed

echo.
echo Rendering eight held-item views plus both Workbench recipe pages.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p3f-presentation-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p3f-held-item-contact-sheet.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3f-workbench-page-1.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3f-workbench-page-2.png" goto :image_missing
if not exist "%VISUAL_ROOT%\p3h2-held-scale-and-swing.png" goto :image_missing
if /i "%P3F_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P3F PRESENTATION TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p3f-held-item-contact-sheet.png"
start "" "%VISUAL_ROOT%\p3f-workbench-page-1.png"
start "" "%VISUAL_ROOT%\p3f-workbench-page-2.png"
start "" "%VISUAL_ROOT%\p3h2-held-scale-and-swing.png"
echo.
echo P3F PRESENTATION TEST: PASS
echo The held-item contact sheet, scale/swing comparison and both Workbench pages are opening now.
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
echo P3F gate automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1

:visual_failed
echo.
echo P3F visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing all three expected screenshots.
echo Expected folder: %VISUAL_ROOT%
pause
exit /b 1
