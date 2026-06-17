@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - START
echo ============================================
echo    Witaj! Zaraz wszystko zrobie za Ciebie.
echo ============================================
echo.
echo Otwieram kreator. Wystarczy wybrac:
echo    1 = jestem w domu      2 = jestem w terenie
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\kreator.ps1"
if errorlevel 1 (
  echo.
  echo Cos poszlo nie tak. Kliknij ten plik jeszcze raz.
  echo.
)
pause
