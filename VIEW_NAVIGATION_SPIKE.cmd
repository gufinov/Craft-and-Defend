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

if not exist "%~dp0artifacts\manual-p2-navigation" mkdir "%~dp0artifacts\manual-p2-navigation"
"%~dp0builds\CraftAndDefend\CraftAndDefend.exe" --f0-data-root="%~dp0artifacts\manual-p2-navigation" --p2-navigation-automation=visual
if errorlevel 1 (
    echo.
    echo The navigation diagnostic failed. Review the console output above.
    pause
    exit /b 1
)

start "" "%~dp0artifacts\manual-p2-navigation\p2-navigation-spike.png"
echo Navigation diagnostic passed. The rendered evidence image is opening now.
pause
