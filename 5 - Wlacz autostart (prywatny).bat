@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Autostart (prywatny)
echo ============================================
echo    WLACZAM AUTOSTART - WERSJA PRYWATNA
echo ============================================
echo.
echo Wersja prywatna (tylko Ty) bedzie wstawala sama po starcie Windows.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-autostart.ps1" -Mode private
echo.
pause
