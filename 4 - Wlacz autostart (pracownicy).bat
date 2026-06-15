@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Autostart (pracownicy)
echo ============================================
echo    WLACZAM AUTOSTART - WERSJA DLA PRACOWNIKOW
echo ============================================
echo.
echo Serwer bedzie wstawal SAM po kazdym zalogowaniu do Windows
echo i sam restartowal sie po awarii.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-autostart.ps1"
echo.
pause
