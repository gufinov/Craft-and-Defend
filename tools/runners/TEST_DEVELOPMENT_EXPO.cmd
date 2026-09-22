@echo off
setlocal
title Craft and Defend - Development Expo Test
rem Runners live in tools\runners; ROOT is the repository root two levels up.
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI\"
cd /d "%ROOT%"

echo Preparing the current exported game...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start_game.ps1" -PrepareOnly
if errorlevel 1 goto :prepare_failed

set "TEST_ROOT=%ROOT%artifacts\manual-development-expo-%RANDOM%%RANDOM%"
set "GATE_ROOT=%TEST_ROOT%\gate"
set "VISUAL_ROOT=%TEST_ROOT%\visual"
set "EXE=%ROOT%builds\CraftAndDefend\CraftAndDefend.exe"
mkdir "%GATE_ROOT%" 2>nul
mkdir "%VISUAL_ROOT%" 2>nul

echo.
echo Building the canonical Development Expo and checking its layout, campus,
echo signs and generated Supply Depot (T213, T214, T215, T223).
echo The diagnostic controls itself; it is not the playable game.
"%EXE%" --headless --log-file "%GATE_ROOT%\gate.log" -- --f0-data-root="%GATE_ROOT%" --development-expo-automation=gate
if errorlevel 1 goto :gate_failed

echo.
echo Rendering the plaza, a campus sign, a Supply Depot chest with its board
echo and the lit mountain tunnel.
echo A game window may appear briefly and close itself.
"%EXE%" --log-file "%VISUAL_ROOT%\visual.log" -- --f0-data-root="%VISUAL_ROOT%" --development-expo-automation=visual
if errorlevel 1 goto :visual_failed

if not exist "%VISUAL_ROOT%\development-expo-plaza.png" goto :image_missing
if not exist "%VISUAL_ROOT%\development-expo-sign.png" goto :image_missing
if not exist "%VISUAL_ROOT%\development-expo-supply.png" goto :image_missing
if not exist "%VISUAL_ROOT%\development-expo-tunnel.png" goto :image_missing
if /i "%EXPO_DIAGNOSTIC_NO_OPEN%"=="1" (
  echo DEVELOPMENT EXPO TEST: PASS
  echo Evidence folder: %TEST_ROOT%
  exit /b 0
)
start "" "%VISUAL_ROOT%\development-expo-supply.png"
start "" "%VISUAL_ROOT%\development-expo-plaza.png"
echo.
echo DEVELOPMENT EXPO TEST: PASS
echo The rendered evidence images are opening now.
echo Evidence folder: %TEST_ROOT%
if /i not "%EXPO_DIAGNOSTIC_NO_PAUSE%"=="1" pause
exit /b 0

:prepare_failed
echo.
echo The current game could not be prepared. Review artifacts\windows_export.log.
echo DEVELOPMENT EXPO TEST: FAIL
if /i not "%EXPO_DIAGNOSTIC_NO_PAUSE%"=="1" pause
exit /b 1

:gate_failed
echo.
echo Development Expo automation failed. Review: %GATE_ROOT%\gate.log
echo DEVELOPMENT EXPO TEST: FAIL
if /i not "%EXPO_DIAGNOSTIC_NO_PAUSE%"=="1" pause
exit /b 1

:visual_failed
echo.
echo Development Expo visual automation failed. Review: %VISUAL_ROOT%\visual.log
echo DEVELOPMENT EXPO TEST: FAIL
if /i not "%EXPO_DIAGNOSTIC_NO_PAUSE%"=="1" pause
exit /b 1

:image_missing
echo.
echo The visual test passed without producing all four expected screenshots.
echo Expected folder: %VISUAL_ROOT%
echo DEVELOPMENT EXPO TEST: FAIL
if /i not "%EXPO_DIAGNOSTIC_NO_PAUSE%"=="1" pause
exit /b 1
