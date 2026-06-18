# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - TRYB OFFLINE / TYLKO MOJA SIEC
# ----------------------------------------------------------------------------
#  Uruchamia BRAME bez zadnego publicznego linku (BEZ Cloudflare).
#  Dostep dziala WYLACZNIE w Twojej sieci:
#    - LAN (ta sama siec WiFi/kabel w warsztacie), albo
#    - prywatny Tailscale (zdalnie, ale tylko Twoje konto/urzadzenia).
#  Nic nie jest publiczne, nic nie trafia na zewnatrz, nic sie nie "swieci".
#
#  Uruchom:  .\scripts\run-offline.ps1
#  Zatrzymaj: Ctrl + C
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$GatewayLog = Join-Path $LogDir "gateway.log"
$InfoFile   = Join-Path $Root "OFFLINE-DOSTEP.txt"

function Get-EnvValue([string]$key) {
  $envPath = Join-Path $Root ".env"
  if (-not (Test-Path $envPath)) { return "" }
  $line = (Get-Content $envPath | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return ($line -replace "^\s*$key\s*=", "").Trim()
}

$Port     = Get-EnvValue "PORT"; if ([string]::IsNullOrWhiteSpace($Port)) { $Port = "8080" }
$Password = Get-EnvValue "ACCESS_PASSWORD"
if ([string]::IsNullOrWhiteSpace($Password)) {
  Write-Host "[BLAD] Brak ACCESS_PASSWORD w .env. Uruchom najpierw: .\scripts\setup.ps1" -ForegroundColor Red
  exit 1
}

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   TRYB OFFLINE - TYLKO TWOJA SIEC (bez internetu)" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "Nic publicznego. Brak linku w internecie. Dziala w LAN / Tailscale." -ForegroundColor Gray
Write-Host ""

# --- Adres LAN (ta sama siec) -----------------------------------------------
$lanIp = ""
try {
  $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.' } |
    Sort-Object -Property { $_.IPAddress -match '^192\.168\.' } -Descending |
    Select-Object -First 1).IPAddress
} catch {}
if ([string]::IsNullOrWhiteSpace($lanIp)) {
  try { $lanIp = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 -ErrorAction SilentlyContinue).IPV4Address.IPAddressToString } catch {}
}

# --- Adres Tailscale (jesli jest) -------------------------------------------
$tsIp = ""; $tsName = ""
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
  try { $tsIp = (tailscale ip -4 2>$null | Select-Object -First 1).Trim() } catch {}
  try {
    $st = tailscale status --json 2>$null | ConvertFrom-Json
    if ($st.Self.DNSName) { $tsName = $st.Self.DNSName.TrimEnd('.') }
  } catch {}
}

# --- Start bramy (nasluch na calej sieci, by LAN/Tailscale mogly dosiegnac) --
function Start-Gateway {
  if (Test-Path $GatewayLog) { Remove-Item $GatewayLog -Force -ErrorAction SilentlyContinue }
  # HOST=0.0.0.0 -> brama widoczna w Twojej sieci (nadal chroniona haslem + lockout).
  $env:HOST = "0.0.0.0"
  Start-Process -FilePath "node" -ArgumentList "src/server.js" `
    -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $GatewayLog -RedirectStandardError (Join-Path $LogDir "gateway.err.log")
}

$gw = Start-Gateway
Start-Sleep -Seconds 2

# --- Zbuduj liste adresow do podania pracownikowi ---------------------------
$addrLan = if ($lanIp)  { "http://$lanIp`:$Port" } else { "" }
$addrTs  = if ($tsIp)   { "http://$tsIp`:$Port" }  else { "" }
$addrTsN = if ($tsName) { "http://$tsName`:$Port" } else { "" }

$content = @"
==========================================================
  DOSTEP OFFLINE - TYLKO TWOJA SIEC (nic publicznego)
==========================================================

Podaj pracownikowi JEDEN z ponizszych adresow (jako "LINK" w pliku nr 8)
oraz HASLO. Adres dziala TYLKO w Twojej sieci - nie ma go w internecie.

  W tej samej sieci (warsztat, ta sama WiFi/kabel):
    $addrLan

  Zdalnie przez prywatny Tailscale (tylko Twoje konto/urzadzenia):
    $addrTs
    $addrTsN

  HASLO:
    $Password

Jak laczy sie pracownik:
  1. Klika "8 - Polacz OBD w terenie (mechanik).bat".
  2. Jako LINK wkleja jeden z adresow powyzej, potem wpisuje HASLO.
  3. W programie diagnostycznym laczy sie z 127.0.0.1 i podanym portem.

Bezpieczenstwo:
  - Brak publicznego linku, brak Cloudflare, nic nie trafia na zewnatrz.
  - Dostep chroniony wspolnym haslem + limitem prob (lockout).
  - LAN: dziala w obrebie Twojej sieci. Tailscale: tylko Twoje konto.

Wygenerowano: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
Set-Content -Path $InfoFile -Value $content -Encoding UTF8

Write-Host "============================================" -ForegroundColor Green
Write-Host "   GOTOWE - dostep OFFLINE (tylko Twoja siec):" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
if ($addrLan) { Write-Host ("   W sieci (LAN): " + $addrLan) -ForegroundColor Yellow }
if ($addrTs)  { Write-Host ("   Tailscale    : " + $addrTs)  -ForegroundColor Yellow }
if ($addrTsN) { Write-Host ("   Tailscale    : " + $addrTsN) -ForegroundColor DarkYellow }
Write-Host ("   Haslo        : " + $Password) -ForegroundColor Yellow
Write-Host "   (Zapisane w pliku: OFFLINE-DOSTEP.txt)" -ForegroundColor DarkGray
if (-not $addrLan -and -not $addrTs) {
  Write-Host "`n[!] Nie wykryto adresu sieci. Sprawdz polaczenie WiFi/LAN albo zainstaluj Tailscale." -ForegroundColor Yellow
}
Write-Host "`nNadzor wlaczony. To okno ZOSTAW OTWARTE. Ctrl+C konczy." -ForegroundColor DarkGray

# --- Petla nadzoru ----------------------------------------------------------
try {
  while ($true) {
    Start-Sleep -Seconds 5
    if ($gw.HasExited) {
      Write-Host "[$(Get-Date -Format HH:mm:ss)] Brama padla - restart." -ForegroundColor Yellow
      $gw = Start-Gateway
    }
  }
}
finally {
  Write-Host "`nZatrzymuje brame..." -ForegroundColor Cyan
  if ($gw -and -not $gw.HasExited) { try { $gw.Kill() } catch {} }
  Write-Host "Zatrzymano." -ForegroundColor Cyan
}
