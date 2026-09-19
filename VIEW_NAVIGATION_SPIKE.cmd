@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_game.ps1" -PrepareOnly
if errorlevel 1 (
    echo.
    echo Craft and Defend could not prepare the navigation diagnostic.
    pause
    exit /b 1
)

set "DIAGNOSTIC_ROOT=%~dp0artifacts\manual-p2-navigation"
set "DIAGNOSTIC_IMAGE=%DIAGNOSTIC_ROOT%\p2-navigation-spike.png"
set "DIAGNOSTIC_LOG=%DIAGNOSTIC_ROOT%\p2-navigation-spike.log"

if not exist "%DIAGNOSTIC_ROOT%" mkdir "%DIAGNOSTIC_ROOT%"
"%~dp0builds\CraftAndDefend\CraftAndDefend.exe" --log-file "%DIAGNOSTIC_LOG%" -- --f0-data-root="%DIAGNOSTIC_ROOT%" --p2-navigation-automation=visual
if errorlevel 1 (
    echo.
    echo The navigation diagnostic failed.
    echo Review: %DIAGNOSTIC_LOG%
    pause
    exit /b 1
)

if not exist "%DIAGNOSTIC_IMAGE%" (
    echo.
    echo The navigation diagnostic exited without creating its evidence image.
    echo Expected: %DIAGNOSTIC_IMAGE%
    echo Review: %DIAGNOSTIC_LOG%
    pause
    exit /b 1
)

if /i "%P2_DIAGNOSTIC_NO_OPEN%"=="1" (
    echo Navigation diagnostic passed. Evidence: %DIAGNOSTIC_IMAGE%
    exit /b 0
)

start "" "%DIAGNOSTIC_IMAGE%"
echo Navigation diagnostic passed. The rendered evidence image is opening now.
pause
