@echo off
setlocal
cd /d "%~dp0"
set "ROOT=%~dp0"
set "EXE=%ROOT%builds\CraftAndDefend\CraftAndDefend.exe"
set "MODE=%~1"
if "%MODE%"=="" set "MODE=play"
if /i "%MODE%"=="play" goto :play
if /i "%MODE%"=="sandbox" goto :sandbox
if /i "%MODE%"=="coastercraft" goto :coastercraft
if /i "%MODE%"=="dev" goto :dev
if /i "%MODE%"=="build" goto :build
if /i "%MODE%"=="stop" goto :stop
if /i "%MODE%"=="help" goto :help
if /i "%MODE%"=="/?" goto :help
if /i "%MODE%"=="-h" goto :help
if /i "%MODE%"=="--help" goto :help
echo Unknown option: %MODE%
echo.
goto :help

:help
echo START.cmd - Craft and Defend launcher
echo.
echo   START.cmd               Prepare the provenance-matched export and play (main menu:
echo                           the real game and CoasterCraft).
echo   START.cmd sandbox       Coaster sandbox: CoasterCraft plus the premade demo tracks,
echo                           infinite pack. Data root artifacts\coaster-sandbox.
echo   START.cmd coastercraft  Straight into CoasterCraft New (bare plate, no monsters).
echo                           Data root artifacts\coastercraft.
echo   START.cmd dev           Straight into the Development Expo (its own save, no ambient raids).
echo                           Data root artifacts\development.
echo   START.cmd build         Rebuild the Windows export (builds\CraftAndDefend) now.
echo   START.cmd stop          Close every running Craft and Defend game window.
echo   START.cmd help          This text.
echo.
echo Test runners live in tools\runners (RUN_ALL.cmd runs every suite).
exit /b 0

:play
title Craft and Defend
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start_game.ps1"
if errorlevel 1 (
  echo.
  echo Craft and Defend could not start.
  echo Review the message above and artifacts\windows_export.log.
  pause
  exit /b 1
)
exit /b 0

:sandbox
title Craft and Defend - Coaster Sandbox
call :prepare
if errorlevel 1 goto :prepare_failed
set "SANDBOX_ROOT=%ROOT%artifacts\coaster-sandbox"
mkdir "%SANDBOX_ROOT%" 2>nul
echo.
echo Starting the coaster sandbox: CoasterCraft mode (bare plate) plus the premade demo tracks,
echo infinite rails / slopes / loops / carts / kettles / blocks / tools in the pack.
echo Saves for this sandbox live in %SANDBOX_ROOT%\coastercraft (your normal saves are untouched).
start "" "%EXE%" --log-file "%SANDBOX_ROOT%\sandbox.log" -- --f0-data-root="%SANDBOX_ROOT%" --coaster-sandbox
exit /b 0

:coastercraft
title Craft and Defend - CoasterCraft
call :prepare
if errorlevel 1 goto :prepare_failed
set "CC_ROOT=%ROOT%artifacts\coastercraft"
mkdir "%CC_ROOT%" 2>nul
echo.
echo Starting CoasterCraft: a new bare 60 x 100 stone plate, infinite rails / slopes / loops /
echo switches / crossings / curves / climbs / carts / cars / kettles / blocks / tools, no monsters.
echo Escape opens its own pause menu (Save, Save and Restart, Save and Exit to Menu, Save and Quit).
echo Saves for this mode live in %CC_ROOT%\coastercraft (your normal saves are untouched).
start "" "%EXE%" --log-file "%CC_ROOT%\coastercraft.log" -- --f0-data-root="%CC_ROOT%" --coastercraft
exit /b 0

:dev
title Craft and Defend - Development Expo
call :prepare
if errorlevel 1 goto :prepare_failed
set "DEV_ROOT=%ROOT%artifacts\development"
mkdir "%DEV_ROOT%" 2>nul
echo.
echo Starting the Development Expo: the owner's development world - the real game rules on its
echo own save, with no ambient raids. Continue resumes it; the first run builds it.
echo Escape opens its own pause menu (Save, Reset Expo, Save and Exit to Menu, Save and Quit).
echo Saves for this mode live in %DEV_ROOT%\development (your normal saves are untouched).
start "" "%EXE%" --log-file "%DEV_ROOT%\development.log" -- --f0-data-root="%DEV_ROOT%" --development
exit /b 0

:build
title Craft and Defend - Build Windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\build_windows_f0.ps1"
if errorlevel 1 (
  echo.
  echo Build failed. Review artifacts\windows_export.log and the message above.
  pause
  exit /b 1
)
echo.
echo Build complete: builds\CraftAndDefend\CraftAndDefend.exe
pause
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

:prepare
echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start_game.ps1" -PrepareOnly
exit /b %errorlevel%

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
pause
exit /b 1
