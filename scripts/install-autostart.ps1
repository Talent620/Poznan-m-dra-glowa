# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - AUTOSTART Z WINDOWS
#  Rejestruje zadanie w Harmonogramie zadan, ktore uruchamia wybrana wersje
#  automatycznie po zalogowaniu - z automatycznym restartem.
#
#  Wersja wspolna (dla pracownikow, domyslna):
#      .\scripts\install-autostart.ps1
#  Wersja prywatna (tylko Ty, przez Tailscale):
#      .\scripts\install-autostart.ps1 -Mode private
# ============================================================================

param(
  [ValidateSet('shared', 'private', 'offline')]
  [string]$Mode = 'shared'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

if ($Mode -eq 'private') {
  $RunScript = Join-Path $Root "scripts\run-private.ps1"
  $TaskName  = "KluczykiPoznanPrivate"
} elseif ($Mode -eq 'offline') {
  $RunScript = Join-Path $Root "scripts\run-offline.ps1"
  $TaskName  = "KluczykiPoznanOffline"
} else {
  $RunScript = Join-Path $Root "scripts\run.ps1"
  $TaskName  = "KluczykiPoznan"
}
Write-Host "Wersja: $Mode  (zadanie: $TaskName)" -ForegroundColor Cyan

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   KLUCZYKI POZNAN MADRA GLOWA - konfiguracja autostartu" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

if (-not (Test-Path $RunScript)) {
  Write-Host "[BLAD] Nie znaleziono run.ps1. Uruchom z katalogu projektu." -ForegroundColor Red
  exit 1
}

# Akcja: uruchom PowerShell, ukryte okno, bez profilu, nasz skrypt run.ps1.
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RunScript`""

# Wyzwalacz: przy zalogowaniu uzytkownika.
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Ustawienia: restart przy bledzie, brak limitu czasu, dziala caly czas.
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

# Uruchamiaj jako biezacy uzytkownik (dostep do jego srodowiska/aplikacji).
$principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
  -LogonType Interactive -RunLevel Limited

# Usun stare zadanie, jesli istnieje.
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Host "    Usunieto poprzednie zadanie." -ForegroundColor DarkGray
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Settings $settings -Principal $principal `
  -Description "Kluczyki Poznan madra glowa - autonomiczny serwer udostepniajacy narzedzie pracownikom." | Out-Null

Write-Host "`n[OK] Autostart skonfigurowany." -ForegroundColor Green
Write-Host "Serwer uruchomi sie sam po kazdym zalogowaniu do Windows."
Write-Host ""
Write-Host "Mozesz uruchomic go teraz, bez restartu, komenda:" -ForegroundColor White
Write-Host "    Start-ScheduledTask -TaskName $TaskName" -ForegroundColor Yellow
Write-Host ""
Write-Host "Aby wylaczyc autostart:  .\scripts\uninstall-autostart.ps1" -ForegroundColor DarkGray
