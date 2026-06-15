@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - START (pracownicy)
echo ============================================
echo    URUCHAMIAM SERWER DLA PRACOWNIKOW
echo ============================================
echo.
echo Za chwile pojawi sie LINK + HASLO i otworzy sie strona z kodem QR.
echo To okno zostaw OTWARTE - serwer dziala dopoki jest otwarte.
echo Aby zatrzymac: zamknij to okno lub nacisnij Ctrl+C.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run.ps1"
pause
