# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - POLACZ OBD PRZEZ LINK (w terenie)
# ----------------------------------------------------------------------------
#  Uruchamiasz to NA LAPTOPIE U MECHANIKA / W TERENIE.
#  Tworzy lokalny port (np. 127.0.0.1:35000), do ktorego podlaczasz program
#  diagnostyczny. Ruch OBD jedzie przez link Cloudflare do urzadzenia w domu.
#  Dziala przez ZWYKLY darmowy link - bez Tailscale, bez routera.
#
#  Obsluguje WIELE urzadzen: wybierasz jedno albo wszystkie naraz (kazde
#  dostaje wlasny port lokalny: 35000, 35001, 35002 ...).
#
#  Potrzebujesz od pracodawcy: LINK + HASLO.
#
#  Uruchom:  .\scripts\run-obd.ps1
#  Zatrzymaj: Ctrl + C
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$SaveFile  = Join-Path $Root "obd-polaczenie.txt"

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   POLACZ OBD PRZEZ LINK (w terenie)" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

# --- Sprawdz Node.js --------------------------------------------------------
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "[BLAD] Nie ma Node.js. Kliknij najpierw '1 - INSTALACJA.bat'." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path (Join-Path $Root "node_modules\ws"))) {
  Write-Host "[i] Brakuje czesci programu - instaluje (chwila)..." -ForegroundColor Yellow
  npm install --no-fund --no-audit | Out-Null
}

# --- Wczytaj poprzednie ustawienia, jesli sa -------------------------------
$prevLink = ""; $prevKey = ""
if (Test-Path $SaveFile) {
  foreach ($line in Get-Content $SaveFile) {
    if ($line -match "^LINK=(.*)$") { $prevLink = $Matches[1].Trim() }
    if ($line -match "^KEY=(.*)$")  { $prevKey  = $Matches[1].Trim() }
  }
}

# --- Zapytaj o link ---------------------------------------------------------
if ($prevLink) {
  Write-Host "Ostatni link: $prevLink" -ForegroundColor DarkGray
  $link = Read-Host "Podaj LINK (Enter = uzyj ostatniego)"
  if ([string]::IsNullOrWhiteSpace($link)) { $link = $prevLink }
} else {
  $link = Read-Host "Podaj LINK od pracodawcy (np. https://cos.trycloudflare.com)"
}
if ([string]::IsNullOrWhiteSpace($link)) {
  Write-Host "[BLAD] Bez linku nie da sie polaczyc." -ForegroundColor Red
  exit 1
}
$link = $link.Trim().TrimEnd('/')

# --- Zapytaj o haslo --------------------------------------------------------
if ($prevKey) {
  $key = Read-Host "Podaj HASLO (Enter = uzyj ostatniego)"
  if ([string]::IsNullOrWhiteSpace($key)) { $key = $prevKey }
} else {
  $key = Read-Host "Podaj HASLO (wspolne, to samo co do strony)"
}
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Host "[BLAD] Bez hasla serwer nie wpusci polaczenia." -ForegroundColor Red
  exit 1
}

# Zapamietaj na przyszlosc.
Set-Content -Path $SaveFile -Value @("LINK=$link", "KEY=$key") -Encoding UTF8

# --- Pobierz liste urzadzen z serwera ---------------------------------------
Write-Host ""
Write-Host "Sprawdzam, jakie urzadzenia sa dostepne..." -ForegroundColor Cyan
$deviceNames = @()
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  # Haslo wysylamy w naglowku (NIE w adresie) - nie trafi do logow tunelu.
  $resp = Invoke-RestMethod -Uri "$link/obd-devices" -Headers @{ 'x-obd-key' = $key } -TimeoutSec 20
  if ($resp.devices) { $deviceNames = @($resp.devices | ForEach-Object { $_.name }) }
} catch {
  Write-Host "[i] Nie udalo sie pobrac listy urzadzen ($($_.Exception.Message))." -ForegroundColor Yellow
  Write-Host "    Sprobuje polaczyc sie z urzadzeniem domyslnym." -ForegroundColor Yellow
}

# --- Ustal, ktore urzadzenia podlaczyc --------------------------------------
# Kazdy wpis: @{ Device = nazwa lub ''; Port = 35000+i }
$selected = @()

