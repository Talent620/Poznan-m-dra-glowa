# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - URUCHAMIANIE I NADZOR
#  Co robi:
#    1. uruchamia brame (Node.js),
#    2. uruchamia tunel Cloudflare (publiczny HTTPS, bez konfiguracji routera),
#    3. wylapuje publiczny adres i zapisuje share-info.txt (link + haslo),
#    4. pilnuje obu procesow i restartuje je po awarii (pelna autonomia).
#  Uruchom:  .\scripts\run.ps1
#  Zatrzymaj: Ctrl + C
# ============================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$GatewayLog = Join-Path $LogDir "gateway.log"
$TunnelLog  = Join-Path $LogDir "cloudflared.log"
$ShareInfo  = Join-Path $Root  "share-info.txt"

# --- Wczytaj wybrane wartosci z .env ----------------------------------------
function Get-EnvValue([string]$key) {
  $envPath = Join-Path $Root ".env"
  if (-not (Test-Path $envPath)) { return "" }
  $line = (Get-Content $envPath | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return ($line -replace "^\s*$key\s*=", "").Trim()
}

$Port         = Get-EnvValue "PORT"; if ([string]::IsNullOrWhiteSpace($Port)) { $Port = "8080" }
$Password     = Get-EnvValue "ACCESS_PASSWORD"
$TunnelToken  = Get-EnvValue "CLOUDFLARE_TUNNEL_TOKEN"
$LocalTarget  = "http://127.0.0.1:$Port"

if ([string]::IsNullOrWhiteSpace($Password)) {
  Write-Host "[BLAD] Brak ACCESS_PASSWORD w .env. Uruchom najpierw: .\scripts\setup.ps1" -ForegroundColor Red
  exit 1
}
if (-not (Test-Path (Join-Path $Root "cloudflared.exe"))) {
  Write-Host "[BLAD] Brak cloudflared.exe. Uruchom najpierw: .\scripts\setup.ps1" -ForegroundColor Red
  exit 1
}

# --- Pomocnicze: start procesow ---------------------------------------------
function Start-Gateway {
  if (Test-Path $GatewayLog) { Remove-Item $GatewayLog -Force -ErrorAction SilentlyContinue }
  Start-Process -FilePath "node" -ArgumentList "src/server.js" `
    -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $GatewayLog -RedirectStandardError (Join-Path $LogDir "gateway.err.log")
}

function Start-Tunnel {
  if (Test-Path $TunnelLog) { Remove-Item $TunnelLog -Force -ErrorAction SilentlyContinue }
  $cf = Join-Path $Root "cloudflared.exe"
  if (-not [string]::IsNullOrWhiteSpace($TunnelToken)) {
    # Tryb nazwany: staly adres (Twoja domena w Cloudflare).
    $cfArgs = "tunnel run --token $TunnelToken"
  } else {
    # Tryb szybki: losowy adres *.trycloudflare.com, bez konta.
    $cfArgs = "tunnel --no-autoupdate --url $LocalTarget"
  }
  Start-Process -FilePath $cf -ArgumentList $cfArgs `
    -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $TunnelLog -RedirectStandardError (Join-Path $LogDir "cloudflared.err.log")
}

# --- Wylapanie publicznego adresu z logu cloudflared ------------------------
function Find-PublicUrl {
  $sources = @($TunnelLog, (Join-Path $LogDir "cloudflared.err.log"))
  foreach ($src in $sources) {
    if (Test-Path $src) {
      $m = Select-String -Path $src -Pattern 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($m) { return $m.Matches[0].Value }
    }
  }
  return $null
}

function Write-ShareInfo([string]$url) {
  $content = @"
========================================
  DOSTEP DO NARZEDZIA - DLA PRACOWNIKOW
========================================

Adres (link):
  $url

Haslo wspolne:
  $Password

Instrukcja dla pracownika:
  1. Otworz powyzszy link w przegladarce.
  2. Wpisz wspolne haslo.
  3. Gotowe - korzystaj z narzedzia.

Wygenerowano: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
(W trybie szybkiego tunelu adres moze zmienic sie po restarcie.
 Aby miec staly adres, ustaw CLOUDFLARE_TUNNEL_TOKEN w .env - patrz README.)
"@
  Set-Content -Path $ShareInfo -Value $content -Encoding UTF8
}

# --- Start ------------------------------------------------------------------
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   KLUCZYKI POZNAN MADRA GLOWA - uruchamiam" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "Brama lokalna : $LocalTarget"
Write-Host "Logi          : $LogDir"
Write-Host ""

$gw = Start-Gateway
Start-Sleep -Seconds 2
$tn = Start-Tunnel

# Czekaj na publiczny adres (do ~30 s).
$publicUrl = $null
if ([string]::IsNullOrWhiteSpace($TunnelToken)) {
  Write-Host "Czekam na publiczny adres tunelu..." -ForegroundColor Cyan
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $publicUrl = Find-PublicUrl
    if ($publicUrl) { break }
  }
}

