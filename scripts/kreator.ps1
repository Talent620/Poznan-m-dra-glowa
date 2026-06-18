# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - KREATOR (najprostsza droga, dla kazdego)
# ----------------------------------------------------------------------------
#  Prowadzi za reke. Zadaje tylko proste pytania (T/N, wklej link).
#  Sam instaluje, sam szuka adaptera, sam uruchamia. Nic nie trzeba pamietac.
# ============================================================================

$ErrorActionPreference = 'Continue'
$OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# --- Drobne pomocniki wyswietlania ------------------------------------------
function Big($t, $c = 'Magenta') {
  Write-Host ""
  Write-Host "================================================================" -ForegroundColor $c
  Write-Host "   $t" -ForegroundColor $c
  Write-Host "================================================================" -ForegroundColor $c
  Write-Host ""
}
function Step($t) { Write-Host ""; Write-Host ">> $t" -ForegroundColor White }
function Ok($t)   { Write-Host "   [OK] $t" -ForegroundColor Green }
function Warn($t) { Write-Host "   [!] $t" -ForegroundColor Yellow }
function Wait-Enter { Write-Host ""; Read-Host "Nacisnij Enter, aby wrocic" | Out-Null }

# --- Praca na pliku .env -----------------------------------------------------
function Get-EnvValue([string]$key) {
  $envPath = Join-Path $Root ".env"
  if (-not (Test-Path $envPath)) { return "" }
  $line = (Get-Content $envPath | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return ($line -replace "^\s*$key\s*=", "").Trim()
}
function Set-EnvValue([string]$key, [string]$value) {
  $envPath = Join-Path $Root ".env"
  if (-not (Test-Path $envPath)) {
    if (Test-Path (Join-Path $Root ".env.example")) { Copy-Item (Join-Path $Root ".env.example") $envPath }
    else { New-Item -ItemType File -Path $envPath | Out-Null }
  }
  $lines = @(Get-Content $envPath)
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match "^\s*$key\s*=") { $found = $true; "$key=$value" } else { $line }
  }
  if (-not $found) { $out += "$key=$value" }
  Set-Content -Path $envPath -Value $out -Encoding UTF8
}

# --- Upewnij sie, ze wszystko jest zainstalowane (jak nie - zainstaluj) ------
function Ensure-Installed {
  $haveNode    = [bool](Get-Command node -ErrorAction SilentlyContinue)
  $haveModules = Test-Path (Join-Path $Root "node_modules")
  $haveEnv     = Test-Path (Join-Path $Root ".env")
  if ($haveNode -and $haveModules -and $haveEnv) { Ok "Wszystko juz gotowe."; return $true }

  Step "Pierwsze uruchomienie - instaluje wszystko za Ciebie. To potrwa 1-2 minuty."
  & (Join-Path $Root "scripts\setup.ps1")

  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Warn "Nie udalo sie zainstalowac silnika (Node.js)."
    Write-Host "   Zainstaluj go raz ze strony https://nodejs.org (sam zielony przycisk, same 'Dalej')," -ForegroundColor White
    Write-Host "   a potem uruchom mnie ponownie." -ForegroundColor White
    try { Start-Process "https://nodejs.org" } catch {}
    return $false
  }
  return $true
}

# --- Znajdz adapter OBD automatycznie (zwraca "host:port" albo $null) --------
function Find-Adapter {
  Step "Szukam adaptera OBD w Twojej sieci domowej (chwila cierpliwosci)..."
  $out = & node (Join-Path $Root "src\scan-obd.js") 2>$null
  $jsonLine = ($out | Where-Object { $_ -match '^JSON:' } | Select-Object -First 1)
  if ($jsonLine) {
    try {
      $arr = @(($jsonLine -replace '^JSON:', '') | ConvertFrom-Json)
      if ($arr.Count -ge 1) { return ("{0}:{1}" -f $arr[0].host, $arr[0].port) }
    } catch {}
  }
  return $null
}

