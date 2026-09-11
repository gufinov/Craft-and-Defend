@echo off
setlocal
title Craft and Defend
cd /d "%~dp0"
if not exist "CraftAndDefend.exe" (
  echo CraftAndDefend.exe is missing from this portable folder.
  echo Keep START_GAME.cmd, CraftAndDefend.exe and CraftAndDefend.pck together.
  pause
  exit /b 1
)
if not exist "CraftAndDefend.pck" (
  echo CraftAndDefend.pck is missing from this portable folder.
  echo Keep START_GAME.cmd, CraftAndDefend.exe and CraftAndDefend.pck together.
  pause
  exit /b 1
)
start "" "%~dp0CraftAndDefend.exe"