if ($publicUrl) {
  Write-ShareInfo $publicUrl
  # Ladna strona z kodem QR + przyciskami "Kopiuj" - otwiera sie sama.
  $sharePage = Join-Path $Root "UDOSTEPNIJ-PRACOWNIKOM.html"
  try {
    node "src/share-page.js" --mode shared --url $publicUrl --password $Password --out $sharePage | Out-Null
    Start-Process $sharePage
  } catch { Write-Host "    (Nie udalo sie wygenerowac strony QR: $($_.Exception.Message))" -ForegroundColor DarkYellow }

  Write-Host ""
  Write-Host "============================================" -ForegroundColor Green
  Write-Host "   GOTOWE - rozdaj to pracownikom:" -ForegroundColor Green
  Write-Host "============================================" -ForegroundColor Green
  Write-Host ("   Link  : " + $publicUrl) -ForegroundColor Yellow
  Write-Host ("   Haslo : " + $Password)  -ForegroundColor Yellow
  Write-Host ""
  Write-Host "   Otwarto strone z kodem QR: UDOSTEPNIJ-PRACOWNIKOM.html" -ForegroundColor DarkGray
  Write-Host "   (Link i haslo tez w pliku: share-info.txt)" -ForegroundColor DarkGray
} else {
  Write-Host "Tunel uruchomiony. Adres znajdziesz w logach lub (tryb nazwany) na Twojej domenie." -ForegroundColor Cyan
}

Write-Host "`nNadzor wlaczony. Procesy beda restartowane po awarii. Ctrl+C konczy." -ForegroundColor DarkGray

# --- Petla nadzoru: restartuj to, co padnie ---------------------------------
try {
  while ($true) {
    Start-Sleep -Seconds 5

    if ($gw.HasExited) {
      Write-Host "[$(Get-Date -Format HH:mm:ss)] Brama padla - restart." -ForegroundColor Yellow
      $gw = Start-Gateway
    }
    if ($tn.HasExited) {
      Write-Host "[$(Get-Date -Format HH:mm:ss)] Tunel padl - restart." -ForegroundColor Yellow
      $tn = Start-Tunnel
      Start-Sleep -Seconds 3
      if ([string]::IsNullOrWhiteSpace($TunnelToken)) {
        $newUrl = Find-PublicUrl
        if ($newUrl -and $newUrl -ne $publicUrl) {
          $publicUrl = $newUrl
          Write-ShareInfo $publicUrl
          # Odswiez tez strone z kodem QR, by nie prowadzila do starego adresu.
          $sharePage = Join-Path $Root "UDOSTEPNIJ-PRACOWNIKOM.html"
          try { node "src/share-page.js" --mode shared --url $publicUrl --password $Password --out $sharePage | Out-Null } catch {}
          Write-Host ("[$(Get-Date -Format HH:mm:ss)] Nowy adres: " + $publicUrl + " (odswiezono link, haslo i kod QR)") -ForegroundColor Yellow
        }
      }
    }
  }
}
finally {
  Write-Host "`nZatrzymuje procesy..." -ForegroundColor Cyan
  foreach ($p in @($gw, $tn)) {
    if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
  }
  Write-Host "Zatrzymano." -ForegroundColor Cyan
}