# ============================================================================
#  TRYB: W DOMU (szef udostepnia adapter)
# ============================================================================
function Run-Home([bool]$offline = $true) {
  if ($offline) { Big "W DOMU - OFFLINE / tylko moja siec (nic publicznego)" 'Green' }
  else          { Big "W DOMU - przez internet (publiczny link)" 'Green' }
  if (-not (Ensure-Installed)) { Wait-Enter; return }

  Write-Host "Upewnij sie, ze adapter OBD jest WPIETY do auta i WLACZONY (swieci)." -ForegroundColor Gray
  Write-Host "Komputer i adapter powinny byc w tej samej sieci WiFi." -ForegroundColor Gray
  Read-Host "Gdy gotowe - nacisnij Enter" | Out-Null

  $picked = $false
  $cand = Find-Adapter
  if ($cand) {
    Ok "Znalazlem adapter pod adresem: $cand"
    $a = Read-Host "Uzyc tego adaptera? (Enter = TAK / wpisz n, gdy chcesz podac sam)"
    if ($a -notmatch '^(n|nie|no)$') {
      Set-EnvValue "DEVICES" ("auto=" + $cand)
      Set-EnvValue "DEVICE_HOST" ""; Set-EnvValue "DEVICE_PORT" ""; Set-EnvValue "UPSTREAM_URL" ""
      Ok "Zapisalem adapter - nic wiecej nie musisz ustawiac."
      $picked = $true
    }
  } else {
    Warn "Nie znalazlem adaptera automatycznie."
  }

  if (-not $picked) {
    Write-Host ""
    Write-Host "Podaj adres adaptera recznie (np. 192.168.0.10)." -ForegroundColor Gray
    Write-Host "Nie znasz? Nacisnij Enter - uruchomimy mimo to (mozesz poprawic pozniej)." -ForegroundColor Gray
    $h = Read-Host "Adres adaptera"
    if (-not [string]::IsNullOrWhiteSpace($h)) {
      $p = Read-Host "Port (Enter = 35000)"
      if ([string]::IsNullOrWhiteSpace($p)) { $p = "35000" }
      Set-EnvValue "DEVICES" ("auto=$($h.Trim()):$($p.Trim())")
      Set-EnvValue "DEVICE_HOST" ""; Set-EnvValue "DEVICE_PORT" ""; Set-EnvValue "UPSTREAM_URL" ""
      Ok "Zapisalem adapter."
    } else {
      Warn "Pomijam adapter - uruchamiam sam serwer (adapter ustawisz w MENU pozniej)."
    }
  }

  # --- AUTO-TEST: czy komputer naprawde widzi adapter? --------------------
  Step "Sprawdzam, czy komputer WIDZI adapter (szybki test)..."
  & node (Join-Path $Root "src\check-device.js")
  $rc = $LASTEXITCODE
  if ($rc -eq 0) {
    Big "WSZYSTKO GRA - widze adapter! Mozna udostepniac." 'Green'
  } elseif ($rc -eq 3) {
    Warn "Czesc adapterow widze, a czesci NIE (te z [X] wyzej)."
    Write-Host "   Te widoczne zadzialaja; reszte sprawdz: czy wlaczone i w tej samej sieci WiFi." -ForegroundColor Gray
  } elseif ($rc -eq 2) {
    Warn "Nie ustawiono adaptera - uruchamiam sam serwer (adapter dodasz w MENU)."
  } else {
    Big "NIE WIDZE ADAPTERA" 'Red'
    Write-Host "  Najczestsze przyczyny (sprawdz po kolei):" -ForegroundColor White
    Write-Host "   - adapter nie jest wpiety do auta albo nie swieci," -ForegroundColor Gray
    Write-Host "   - adapter i komputer sa w INNEJ sieci WiFi (musza byc w tej samej)," -ForegroundColor Gray
    Write-Host "   - adapter robi WLASNA siec WiFi - podlacz do niej komputer," -ForegroundColor Gray
    Write-Host "   - zly adres/port - sprobuj jeszcze raz (kreator poszuka ponownie)." -ForegroundColor Gray
    Write-Host ""
    $dalej = Read-Host "Uruchomic mimo to? (Enter = TAK / wpisz n, by przerwac)"
    if ($dalej -match '^(n|nie|no)$') { Wait-Enter; return }
  }

  if ($offline) {
    Step "Wlaczam tryb OFFLINE (bez internetu). Otworzy sie NOWE okno z adresem lokalnym."
    Start-Process powershell -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root 'scripts\run-offline.ps1') + "`"")
    Big "GOTOWE! (OFFLINE - nic publicznego)" 'Green'
    Write-Host "  1. W NOWYM oknie pojawi sie ADRES w Twojej sieci (LAN / Tailscale) i HASLO." -ForegroundColor White
    Write-Host "  2. ZOSTAW tamto okno OTWARTE - dziala, dopoki jest otwarte." -ForegroundColor Yellow
    Write-Host "  3. Daj pracownikowi: ten ADRES + HASLO (wkleja je w pliku nr 8 jako LINK)." -ForegroundColor White
    Write-Host "  Nic nie jest publiczne - dziala tylko w Twojej sieci." -ForegroundColor DarkGray
    Write-Host ""
    $auto = Read-Host "Chcesz, zeby tryb OFFLINE wlaczal sie SAM po starcie Windows? (t = tak)"
    if ($auto -match '^(t|tak|y|yes)$') {
      & (Join-Path $Root "scripts\install-autostart.ps1") -Mode offline
      Write-Host "[OK] Od teraz brama OFFLINE wstanie sama po kazdym zalogowaniu do Windows." -ForegroundColor Green
    }
  } else {
    Step "Wlaczam udostepnianie przez internet. Otworzy sie NOWE okno z LINKIEM, HASLEM i kodem QR."
    Start-Process powershell -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root 'scripts\run.ps1') + "`"")
    Big "GOTOWE!" 'Green'
    Write-Host "  1. W NOWYM oknie pojawi sie LINK i HASLO (oraz strona z kodem QR)." -ForegroundColor White
    Write-Host "  2. ZOSTAW tamto okno OTWARTE - dziala, dopoki jest otwarte." -ForegroundColor Yellow
    Write-Host "  3. Wyslij mechanikowi: LINK + HASLO." -ForegroundColor White
  }
  Wait-Enter
}

