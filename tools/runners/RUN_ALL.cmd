@echo off
setlocal
title Craft and Defend - Run All Test Runners
rem Runs every TEST_*.cmd in this folder in name order and prints a PASS/FAIL table.
rem Optional arguments: runner names to limit the sweep, e.g. RUN_ALL.cmd TEST_COASTER_RAILS TEST_P4_RESOURCES
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_all.ps1" %*
set "RESULT=%errorlevel%"
if not "%RESULT%"=="0" (
  echo.
  echo RUN ALL: at least one runner FAILED. Review the logs folder printed above.
)
if /i not "%P4_DIAGNOSTIC_NO_PAUSE%"=="1" pause
exit /b %RESULT%