if ($deviceNames.Count -eq 0) {
  # Brak listy - jedno polaczenie domyslne (bez nazwy).
  $selected += @{ Device = ''; Port = 35000 }
}
elseif ($deviceNames.Count -eq 1) {
  $selected += @{ Device = $deviceNames[0]; Port = 35000 }
}
else {
  Write-Host ""
  Write-Host "Dostepne urzadzenia:" -ForegroundColor White
  for ($i = 0; $i -lt $deviceNames.Count; $i++) {
    Write-Host ("   {0}) {1}   ->  port lokalny {2}" -f ($i + 1), $deviceNames[$i], (35000 + $i))
  }
  Write-Host "   A) WSZYSTKIE naraz (kazde na swoim porcie)" -ForegroundColor Gray
  Write-Host ""
  $pick = Read-Host "Wpisz numer urzadzenia albo A (Enter = pierwsze)"
  $pick = $pick.Trim()
  if ($pick -match '^(a|all|w|wszystkie)$') {
    for ($i = 0; $i -lt $deviceNames.Count; $i++) {
      $selected += @{ Device = $deviceNames[$i]; Port = 35000 + $i }
    }
  } elseif ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $deviceNames.Count) {
    $selected += @{ Device = $deviceNames[[int]$pick - 1]; Port = 35000 }
  } else {
    $selected += @{ Device = $deviceNames[0]; Port = 35000 }
  }
}

# --- Start klientow (po jednym na urzadzenie) -------------------------------
function Start-OneClient($device, $port) {
  $env:OBD_LINK = $link
  $env:OBD_KEY = $key
  $env:OBD_DEVICE = $device
  $env:OBD_LOCAL_PORT = "$port"
  $env:OBD_LOCAL_HOST = "127.0.0.1"
  $tag = if ([string]::IsNullOrWhiteSpace($device)) { "domyslne" } else { $device }
  $outLog = Join-Path $LogDir ("obd-client-{0}.log" -f $tag)
  $errLog = Join-Path $LogDir ("obd-client-{0}.err.log" -f $tag)
  if (Test-Path $outLog) { Remove-Item $outLog -Force -ErrorAction SilentlyContinue }
  Start-Process -FilePath "node" -ArgumentList "src/obd-client.js" `
    -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog
}

$running = @()
foreach ($s in $selected) {
  $proc = Start-OneClient $s.Device $s.Port
  $running += @{ Device = $s.Device; Port = $s.Port; Proc = $proc }
}
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   GOTOWE - w programie diagnostycznym wpisz:" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
foreach ($r in $running) {
  $tag = if ([string]::IsNullOrWhiteSpace($r.Device)) { "urzadzenie" } else { $r.Device }
  Write-Host ("   {0,-16}  Adres: 127.0.0.1   Port: {1}" -f $tag, $r.Port) -ForegroundColor Yellow
}
Write-Host ""
Write-Host "   W programie wybierz polaczenie 'po sieci / WiFi / TCP'" -ForegroundColor Gray
Write-Host "   i wpisz adres 127.0.0.1 oraz odpowiedni port z listy wyzej." -ForegroundColor Gray
Write-Host "`nNadzor wlaczony. Ctrl+C konczy." -ForegroundColor DarkGray

# --- Petla nadzoru: restartuj klienta, ktory padnie -------------------------
try {
  while ($true) {
    Start-Sleep -Seconds 5
    for ($i = 0; $i -lt $running.Count; $i++) {
      if ($running[$i].Proc.HasExited) {
        $r = $running[$i]
        $tag = if ([string]::IsNullOrWhiteSpace($r.Device)) { "domyslne" } else { $r.Device }
        Write-Host "[$(Get-Date -Format HH:mm:ss)] Klient '$tag' padl - restart." -ForegroundColor Yellow
        $running[$i].Proc = Start-OneClient $r.Device $r.Port
      }
    }
  }
}
finally {
  Write-Host "`nZatrzymuje klientow OBD..." -ForegroundColor Cyan
  foreach ($r in $running) {
    if ($r.Proc -and -not $r.Proc.HasExited) { try { $r.Proc.Kill() } catch {} }
  }
  Write-Host "Zatrzymano." -ForegroundColor Cyan
}
