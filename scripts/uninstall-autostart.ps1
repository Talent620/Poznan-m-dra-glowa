# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - WYLACZENIE AUTOSTARTU
#  Usuwa zadanie z Harmonogramu zadan. Pliki projektu zostaja nietkniete.
#  Uruchom:  .\scripts\uninstall-autostart.ps1
# ============================================================================

$ErrorActionPreference = 'Stop'
$removed = $false

foreach ($TaskName in @("KluczykiPoznan", "KluczykiPoznanPrivate", "KluczykiPoznanOffline")) {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[OK] Autostart wylaczony (zadanie '$TaskName' usuniete)." -ForegroundColor Green
    $removed = $true
  }
}

if (-not $removed) {
  Write-Host "[i] Brak zadan autostartu - nie bylo czego usuwac." -ForegroundColor Yellow
}
