@echo off
setlocal

set "PROJECT_ROOT=%~dp0.."
set "LAUNCHER=%PROJECT_ROOT%\scripts\run-godot.ps1"

if not exist "%LAUNCHER%" (
    echo Launch script not found: "%LAUNCHER%"
    pause
    exit /b 1
)

start "Adaptive Social Immersive Sim - GPU" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LAUNCHER%" -Gpu
exit /b 0
