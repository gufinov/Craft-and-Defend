@echo off
setlocal
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
