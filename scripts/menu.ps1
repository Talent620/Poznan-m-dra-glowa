# ============================================================================
#  KLUCZYKI POZNAN MADRA GLOWA - GLOWNE MENU
#  Jedno miejsce, z ktorego wybierasz wszystko. Kazda opcja jest opisana.
#  Nic nie trzeba pamietac ani wpisywac z palca - tylko numer i Enter.
# ============================================================================

$ErrorActionPreference = 'Continue'
$OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Pause-Enter { Write-Host ""; Read-Host "Nacisnij Enter, aby wrocic do menu" | Out-Null }

function Get-EnvValue([string]$key) {
  $envPath = Join-Path $Root ".env"
  if (-not (Test-Path $envPath)) { return "" }
  $line = (Get-Content $envPath | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return ($line -replace "^\s*$key\s*=", "").Trim()
}

# Uruchamia serwer w NOWYM oknie, zeby menu zostalo otwarte.
function Start-InNewWindow([string]$scriptName) {
  $full = Join-Path $Root "scripts\$scriptName"
  Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$full`""
}

function Is-Installed {
  return (Test-Path (Join-Path $Root "node_modules")) -and (Test-Path (Join-Path $Root ".env"))
}

# Gdy cos nie jest zainstalowane - instalujemy SAMI (zamiast odsylac do opcji 1).
# Zwraca $true, gdy mozna isc dalej.
function Ensure-Installed {
  if (Is-Installed) { return $true }
  Write-Host "`nWyglada na pierwsze uruchomienie - instaluje wszystko za Ciebie (1-2 min)..." -ForegroundColor Cyan
  & (Join-Path $Root "scripts\setup.ps1")
  return (Is-Installed)
}

function Show-Menu {
  Clear-Host
  Write-Host "================================================================" -ForegroundColor Magenta
  Write-Host "                  KLUCZYKI POZNAN MADRA GLOWA  -  GLOWNE MENU" -ForegroundColor Magenta
  Write-Host "================================================================" -ForegroundColor Magenta
  Write-Host ""
  if (-not (Is-Installed)) {
    Write-Host "  (!) Wyglada na to, ze to pierwszy raz. Zacznij od opcji 1." -ForegroundColor Yellow
    Write-Host ""
  }
  Write-Host "  Wpisz numer i nacisnij Enter. Nic nie zepsujesz - mozesz probowac." -ForegroundColor Gray
  Write-Host ""
  Write-Host "  --- PRZYGOTOWANIE -------------------------------------------" -ForegroundColor DarkGray
  Write-Host "  1) ZAINSTALUJ / NAPRAW" -ForegroundColor White
  Write-Host "     Pobiera i ustawia wszystko. Kliknij przy pierwszym razie"
  Write-Host "     albo gdy cokolwiek nie dziala. Mozna powtarzac bezpiecznie."
  Write-Host ""
  Write-Host "  2) USTAW, CO CHCESZ UDOSTEPNIC" -ForegroundColor White
  Write-Host "     Pyta prostym jezykiem (narzedzie/strona czy urzadzenie OBD)"
  Write-Host "     i sam zapisuje ustawienia."
  Write-Host ""
  Write-Host "  Z) ZNAJDZ ADAPTER OBD w sieci" -ForegroundColor White
  Write-Host "     Sam wyszukuje adres i port adaptera (np. AIR OBD2 / ELM327)"
  Write-Host "     w Twojej sieci domowej - nie musisz znac numerow."
  Write-Host ""
  Write-Host "  --- UDOSTEPNIANIE (wybierz jeden tryb) ----------------------" -ForegroundColor DarkGray
  Write-Host "  3) DLA PRACOWNIKOW (przez przegladarke)" -ForegroundColor White
  Write-Host "     Tworzy LINK + HASLO + kod QR. Wysylasz pracownikom, oni"
  Write-Host "     otwieraja link w przegladarce. Kazdy z haslem ma dostep."
  Write-Host ""
  Write-Host "  4) TYLKO JA - zdalnie z domu (przez przegladarke)" -ForegroundColor White
  Write-Host "     Dostep ma WYLACZNIE Twoje konto. Laczysz sie z dowolnego"
  Write-Host "     miejsca przez prywatna siec (Tailscale)."
  Write-Host ""
  Write-Host "  5) URZADZENIE OBD - przez prywatna siec (Tailscale)" -ForegroundColor White
  Write-Host "     Udostepnia sprzet stojacy w domu przez prywatna siec."
  Write-Host ""
  Write-Host "  P) POLACZ OBD W TERENIE (mechanik) <-- gdy OBD sie nie laczy" -ForegroundColor White
  Write-Host "     To uruchamiasz U MECHANIKA na laptopie. Wklejasz LINK + HASLO,"
  Write-Host "     a program diagnostyczny laczysz z 127.0.0.1:35000."
  Write-Host "     Dziala przez ZWYKLY link - bez Tailscale."
  Write-Host ""
  Write-Host "  --- DODATKI -------------------------------------------------" -ForegroundColor DarkGray
  Write-Host "  6) URUCHAMIAJ SAM PO STARCIE WINDOWS" -ForegroundColor White
  Write-Host "     Serwer bedzie wstawal sam i wracal po awarii. Bez klikania."
  Write-Host ""
  Write-Host "  7) POKAZ, KTO SIE LACZYL" -ForegroundColor White
  Write-Host "     Ladny raport: ile wejsc, logowan, jakie adresy, kiedy."
  Write-Host ""
  Write-Host "  8) WYLACZ auto-uruchamianie" -ForegroundColor White
  Write-Host "  9) POMOC / pelna instrukcja" -ForegroundColor White
  Write-Host ""
  Write-Host "  0) ZAMKNIJ MENU" -ForegroundColor White
  Write-Host ""
  Write-Host "================================================================" -ForegroundColor Magenta
}

:menuLoop while ($true) {
  Show-Menu
  $sel = Read-Host "Twoj wybor"
  switch ($sel.Trim()) {

    '1' {
      & (Join-Path $Root "scripts\setup.ps1")
      Pause-Enter
    }

    '2' {
      & (Join-Path $Root "scripts\configure.ps1")
      Pause-Enter
    }

    '3' {
      if (-not (Ensure-Installed)) { Write-Host "`nInstalacja sie nie powiodla - sprobuj opcji 1." -ForegroundColor Yellow; Pause-Enter; continue }
      Write-Host ""
      Write-Host "Uruchamiam tryb DLA PRACOWNIKOW w nowym oknie." -ForegroundColor Cyan
      Write-Host "W nowym oknie pojawi sie LINK + HASLO i otworzy sie strona z kodem QR." -ForegroundColor Gray
      Write-Host "WAZNE: tamto okno ZOSTAW OTWARTE - serwer dziala, dopoki jest otwarte." -ForegroundColor Yellow
      Start-InNewWindow "run.ps1"
      Pause-Enter
    }

    '4' {
      if (-not (Ensure-Installed)) { Write-Host "`nInstalacja sie nie powiodla - sprobuj opcji 1." -ForegroundColor Yellow; Pause-Enter; continue }
      Write-Host ""
      Write-Host "Uruchamiam tryb TYLKO JA w nowym oknie." -ForegroundColor Cyan
      Write-Host "Przy pierwszym razie zaloguj sie swoim kontem (otworzy sie przegladarka)." -ForegroundColor Gray
      Write-Host "WAZNE: nowe okno ZOSTAW OTWARTE." -ForegroundColor Yellow
      Start-InNewWindow "run-private.ps1"
      Pause-Enter
    }

    '5' {
      if (-not (Ensure-Installed)) { Write-Host "`nInstalacja sie nie powiodla - sprobuj opcji 1." -ForegroundColor Yellow; Pause-Enter; continue }
      if ([string]::IsNullOrWhiteSpace((Get-EnvValue "DEVICE_PORT")) -and [string]::IsNullOrWhiteSpace((Get-EnvValue "DEVICES"))) {
        Write-Host "`nNajpierw wybierz opcje 2 i ustaw urzadzenie (port)." -ForegroundColor Yellow; Pause-Enter; continue
      }
      Write-Host ""
      Write-Host "Uruchamiam udostepnianie URZADZENIA w nowym oknie." -ForegroundColor Cyan
      Write-Host "Pojawi sie adres i port do wpisania w programie diagnostycznym." -ForegroundColor Gray
      Write-Host "WAZNE: nowe okno ZOSTAW OTWARTE." -ForegroundColor Yellow
      Start-InNewWindow "run-device.ps1"
      Pause-Enter
    }

    { $_ -in 'Z','z' } {
      Write-Host ""
      Write-Host "Szukam adaptera OBD w Twojej sieci domowej (chwila)..." -ForegroundColor Cyan
      & node (Join-Path $Root "src\scan-obd.js")
      Write-Host ""
      Write-Host "Jesli cos znalazl - wpisz 2 (USTAW) i podaj ten adres oraz port." -ForegroundColor Gray
      Pause-Enter
    }

    { $_ -in 'P','p' } {
      Write-Host ""
      Write-Host "Uruchamiam POLACZENIE OBD W TERENIE w nowym oknie." -ForegroundColor Cyan
      Write-Host "Wklej LINK i HASLO od pracodawcy. Potem program diagnostyczny" -ForegroundColor Gray
      Write-Host "podlacz do 127.0.0.1:35000." -ForegroundColor Gray
      Write-Host "WAZNE: nowe okno ZOSTAW OTWARTE." -ForegroundColor Yellow
      Start-InNewWindow "run-obd.ps1"
      Pause-Enter
    }

    '6' {
      Write-Host ""
      Write-Host "Ktora wersja ma uruchamiac sie SAMA po starcie Windows?" -ForegroundColor White
      Write-Host "  1) Dla pracownikow (publiczny link)"
      Write-Host "  2) Tylko ja (zdalnie z domu, Tailscale)"
      Write-Host "  3) OFFLINE / tylko moja siec (bez internetu)" -ForegroundColor Green
      $m = Read-Host "Wpisz 1, 2 albo 3"
      if ($m.Trim() -eq '2') {
        & (Join-Path $Root "scripts\install-autostart.ps1") -Mode private
      } elseif ($m.Trim() -eq '3') {
        & (Join-Path $Root "scripts\install-autostart.ps1") -Mode offline
      } else {
        & (Join-Path $Root "scripts\install-autostart.ps1")
      }
      Pause-Enter
    }

    '7' {
      & node (Join-Path $Root "src\log-report.js")
      $report = Join-Path $Root "RAPORT-POLACZEN.html"
      if (Test-Path $report) { Start-Process $report } else { Write-Host "Brak danych - jeszcze nikt sie nie laczyl." -ForegroundColor Yellow }
      Pause-Enter
    }

    '8' {
      & (Join-Path $Root "scripts\uninstall-autostart.ps1")
      Pause-Enter
    }

    '9' {
      $help = Join-Path $Root "INSTRUKCJA-PROSTA.txt"
      if (Test-Path $help) { Start-Process notepad.exe $help } else { Write-Host "Brak pliku instrukcji." -ForegroundColor Yellow }
      Pause-Enter
    }

    '0' { Write-Host "`nDo zobaczenia!" -ForegroundColor Cyan; break menuLoop }

    default { Write-Host "`nNie rozumiem '$sel'. Wpisz numer 0-9 albo litere P/Z." -ForegroundColor Yellow; Pause-Enter }
  }
}
