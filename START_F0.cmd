@echo off
setlocal
title Craft and Defend F0
set "APP=%~dp0builds\CraftAndDefend\CraftAndDefend.exe"
if exist "%APP%" (
  start "Craft and Defend" "%APP%"
  exit /b 0
)

set "GODOT="
for %%D in ("%~dp0.." "%~dp0..\.." "%~dp0..\..\..") do if exist "%%~fD\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe" set "GODOT=%%~fD\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe"
if exist "%GODOT%" (
  start "Craft and Defend" "%GODOT%" --path "%~dp0game"
  exit /b 0
)

echo Craft and Defend could not start.
echo Build the portable executable with BUILD_WINDOWS_F0.cmd or install the pinned Godot/Voxel Tools pair documented in docs\WINDOWS_SETUP.md.
pause
exit /b 1