# ============================================================================
#  TRYB: W TERENIE (mechanik laczy sie z autem)
# ============================================================================
function Run-Field {
  Big "JESTEM W TERENIE - lacze sie z autem" 'Green'
  if (-not (Ensure-Installed)) { Wait-Enter; return }

  Step "Wlaczam laczenie z autem. Otworzy sie NOWE okno."
  Write-Host "  W nowym oknie:" -ForegroundColor White
  Write-Host "    1. WKLEJ LINK od szefa (klik prawym myszka -> Wklej) i Enter." -ForegroundColor White
  Write-Host "    2. WPISZ HASLO i Enter." -ForegroundColor White
  Write-Host "    3. Gdy pokaze sie tabelka, w programie diagnostycznym wpisz:" -ForegroundColor White
  Write-Host "         Adres 127.0.0.1   Port 35000" -ForegroundColor Yellow
  Start-Process powershell -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root 'scripts\run-obd.ps1') + "`"")

  Big "GOTOWE!" 'Green'
  Write-Host "  Zostaw NOWE okno otwarte podczas diagnozy." -ForegroundColor Yellow
  Wait-Enter
}

# ============================================================================
#  EKRAN GLOWNY
# ============================================================================
:mainLoop while ($true) {
  Clear-Host
  Big "KREATOR - poprowadze Cie krok po kroku" 'Magenta'
  Write-Host "  Wybierz, kim jestes. Nic nie zepsujesz - mozesz probowac." -ForegroundColor Gray
  Write-Host ""
  Write-Host "   [1]  JESTEM W DOMU - OFFLINE / tylko moja siec  (zalecane)" -ForegroundColor White
  Write-Host "        Udostepniam OBD pracownikowi PRYWATNIE - nic publicznego, nic w internecie."
  Write-Host "        Dziala w Twojej sieci (LAN warsztatu) albo przez prywatny Tailscale."
  Write-Host ""
  Write-Host "   [2]  JESTEM W DOMU - przez internet (publiczny link)" -ForegroundColor White
  Write-Host "        Tworzy publiczny link + QR (wygodne z dowolnego miejsca)."
  Write-Host ""
  Write-Host "   [3]  JESTEM W TERENIE" -ForegroundColor White
  Write-Host "        Dostalem ADRES/LINK i HASLO i chce polaczyc sie z autem."
  Write-Host ""
  Write-Host "   [4]  POMOC / pelna instrukcja" -ForegroundColor White
  Write-Host "   [5]  WIECEJ USTAWIEN (menu dla zaawansowanych)" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "   [0]  Zamknij" -ForegroundColor White
  Write-Host ""
  $wybor = Read-Host "Wpisz cyfre i nacisnij Enter"

  switch ($wybor.Trim()) {
    '1' { Run-Home $true }
    '2' { Run-Home $false }
    '3' { Run-Field }
    '4' {
      $help = Join-Path $Root "INSTRUKCJA-PROSTA.txt"
      if (Test-Path $help) { Start-Process notepad.exe $help } else { Warn "Brak pliku instrukcji." }
    }
    '5' {
      & (Join-Path $Root "scripts\menu.ps1")
    }
    '0' { Write-Host "`nDo zobaczenia!" -ForegroundColor Cyan; break mainLoop }
    default { Warn "Nie rozumiem '$wybor'. Wpisz 1, 2, 3, 4, 5 albo 0." ; Start-Sleep -Seconds 1 }
  }
}
