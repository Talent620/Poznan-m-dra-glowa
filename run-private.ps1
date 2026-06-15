# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - WERSJA PRYWATNA (tylko Ty, zdalnie z domu)
# ----------------------------------------------------------------------------
#  Roznica wzgledem wersji wspolnej (run.ps1):
#    - NIE wystawia narzedzia publicznie zadnym linkiem dla pracownikow,
#    - udostepnia je w prywatnej sieci Tailscale - widocznej WYLACZNIE
#      na Twoim koncie i Twoich urzadzeniach,
#    - laczysz sie z domu (telefon/laptop) po zalogowaniu do tej samej sieci.
#
#  Uruchom:  .\scripts\run-private.ps1
#  Zatrzymaj: Ctrl + C
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$GatewayLog = Join-Path $LogDir "gateway.log"
$ShareInfo  = Join-Path $Root  "private-access.txt"

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
Write-Host "   KLUCZYKI POZNAN MADRA GLOWA - WERSJA PRYWATNA" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# --- 1. Tailscale -----------------------------------------------------------
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts) {
  Write-Host "`n[!] Nie znaleziono Tailscale (prywatna siec do zdalnego dostepu)." -ForegroundColor Yellow
  $ans = Read-Host "Zainstalowac przez winget? (t/n)"
  if ($ans -match '^(t|tak|y|yes)$') {
    winget install -e --id Tailscale.Tailscale --accept-source-agreements --accept-package-agreements
    Write-Host "Po instalacji ZAMKNIJ to okno, otworz nowe PowerShell i uruchom run-private.ps1 ponownie." -ForegroundColor Yellow
    exit 0
  } else {
    Write-Host "Zainstaluj Tailscale ze strony https://tailscale.com/download i uruchom ponownie." -ForegroundColor Yellow
    exit 1
  }
}

# --- 2. Logowanie do Twojej prywatnej sieci ---------------------------------
Write-Host "`n==> Loguje maszyne do Twojej prywatnej sieci Tailscale..." -ForegroundColor Cyan
Write-Host "    (Przy pierwszym uruchomieniu otworzy sie przegladarka - zaloguj sie SWOIM kontem.)"
tailscale up | Out-Null

# --- 3. Brama (Node.js) -----------------------------------------------------
Write-Host "==> Uruchamiam brame lokalnie (127.0.0.1:$Port)..." -ForegroundColor Cyan
if (Test-Path $GatewayLog) { Remove-Item $GatewayLog -Force -ErrorAction SilentlyContinue }
$gw = Start-Process -FilePath "node" -ArgumentList "src/server.js" `
  -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput $GatewayLog -RedirectStandardError (Join-Path $LogDir "gateway.err.log")
Start-Sleep -Seconds 2

# --- 4. Udostepnienie tylko w Twojej sieci (Tailscale Serve, HTTPS) ---------
Write-Host "==> Udostepniam narzedzie PRYWATNIE (tylko Twoje konto)..." -ForegroundColor Cyan
# Najpierw czyscimy ewentualna stara konfiguracje serve.
tailscale serve reset 2>$null | Out-Null
# Wystaw lokalna brame jako HTTPS w obrebie tailnetu (tylko Twoje urzadzenia).
tailscale serve --bg --https=443 "http://127.0.0.1:$Port" 2>&1 | Out-Null

Start-Sleep -Seconds 2

# --- 5. Ustal prywatny adres (MagicDNS) -------------------------------------
$privateUrl = $null
try {
  $statusJson = tailscale status --json 2>$null | ConvertFrom-Json
  $dns = $statusJson.Self.DNSName
  if ($dns) { $privateUrl = "https://" + ($dns.TrimEnd('.')) }
} catch {}

$content = @"
========================================
  PRYWATNY DOSTEP - TYLKO DLA CIEBIE
========================================

Adres (dziala tylko na Twoich urzadzeniach w sieci Tailscale):
  $privateUrl

Haslo:
  $Password

Jak laczyc sie z domu / w podrozy:
  1. Na telefonie/laptopie zainstaluj Tailscale i zaloguj sie TYM SAMYM kontem.
  2. Otworz powyzszy adres w przegladarce.
  3. Wpisz haslo - masz pelna kontrole nad narzedziem zdalnie.

Bezpieczenstwo:
  - Narzedzie NIE jest widoczne publicznie ani w wyszukiwarkach.
  - Dostep ma wylacznie Twoje konto Tailscale (i urzadzenia, ktore dodasz).

Wygenerowano: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
Set-Content -Path $ShareInfo -Value $content -Encoding UTF8

# Ladna strona z kodem QR (wygodne zalogowanie z telefonu) - otwiera sie sama.
if ($privateUrl) {
  $sharePage = Join-Path $Root "UDOSTEPNIJ-PRYWATNY.html"
  try {
    node "src/share-page.js" --mode private --url $privateUrl --password $Password --out $sharePage | Out-Null
    Start-Process $sharePage
  } catch { Write-Host "    (Nie udalo sie wygenerowac strony QR: $($_.Exception.Message))" -ForegroundColor DarkYellow }
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "   GOTOWE - dostep PRYWATNY (tylko Ty):" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
if ($privateUrl) {
  Write-Host ("   Adres : " + $privateUrl) -ForegroundColor Yellow
} else {
  Write-Host "   Adres : sprawdz 'tailscale serve status'" -ForegroundColor Yellow
}
Write-Host ("   Haslo : " + $Password) -ForegroundColor Yellow
Write-Host "   (Zapisane w pliku: private-access.txt)" -ForegroundColor DarkGray
Write-Host "`nNadzor wlaczony. Ctrl+C konczy." -ForegroundColor DarkGray

# --- 6. Petla nadzoru -------------------------------------------------------
try {
  while ($true) {
    Start-Sleep -Seconds 5
    if ($gw.HasExited) {
      Write-Host "[$(Get-Date -Format HH:mm:ss)] Brama padla - restart." -ForegroundColor Yellow
      $gw = Start-Process -FilePath "node" -ArgumentList "src/server.js" `
        -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $GatewayLog -RedirectStandardError (Join-Path $LogDir "gateway.err.log")
    }
  }
}
finally {
  Write-Host "`nZatrzymuje brame..." -ForegroundColor Cyan
  if ($gw -and -not $gw.HasExited) { try { $gw.Kill() } catch {} }
  # Serve zostaje skonfigurowany; aby calkiem wylaczyc dostep: tailscale serve reset
  Write-Host "Zatrzymano. (Aby wylaczyc prywatny dostep: tailscale serve reset)" -ForegroundColor Cyan
}
