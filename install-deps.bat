@echo off
:: ============================================================
::  NEXUS OS — One-Click Dependency Installer (Windows + WSL)
::  Double-click or run in cmd
:: ============================================================

title Nexus OS — Dependency Installer

echo.
echo   NEXUS OS — Windows Setup (WSL)
echo   ================================
echo.

:: Check if WSL is installed
wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] WSL not installed!
    echo.
    echo   Install WSL in PowerShell (Admin):
    echo   wsl --install
    echo.
    echo   After install, restart PC, then run this file again.
    pause
    exit /b 1
)

echo [OK] WSL found.
echo.
echo [1/2] Installing dependencies in WSL...
wsl bash -c "sudo bash install-deps.sh"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Install failed! Check error above.
    pause
    exit /b 1
)

echo.
echo [2/2] Setup complete!
echo.
echo   Build ISO now:
echo     wsl make build
echo.
echo   Or open WSL terminal:
echo     sudo ./makebuild.sh
echo.
pause