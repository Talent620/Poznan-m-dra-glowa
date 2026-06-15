@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kluczyki Poznan madra glowa - Raport polaczen
echo Generuje raport polaczen...
node "%~dp0src\log-report.js"
if exist "%~dp0RAPORT-POLACZEN.html" (
  start "" "%~dp0RAPORT-POLACZEN.html"
) else (
  echo Nie udalo sie wygenerowac raportu. Czy serwer byl juz uruchamiany?
  pause
)
