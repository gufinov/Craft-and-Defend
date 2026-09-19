@echo off
setlocal
title Craft and Defend - P4b Resource Distribution Test
cd /d "%~dp0"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%~dp0artifacts\manual-p4-resources-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\gate"
set "EXE=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul

echo.
echo Running ore depth-band, P1 layout preservation, gold mining and gold smelting checks (T137-T140).
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --p4-resources-automation=gate
if errorlevel 1 goto :phase_failed

echo.
echo P4B RESOURCE DISTRIBUTION TEST: PASS
echo Evidence folder: %TEST_ROOT%
if /i "%P4_DIAGNOSTIC_NO_PAUSE%"=="1" exit /b 0
pause
exit /b 0

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
pause
exit /b 1

:phase_failed
echo.
echo P4b resource automation failed. Review: %GATE_ROOT%\gate.log
pause
exit /b 1
