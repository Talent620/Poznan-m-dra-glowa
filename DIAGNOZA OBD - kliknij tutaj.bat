@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - DIAGNOZA OBD
echo ============================================
echo    DIAGNOZA OBD - sprawdzam, gdzie jest problem
echo ============================================
echo.
echo Uruchom to NA KOMPUTERZE W DOMU (gdzie jest adapter OBD).
echo Adapter musi byc wpiety do auta i wlaczony.
echo.
node "%~dp0src\diagnose.js" > "%~dp0WYNIK-DIAGNOZY.txt" 2>&1
type "%~dp0WYNIK-DIAGNOZY.txt"
echo.
echo ------------------------------------------------------------
echo Wynik zapisano takze w pliku:  WYNIK-DIAGNOZY.txt
echo Skopiuj go i przeslij - wskaze dokladna przyczyne.
echo ------------------------------------------------------------
echo.
pause
