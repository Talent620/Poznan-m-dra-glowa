@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Instalacja
echo ============================================
echo    KLUCZYKI POZNAN MADRA GLOWA - INSTALACJA
echo ============================================
echo.
echo Za chwile zainstaluje wszystko i wygeneruje Twoje haslo.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
echo.
echo Mozesz zamknac to okno.
pause
