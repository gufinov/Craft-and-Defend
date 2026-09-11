@echo off
setlocal
title Craft and Defend
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1"
if errorlevel 1 (
  echo.
  echo Craft and Defend could not start.
  echo Review the message above and artifacts\windows_export.log.
  pause
  exit /b 1
)
