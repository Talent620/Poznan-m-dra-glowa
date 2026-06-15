# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - INSTALATOR (uruchom raz)
#  Co robi:
#    1. sprawdza Node.js (proponuje instalacje),
#    2. instaluje zaleznosci npm,
#    3. tworzy plik .env i generuje mocne haslo + sekret sesji,
#    4. pobiera cloudflared.exe (tunel, bez konfiguracji routera).
#  Uruchom w PowerShell:  .\scripts\setup.ps1
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

# Przejdz do katalogu glownego projektu (rodzic katalogu scripts).
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }

# Odswiezenie zmiennej PATH w biezacym oknie (po instalacji Node nie trzeba
# zamykac okna - program od razu sie znajdzie).
function Update-SessionPath {
  $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   KLUCZYKI POZNAN MADRA GLOWA - instalacja" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "Usiadz wygodnie - zaraz wszystko zrobie za Ciebie." -ForegroundColor Gray

# --- 1. Node.js (silnik programu) -------------------------------------------
Write-Step "Sprawdzam, czy jest zainstalowany Node.js (silnik programu)"
Update-SessionPath
$node = Get-Command node -ErrorAction SilentlyContinue

if (-not $node) {
  Write-Warn2 "Nie ma jeszcze Node.js - zainstaluje go teraz automatycznie."

  $installed = $false

  # Sposob 1: winget (wbudowany w nowsze Windows).
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "    Instaluje przez Menedzer pakietow Windows (winget)..."
    try {
      winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
      Update-SessionPath
      if (Get-Command node -ErrorAction SilentlyContinue) { $installed = $true }
    } catch { Write-Warn2 "winget nie dal rady, sprobuje inaczej." }
  }

  # Sposob 2: pobranie i instalacja oficjalnego instalatora MSI.
  if (-not $installed) {
    try {
      $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
      $msiUrl = "https://nodejs.org/dist/v20.18.0/node-v20.18.0-$arch.msi"
      $msi = Join-Path $env:TEMP "nodejs-setup.msi"
      Write-Host "    Pobieram instalator Node.js..."
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing
      Write-Host "    Instaluje Node.js (chwila cierpliwosci)..."
      Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
      Update-SessionPath
      if (Get-Command node -ErrorAction SilentlyContinue) { $installed = $true }
    } catch { Write-Warn2 "Automatyczna instalacja sie nie powiodla." }
  }

  if (-not $installed) {
    Write-Host ""
    Write-Host "  Nie udalo sie zainstalowac Node.js automatycznie." -ForegroundColor Yellow
    Write-Host "  Zrob to recznie - to proste:" -ForegroundColor Yellow
    Write-Host "    1. Otworz strone:  https://nodejs.org" -ForegroundColor White
    Write-Host "    2. Kliknij duzy zielony przycisk (wersja LTS) i zainstaluj (same Dalej)." -ForegroundColor White
    Write-Host "    3. Potem kliknij plik '1 - INSTALACJA.bat' jeszcze raz." -ForegroundColor White
    try { Start-Process "https://nodejs.org" } catch {}
    exit 1
  }
}
$nodeVer = (node --version)  # np. "v20.18.0"
Write-Ok ("Node.js dziala (" + $nodeVer + ")")

# Wymagamy Node 18 lub nowszego (program z tego korzysta).
$nodeMajor = 0
if ($nodeVer -match 'v(\d+)\.') { $nodeMajor = [int]$Matches[1] }
if ($nodeMajor -gt 0 -and $nodeMajor -lt 18) {
  Write-Warn2 "Masz starsza wersje Node.js ($nodeVer). Potrzebna jest 18 lub nowsza."
  Write-Host  "    Zainstaluj nowa wersje LTS ze strony https://nodejs.org (same 'Dalej')," -ForegroundColor White
  Write-Host  "    a potem kliknij '1 - INSTALACJA.bat' jeszcze raz." -ForegroundColor White
  try { Start-Process "https://nodejs.org" } catch {}
  exit 1
}

