@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Polacz OBD w terenie
echo ============================================
echo    POLACZ OBD PRZEZ LINK (w terenie)
echo ============================================
echo.
echo To uruchamiasz NA LAPTOPIE U MECHANIKA / W TERENIE.
echo Potrzebujesz LINK i HASLO od pracodawcy.
echo.
echo Po starcie podlacz program diagnostyczny do:  127.0.0.1 : 35000
echo To okno zostaw OTWARTE. Aby zatrzymac: zamknij okno lub Ctrl+C.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-obd.ps1"
pause
