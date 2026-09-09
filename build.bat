@echo off
title Silence - Build no GitHub Actions
echo ========================================================
echo   Iniciando build no GitHub Actions e download do APK...
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_and_download.ps1" -PushChanges %*

echo.
pause
