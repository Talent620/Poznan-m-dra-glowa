# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - POLACZ OBD PRZEZ LINK (w terenie)
# ----------------------------------------------------------------------------
#  Uruchamiasz to NA LAPTOPIE U MECHANIKA / W TERENIE.
#  Tworzy lokalny port (127.0.0.1:35000), do ktorego podlaczasz program
#  diagnostyczny. Ruch OBD jedzie przez link Cloudflare do urzadzenia w domu.
#  Dziala przez ZWYKLY darmowy link - bez Tailscale, bez routera.
#
#  Potrzebujesz dwoch rzeczy od pracodawcy:
#     - LINK   (np. https://cos-tam.trycloudflare.com)
#     - HASLO  (to samo co do strony)
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
$ClientLog = Join-Path $LogDir "obd-client.log"
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
$prevLink = ""; $prevKey = ""; $prevPort = ""
if (Test-Path $SaveFile) {
  foreach ($line in Get-Content $SaveFile) {
    if ($line -match "^LINK=(.*)$")  { $prevLink = $Matches[1].Trim() }
    if ($line -match "^KEY=(.*)$")   { $prevKey  = $Matches[1].Trim() }
    if ($line -match "^PORT=(.*)$")  { $prevPort = $Matches[1].Trim() }
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

# --- Port lokalny -----------------------------------------------------------
$port = $prevPort
if ([string]::IsNullOrWhiteSpace($port)) { $port = "35000" }

# Zapamietaj na przyszlosc (bez zbednych pytan nastepnym razem).
Set-Content -Path $SaveFile -Value @("LINK=$link", "KEY=$key", "PORT=$port") -Encoding UTF8

# --- Start klienta z nadzorem ----------------------------------------------
$env:OBD_LINK = $link
$env:OBD_KEY = $key
$env:OBD_LOCAL_PORT = $port
$env:OBD_LOCAL_HOST = "127.0.0.1"

function Start-Client {
  Start-Process -FilePath "node" -ArgumentList "src/obd-client.js" `
    -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $ClientLog -RedirectStandardError (Join-Path $LogDir "obd-client.err.log")
}

if (Test-Path $ClientLog) { Remove-Item $ClientLog -Force -ErrorAction SilentlyContinue }
$client = Start-Client
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   GOTOWE - podlacz program diagnostyczny do:" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ("   Adres : 127.0.0.1") -ForegroundColor Yellow
Write-Host ("   Port  : " + $port) -ForegroundColor Yellow
Write-Host ""
Write-Host "   W programie diagnostycznym wybierz polaczenie 'po sieci / WiFi / TCP'" -ForegroundColor Gray
Write-Host "   i wpisz powyzszy adres oraz port." -ForegroundColor Gray
Write-Host "`nNadzor wlaczony. Ctrl+C konczy." -ForegroundColor DarkGray

try {
  while ($true) {
    Start-Sleep -Seconds 5
    if ($client.HasExited) {
      Write-Host "[$(Get-Date -Format HH:mm:ss)] Klient OBD padl - restart." -ForegroundColor Yellow
      $client = Start-Client
    }
  }
}
finally {
  Write-Host "`nZatrzymuje klienta OBD..." -ForegroundColor Cyan
  if ($client -and -not $client.HasExited) { try { $client.Kill() } catch {} }
  Write-Host "Zatrzymano." -ForegroundColor Cyan
}
