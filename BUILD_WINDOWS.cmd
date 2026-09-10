@echo off
setlocal
title Craft and Defend - Build Windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_windows_f0.ps1"
if errorlevel 1 (
  echo.
  echo Build failed. Review artifacts\windows_export.log and the message above.
  pause
  exit /b 1
)
echo.
echo Build complete: builds\CraftAndDefend\CraftAndDefend.exe
pause
