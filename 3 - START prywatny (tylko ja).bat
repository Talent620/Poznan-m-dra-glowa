@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - START prywatny
echo ============================================
echo    URUCHAMIAM WERSJE PRYWATNA (tylko Ty)
echo ============================================
echo.
echo Polaczenie tylko dla Ciebie, przez prywatna siec Tailscale.
echo To okno zostaw OTWARTE. Aby zatrzymac: zamknij okno lub Ctrl+C.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-private.ps1"
pause
