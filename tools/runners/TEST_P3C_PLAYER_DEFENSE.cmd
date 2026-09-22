@echo off
setlocal
title Craft and Defend - P3C Player Defense Test
rem Runners live in tools\runners; ROOT is the repository root two levels up.
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI\"
cd /d "%ROOT%"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%ROOT%artifacts\manual-p3c-player-defense-%RANDOM%%RANDOM%"
set "PHASE_ROOT=%TEST_ROOT%\phase1"
set "PERSIST_ROOT=%TEST_ROOT%\persistence"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%ROOT%builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%PHASE_ROOT%" 2>nul
mkdir "%PERSIST_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Running the automated sword, ballista, catapult, catalog, paging and save checks.
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%PHASE_ROOT%\phase1.log" -- --f0-data-root="%PHASE_ROOT%" --p3c-player-defense-automation=phase1
if errorlevel 1 goto :phase_failed

echo.
echo Saving siege state, then restoring it in a separate executable process.
"%EXE%" --headless --log-file "%PERSIST_ROOT%\save.log" -- --f0-data-root="%PERSIST_ROOT%" --p3c-player-defense-automation=save
if errorlevel 1 goto :save_failed
"%EXE%" --headless --log-file "%PERSIST_ROOT%\restore.log" -- --f0-data-root="%PERSIST_ROOT%" --p3c-player-defense-automation=restore
if errorlevel 1 goto :restore_failed

echo.
echo Rendering the 12-card Workbench page. A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --p3c-player-defense-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\p3c-visual-catalog.png" goto :image_missing
if /i "%P3C_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo P3C PLAYER DEFENSE TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\p3c-visual-catalog.png"
echo.
echo P3C PLAYER DEFENSE TEST: PASS
echo The rendered recipe-book evidence is opening now.
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
echo P3C gameplay automation failed. Review: %PHASE_ROOT%\phase1.log
pause
exit /b 1

:save_failed
echo.
echo P3C persistence save failed. Review: %PERSIST_ROOT%\save.log
pause
exit /b 1

:restore_failed
echo.
echo P3C clean-process Continue failed. Review: %PERSIST_ROOT%\restore.log
pause
exit /b 1

:visual_failed
echo.
echo P3C visual automation failed. Review: %VISUAL_ROOT%\visual.log
pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing its expected screenshot.
echo Expected: %VISUAL_ROOT%\p3c-visual-catalog.png
pause
exit /b 1
