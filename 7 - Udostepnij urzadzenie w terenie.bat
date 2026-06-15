@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Udostepnij urzadzenie (OBD) w terenie
echo ============================================
echo    UDOSTEPNIAM URZADZENIE W TERENIE
echo ============================================
echo.
echo Najpierw upewnij sie, ze w pliku .env ustawiles:
echo    DEVICE_HOST = adres urzadzenia w domu (np. 192.168.0.50)
echo    DEVICE_PORT = port urzadzenia (np. 35000)
echo.
echo To okno zostaw OTWARTE. Aby zatrzymac: zamknij okno lub Ctrl+C.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-device.ps1"
pause