# --- 2. Zaleznosci programu -------------------------------------------------
Write-Step "Instaluje czesci programu (to moze potrwac minute)"
$npmOk = $false
for ($try = 1; $try -le 3 -and -not $npmOk; $try++) {
  try {
    npm install --no-fund --no-audit
    if ($LASTEXITCODE -eq 0) { $npmOk = $true } else { throw "npm zwrocil blad" }
  } catch {
    Write-Warn2 "Proba $try nie wyszla, probuje jeszcze raz..."
    Start-Sleep -Seconds 3
  }
}
if (-not $npmOk) {
  Write-Host "  Nie udalo sie pobrac czesci programu (sprawdz internet) i kliknij plik 1 ponownie." -ForegroundColor Yellow
  exit 1
}
Write-Ok "Czesci programu zainstalowane."

# --- 3. Plik .env + sekrety -------------------------------------------------
Write-Step "Konfiguruje plik .env"
$envPath = Join-Path $Root ".env"
if (-not (Test-Path $envPath)) {
  Copy-Item (Join-Path $Root ".env.example") $envPath
  Write-Ok "Utworzono .env z szablonu."
} else {
  Write-Ok "Plik .env juz istnieje - uzupelniam tylko brakujace sekrety."
}

function New-Secret([int]$bytes) {
  $b = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  # base64url bez znakow problematycznych
  ([Convert]::ToBase64String($b)) -replace '\+','-' -replace '/','_' -replace '=',''
}

function Set-EnvValue([string]$key, [string]$value) {
  $lines = Get-Content $envPath
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match "^\s*$key\s*=") { $found = $true; "$key=$value" } else { $line }
  }
  if (-not $found) { $out += "$key=$value" }
  Set-Content -Path $envPath -Value $out -Encoding UTF8
}

function Get-EnvValue([string]$key) {
  $line = (Get-Content $envPath | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return ($line -replace "^\s*$key\s*=", "").Trim()
}

# Haslo dostepu
if ([string]::IsNullOrWhiteSpace((Get-EnvValue "ACCESS_PASSWORD"))) {
  $pwd = New-Secret 9   # ~12 znakow
  Set-EnvValue "ACCESS_PASSWORD" $pwd
  Write-Ok "Wygenerowano wspolne haslo dostepu."
} else {
  Write-Ok "Haslo dostepu juz ustawione - zostawiam."
}

# Sekret sesji
if ([string]::IsNullOrWhiteSpace((Get-EnvValue "SESSION_SECRET"))) {
  Set-EnvValue "SESSION_SECRET" (New-Secret 32)
  Write-Ok "Wygenerowano sekret sesji."
} else {
  Write-Ok "Sekret sesji juz ustawiony - zostawiam."
}

# --- 4. cloudflared (tunel do trybu dla pracownikow) ------------------------
Write-Step "Pobieram tunel (potrzebny do udostepniania pracownikom)"
$cf = Join-Path $Root "cloudflared.exe"
if (Test-Path $cf) {
  Write-Ok "Tunel juz pobrany."
} else {
  $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $cfOk = $false
  for ($try = 1; $try -le 3 -and -not $cfOk; $try++) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $cf -UseBasicParsing
      if ((Test-Path $cf) -and ((Get-Item $cf).Length -gt 1000000)) { $cfOk = $true }
    } catch {
      Write-Warn2 "Proba $try nie wyszla, probuje jeszcze raz..."
      Start-Sleep -Seconds 3
    }
  }
  if ($cfOk) {
    Write-Ok "Tunel pobrany."
  } else {
    Write-Warn2 "Nie udalo sie pobrac tunelu (sprawdz internet). Tryb 'tylko ja' i 'urzadzenie' i tak zadzialaja."
    Write-Warn2 "Aby uzyc trybu dla pracownikow - kliknij plik 1 jeszcze raz pozniej."
  }
}

# --- Podsumowanie -----------------------------------------------------------
Write-Host "`n============================================" -ForegroundColor Green
Write-Host "   GOTOWE! Wszystko zainstalowane." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Twoje haslo (zapisz je gdzies):" -ForegroundColor White
Write-Host ("    " + (Get-EnvValue "ACCESS_PASSWORD")) -ForegroundColor Yellow
Write-Host ""
Write-Host "Co dalej? To proste:" -ForegroundColor White
Write-Host "  -> Zamknij to okno i kliknij dwa razy plik:" -ForegroundColor White
Write-Host "       MENU - kliknij tutaj.bat" -ForegroundColor Cyan
Write-Host "  Tam wybierzesz z listy, co chcesz zrobic. Program podpowie reszte." -ForegroundColor Gray
Write-Host ""
