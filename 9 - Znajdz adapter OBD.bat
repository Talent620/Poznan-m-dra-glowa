@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Znajdz adapter OBD
echo ============================================
echo    SZUKAM ADAPTERA OBD W SIECI DOMOWEJ
echo ============================================
echo.
echo Upewnij sie, ze adapter (np. AIR OBD2) jest wpiety do auta,
echo wlaczony i w tej samej sieci WiFi co ten komputer.
echo.
node "%~dp0src\scan-obd.js"
echo.
echo Przepisz znaleziony adres i port w MENU (opcja 2 USTAW).
echo.
pause
