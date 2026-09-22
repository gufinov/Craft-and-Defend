@echo off
setlocal
title Craft and Defend
cd /d "%~dp0"
if /i "%~1"=="stop" goto :stop
if /i "%~1"=="help" goto :help
if not exist "CraftAndDefend.exe" (
  echo CraftAndDefend.exe is missing from this portable folder.
  echo Keep START.cmd, CraftAndDefend.exe and CraftAndDefend.pck together.
  pause
  exit /b 1
)
if not exist "CraftAndDefend.pck" (
  echo CraftAndDefend.pck is missing from this portable folder.
  echo Keep START.cmd, CraftAndDefend.exe and CraftAndDefend.pck together.
  pause
  exit /b 1
)
start "" "%~dp0CraftAndDefend.exe" %*
exit /b 0

:help
echo START.cmd        Play Craft and Defend (extra arguments go to the game).
echo START.cmd stop   Close every running Craft and Defend game window.
exit /b 0

:stop
title Craft and Defend - Stop
echo Closing every running Craft and Defend game window...
taskkill /IM CraftAndDefend.exe /F >nul 2>&1
if errorlevel 1 (
  echo No running game found.
) else (
  echo Game closed.
)
timeout /t 2 >nul
exit /b 0
