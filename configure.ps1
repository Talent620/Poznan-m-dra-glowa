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
    Write-Host "Podaj adres urzadzenia w Twojej domowej sieci." -ForegroundColor Gray
    Write-Host "Przyklad: 192.168.0.50   (jesli nie wiesz, nacisnij Enter - uzyjemy 127.0.0.1)" -ForegroundColor Gray
    $h = Read-Host "Adres urzadzenia"
    if ([string]::IsNullOrWhiteSpace($h)) { $h = "127.0.0.1" }
    Set-EnvValue "DEVICE_HOST" ($h.Trim())

    Write-Host ""
    Write-Host "Podaj port urzadzenia. Dla adapterow WiFi OBD czesto jest to 35000." -ForegroundColor Gray
    $p = Read-Host "Port urzadzenia (np. 35000)"
    if ([string]::IsNullOrWhiteSpace($p)) { $p = "35000" }
    Set-EnvValue "DEVICE_PORT" ($p.Trim())
    Set-EnvValue "UPSTREAM_URL" ""

    Write-Host "`n[OK] Zapisano ustawienia urzadzenia ($h`:$p)." -ForegroundColor Green
    Write-Host "Teraz w MENU wybierz: udostepnij URZADZENIE w terenie." -ForegroundColor White
  }
  default {
    Set-EnvValue "UPSTREAM_URL" ""
    Write-Host "`n[OK] Ustawiono tryb testowy - zobaczysz strone powitalna." -ForegroundColor Green
    Write-Host "Mozesz pozniej uruchomic konfigurator ponownie." -ForegroundColor White
  }
}
Write-Host ""
