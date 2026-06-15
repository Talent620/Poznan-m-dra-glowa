# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - KONFIGURATOR (ustaw, co chcesz udostepnic)
#  Pyta prostym jezykiem i sam zapisuje ustawienia. Nie trzeba niczego
#  edytowac recznie.
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$envPath = Join-Path $Root ".env"
if (-not (Test-Path $envPath)) {
  if (Test-Path (Join-Path $Root ".env.example")) {
    Copy-Item (Join-Path $Root ".env.example") $envPath
  } else {
    New-Item -ItemType File -Path $envPath | Out-Null
  }
}

function Set-EnvValue([string]$key, [string]$value) {
  $lines = @(Get-Content $envPath)
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match "^\s*$key\s*=") { $found = $true; "$key=$value" } else { $line }
  }
  if (-not $found) { $out += "$key=$value" }
  Set-Content -Path $envPath -Value $out -Encoding UTF8
}

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   USTAW: CO CHCESZ UDOSTEPNIC?" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  1) Narzedzie / strone internetowa"
Write-Host "     (cos, co otwiera sie w przegladarce - panel, aplikacja webowa)"
Write-Host ""
Write-Host "  2) Urzadzenie - np. interfejs OBD2 do auta"
Write-Host "     (sprzet, z ktorym laczysz sie programem diagnostycznym)"
Write-Host ""
Write-Host "  3) Nie wiem / chce tylko przetestowac"
Write-Host ""
$choice = Read-Host "Wpisz numer (1, 2 albo 3) i nacisnij Enter"

switch ($choice.Trim()) {
  '1' {
    Write-Host ""
    Write-Host "Podaj adres swojego narzedzia. Zwykle wyglada tak:" -ForegroundColor Gray
    Write-Host "   http://127.0.0.1:3000" -ForegroundColor Gray
    Write-Host "(Jesli nie wiesz - po prostu nacisnij Enter, ustawimy strone testowa.)" -ForegroundColor Gray
    $u = Read-Host "Adres narzedzia"
    Set-EnvValue "UPSTREAM_URL" ($u.Trim())
    Set-EnvValue "DEVICE_PORT" ""
    if ([string]::IsNullOrWhiteSpace($u)) {
      Write-Host "`n[OK] Ustawiono tryb testowy (strona powitalna)." -ForegroundColor Green
    } else {
      Write-Host "`n[OK] Zapisano adres narzedzia." -ForegroundColor Green
    }
    Write-Host "Teraz w MENU wybierz START (pracownicy albo tylko ja)." -ForegroundColor White
  }
  '2' {
    Write-Host ""
    Write-Host "Mozesz dodac JEDNO lub WIELE urzadzen OBD (np. kilka aut / lokalizacji)." -ForegroundColor Gray
    Write-Host "Kazde urzadzenie dostanie nazwe - po niej rozpoznasz je w terenie." -ForegroundColor Gray
    Write-Host ""

    $find = Read-Host "Poszukac adaptera w sieci automatycznie? (t/n)"
    if ($find -match '^(t|tak|y|yes)$') {
      Write-Host "Szukam adaptera OBD (chwila)..." -ForegroundColor Cyan
      try { & node (Join-Path $Root "src\scan-obd.js") } catch { Write-Host "Nie udalo sie uruchomic skanera." -ForegroundColor Yellow }
      Write-Host ""
      Write-Host "Przepisz znaleziony adres i port ponizej (lub wpisz wlasne)." -ForegroundColor Gray
      Write-Host ""
    }

    $devicesList = @()
    $num = 1
    while ($true) {
      Write-Host "--- Urzadzenie #$num ---" -ForegroundColor Cyan
      $name = Read-Host "Nazwa urzadzenia (np. warsztat1, audi, bus)  [Enter = urzadzenie$num]"
      if ([string]::IsNullOrWhiteSpace($name)) { $name = "urzadzenie$num" }
      $name = ($name.Trim() -replace '[^A-Za-z0-9_-]', '-').Trim('-')
      if ([string]::IsNullOrWhiteSpace($name)) { $name = "urzadzenie$num" }

      Write-Host "Adres urzadzenia w domowej sieci. Przyklad: 192.168.0.10" -ForegroundColor Gray
      $h = Read-Host "Adres (Enter = 127.0.0.1)"
      if ([string]::IsNullOrWhiteSpace($h)) { $h = "127.0.0.1" }

      Write-Host "Port urzadzenia. Dla adapterow WiFi OBD / ELM327 czesto 35000." -ForegroundColor Gray
      $p = Read-Host "Port (Enter = 35000)"
      if ([string]::IsNullOrWhiteSpace($p)) { $p = "35000" }

      $devicesList += "$name=$($h.Trim()):$($p.Trim())"
      Write-Host "[OK] Dodano: $name -> $($h.Trim()):$($p.Trim())" -ForegroundColor Green
      Write-Host ""

      $more = Read-Host "Dodac kolejne urzadzenie? (t/n)"
      if ($more -notmatch '^(t|tak|y|yes)$') { break }
      $num++
    }

    Set-EnvValue "DEVICES" ($devicesList -join "; ")
    Set-EnvValue "DEVICE_HOST" ""
    Set-EnvValue "DEVICE_PORT" ""
    Set-EnvValue "UPSTREAM_URL" ""

    Write-Host "`n[OK] Zapisano $($devicesList.Count) urzadzenie/urzadzen." -ForegroundColor Green
    Write-Host "Teraz w MENU wybierz tryb 3 (DLA PRACOWNIKOW) - to wlaczy most OBD na linku." -ForegroundColor White
    Write-Host "W terenie mechanik wybiera urzadzenie po nazwie (opcja P / plik nr 8)." -ForegroundColor White
  }
  default {
    Set-EnvValue "UPSTREAM_URL" ""
    Write-Host "`n[OK] Ustawiono tryb testowy - zobaczysz strone powitalna." -ForegroundColor Green
    Write-Host "Mozesz pozniej uruchomic konfigurator ponownie." -ForegroundColor White
  }
}
Write-Host ""
