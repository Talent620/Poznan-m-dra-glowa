# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - UDOSTEPNIANIE URZADZENIA (np. interfejs OBD2) W TERENIE
# ----------------------------------------------------------------------------
#  Udostepnia surowe urzadzenie sieciowe przez Twoja prywatna siec Tailscale.
#  W terenie laczysz sie programem diagnostycznym pod adres Tailscale serwera.
#
#  Wczesniej ustaw w pliku .env:
#     DEVICE_HOST=adres urzadzenia w domu (np. 192.168.0.50)  albo 127.0.0.1
#     DEVICE_PORT=port urzadzenia (np. 35000)
#
#  Uruchom:  .\scripts\run-device.ps1
#  Zatrzymaj: Ctrl + C
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$BridgeLog = Join-Path $LogDir "device.bridge.log"
$InfoFile  = Join-Path $Root "DOSTEP-URZADZENIE.txt"

function Get-EnvValue([string]$key) {
  $envPath = Join-Path $Root ".env"
  if (-not (Test-Path $envPath)) { return "" }
  $line = (Get-Content $envPath | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return ($line -replace "^\s*$key\s*=", "").Trim()
}

$DeviceHost = Get-EnvValue "DEVICE_HOST"; if ([string]::IsNullOrWhiteSpace($DeviceHost)) { $DeviceHost = "127.0.0.1" }
$DevicePort = Get-EnvValue "DEVICE_PORT"
$ListenPort = Get-EnvValue "DEVICE_LISTEN_PORT"; if ([string]::IsNullOrWhiteSpace($ListenPort)) { $ListenPort = $DevicePort }

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   UDOSTEPNIANIE URZADZENIA W TERENIE" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

if ([string]::IsNullOrWhiteSpace($DevicePort)) {
  Write-Host "[BLAD] Brak DEVICE_PORT w .env." -ForegroundColor Red
  Write-Host "       Otworz plik .env i ustaw np.:" -ForegroundColor Yellow
  Write-Host "         DEVICE_HOST=192.168.0.50" -ForegroundColor Yellow
  Write-Host "         DEVICE_PORT=35000" -ForegroundColor Yellow
  Write-Host "       (DEVICE_HOST to adres urzadzenia w Twojej domowej sieci, DEVICE_PORT to jego port.)"
  exit 1
}

# --- 1. Tailscale -----------------------------------------------------------
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts) {
  Write-Host "`n[!] Nie znaleziono Tailscale (prywatna siec do zdalnego dostepu)." -ForegroundColor Yellow
  $ans = Read-Host "Zainstalowac przez winget? (t/n)"
  if ($ans -match '^(t|tak|y|yes)$') {
    winget install -e --id Tailscale.Tailscale --accept-source-agreements --accept-package-agreements
    Write-Host "Po instalacji ZAMKNIJ to okno, otworz nowe PowerShell i uruchom ponownie." -ForegroundColor Yellow
    exit 0
  } else {
    Write-Host "Zainstaluj Tailscale ze strony https://tailscale.com/download i uruchom ponownie." -ForegroundColor Yellow
    exit 1
  }
}

Write-Host "`n==> Loguje maszyne do Twojej prywatnej sieci Tailscale..." -ForegroundColor Cyan
Write-Host "    (Przy pierwszym razie otworzy sie przegladarka - zaloguj sie SWOIM kontem.)"
tailscale up | Out-Null

# --- 2. Most TCP ------------------------------------------------------------
Write-Host "==> Uruchamiam most do urzadzenia ($DeviceHost`:$DevicePort)..." -ForegroundColor Cyan
$env:DEVICE_HOST = $DeviceHost
$env:DEVICE_PORT = $DevicePort
$env:DEVICE_LISTEN_PORT = $ListenPort
if (Test-Path $BridgeLog) { Remove-Item $BridgeLog -Force -ErrorAction SilentlyContinue }
$bridge = Start-Process -FilePath "node" -ArgumentList "src/tcp-bridge.js" `
  -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput $BridgeLog -RedirectStandardError (Join-Path $LogDir "device.err.log")
Start-Sleep -Seconds 2

# --- 3. Adres Tailscale serwera ---------------------------------------------
$tsIp = ""
try { $tsIp = (tailscale ip -4 2>$null | Select-Object -First 1).Trim() } catch {}
$dnsName = ""
try {
  $statusJson = tailscale status --json 2>$null | ConvertFrom-Json
  if ($statusJson.Self.DNSName) { $dnsName = $statusJson.Self.DNSName.TrimEnd('.') }
} catch {}

$content = @"
==========================================================
  ZDALNY DOSTEP DO URZADZENIA (np. OBD2) - W TERENIE
==========================================================

W programie diagnostycznym (w terenie) ustaw polaczenie sieciowe na:

  Adres (IP):   $tsIp
  Adres (nazwa):$dnsName
  Port:         $ListenPort

Jak to zrobic na laptopie/telefonie w terenie:
  1. Zainstaluj Tailscale i zaloguj sie TYM SAMYM kontem co na serwerze w domu.
  2. W programie diagnostycznym wybierz polaczenie "po sieci / WiFi / TCP".
  3. Wpisz powyzszy adres i port.
  4. Gotowe - laczysz sie z urzadzeniem w domu tak, jakbys byl obok niego.

Bezpieczenstwo:
  - Urzadzenie NIE jest widoczne publicznie. Dostep ma tylko Twoje konto Tailscale.

Wygenerowano: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
Set-Content -Path $InfoFile -Value $content -Encoding UTF8

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "   GOTOWE - urzadzenie dostepne w terenie:" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ("   Adres : " + $tsIp) -ForegroundColor Yellow
Write-Host ("   Port  : " + $ListenPort) -ForegroundColor Yellow
Write-Host "   (Zapisane w pliku: DOSTEP-URZADZENIE.txt)" -ForegroundColor DarkGray
Write-Host "`nNadzor wlaczony. Ctrl+C konczy." -ForegroundColor DarkGray

# --- 4. Petla nadzoru -------------------------------------------------------
try {
  while ($true) {
    Start-Sleep -Seconds 5
    if ($bridge.HasExited) {
      Write-Host "[$(Get-Date -Format HH:mm:ss)] Most padl - restart." -ForegroundColor Yellow
      $bridge = Start-Process -FilePath "node" -ArgumentList "src/tcp-bridge.js" `
        -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $BridgeLog -RedirectStandardError (Join-Path $LogDir "device.err.log")
    }
  }
}
finally {
  Write-Host "`nZatrzymuje most..." -ForegroundColor Cyan
  if ($bridge -and -not $bridge.HasExited) { try { $bridge.Kill() } catch {} }
  Write-Host "Zatrzymano." -ForegroundColor Cyan
}
