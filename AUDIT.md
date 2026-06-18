# AUDYT — Kluczyki Poznań mądra głowa

Data: 2026-06-18 · Rola: senior architekt · Faza 1 (bez zmian w kodzie).

Stack: **Node.js** (Express, `ws`, `http-proxy-middleware`, `qrcode`, `dotenv`) +
skrypty **PowerShell** + pliki **`.bat`** (Windows). Uruchomienie: `node src/server.js`.
Testów automatycznych brak (do tej pory testy ręczne).

> Uwaga: część wcześniejszych poprawek (hasło w nagłówku, lockout na `/obd`, dynamiczne
> `Secure`, CSRF, keep-alive, walidacja `.env`, obsługa `EADDRINUSE`, kreator, auto-test
> adaptera) jest już WDROŻONA — patrz `CHANGELOG.md`. Ten audyt dotyczy stanu PO tych zmianach
> i wyszukuje to, co jeszcze zostało.

---

## 1. Mapa projektu

### Rdzeń serwera (Node)
- **`src/server.js`** — brama HTTP (Express): logowanie wspólnym hasłem, bramka autoryzacji,
  reverse-proxy do narzędzia (`UPSTREAM_URL`) lub pliki statyczne lub panel/landing; routing
  `upgrade` (WebSocket): `/obd` → most OBD, reszta → proxy. Logi wejść do `logs/access.log`.
- **`src/config.js`** — wczytuje `.env`, waliduje (hasło, sekret, `UPSTREAM_URL`, `DEVICES`).
- **`src/auth.js`** — sesja na podpisanym (HMAC) ciasteczku, porównanie hasła odporne na timing,
  limit prób (lockout) per-IP.
- **`src/obd-ws.js`** — most OBD: WebSocket ⇄ TCP do adaptera; lockout, keep-alive,
  blokada „1 klient/1 urządzenie", heartbeat ping/pong.
- **`src/obd-client.js`** — klient w terenie: lokalny port TCP `127.0.0.1:35000` tunelowany
  WSS-em; klucz w nagłówku, bufor z limitem, timeout, strażniki procesu.
- **`src/devices.js`** — rejestr urządzeń z `.env` (`DEVICES=` lub `DEVICE_*`).
- **`src/probe.js`** — `testReachable(host,port)`, wykrywanie podsieci, typowe porty OBD.
- **`src/scan-obd.js`** — skaner adaptera (wynik tekstowy + linia `JSON:`).
- **`src/check-device.js`** — szybki test, czy komputer widzi adapter (dla kreatora).
- **`src/diagnose.js`** — pełna diagnoza „dlaczego OBD nie przekazuje".
- **`src/tcp-bridge.js`** — alternatywny most TCP 1:1 (tryb Tailscale).
- **`src/share-page.js`** / **`src/log-report.js`** — generatory stron HTML (QR / raport).
- **`src/views/*.html`** — login, panel OBD, landing.

### Warstwa Windows (uruchamianie dwuklikiem)
- **`0 - KLIKNIJ TUTAJ...bat` → `scripts/kreator.ps1`** — kreator „jedno kliknięcie".
- **`MENU - kliknij tutaj.bat` → `scripts/menu.ps1`** — pełne menu (auto-instaluje braki).
- **`scripts/setup.ps1`** — instalacja Node≥18, `npm install`, generacja sekretów, `cloudflared`.
- **`scripts/configure.ps1`** — ustawianie `.env`.
- **`scripts/run.ps1`** — brama + tunel Cloudflare + nadzór + QR.
- **`scripts/run-private.ps1`** — brama + Tailscale Serve (prywatnie).
- **`scripts/run-device.ps1`** — most TCP + Tailscale (surowe urządzenie).
- **`scripts/run-obd.ps1`** — klient OBD w terenie (+ nadzór/restart).
- **`scripts/install-autostart.ps1` / `uninstall-autostart.ps1`** — Harmonogram zadań.

### Przepływy
1. **OBD przez link (główny):** `obd-client` (teren) ⇄ `/obd` WSS ⇄ `obd-ws` ⇄ TCP do adaptera.
2. **Narzędzie webowe:** przeglądarka → Cloudflare → brama (hasło) → proxy do `UPSTREAM_URL`.
3. **Prywatny:** Tailscale Serve → brama. **Urządzenie/Tailscale:** `tcp-bridge` na `0.0.0.0`.

---

## 2. Błędy i ryzyka (lokalizacja + dlaczego)

| # | Miejsce | Problem | Waga |
|---|---|---|---|
| R1 | `src/obd-ws.js` `clientIp()` (XFF `split(',')[0]`) | Bierze **lewy** wpis `X-Forwarded-For` — klient może go **podrobić** i obejść lockout / zatruć logi. Powinien używać `CF-Connecting-IP` lub **prawego** wpisu (hop dodany przez zaufane proxy). | Średni |
| R2 | `src/tcp-bridge.js` (`LISTEN_HOST='0.0.0.0'`) | Most TCP **bez żadnej autoryzacji**, nasłuch na wszystkich interfejsach. Każdy w tej samej sieci LAN dosięgnie surowego portu OBD. Zależy wyłącznie od ACL Tailscale. | Średni (→ decyzja) |
| R3 | `scripts/run.ps1` (`$args`) | Nadpisuje **automatyczną** zmienną PowerShell `$args`. Działa, ale to pułapka/zła praktyka. | Niski |
| R4 | `scripts/run.ps1` (restart tunelu) | Po restarcie tunelu i zmianie adresu aktualizuje `share-info.txt`, ale **nie** odświeża strony QR `UDOSTEPNIJ-PRACOWNIKOM.html` → QR prowadzi do starego adresu. | Niski/Średni |
| R5 | `run-obd.ps1` → `obd-polaczenie.txt` | Zapisuje LINK i **HASŁO jawnym tekstem** na dysku mechanika (wygoda „ostatnie ustawienia"). | Niski |
| R6 | Brak testów automatycznych | Każda zmiana grozi cichą regresją; weryfikacja tylko ręczna. | Średni/Wysoki (utrzymanie) |
| R7 | `.gitignore` | `WYNIK-DIAGNOZY.txt` (efekt diagnozy) **nie jest** ignorowany — mógłby trafić do repo. | Niski |
| R8 | `package.json` `name="reklama-gateway"`, `auth.js` cookie `reklama_auth` | Leftover po poprzednim projekcie („reklama") — niespójność marki. Zmiana nazwy ciasteczka wylogowałaby aktywne sesje. | Niski (kosmetyka) |
| R9 | `src/diagnose.js:86` `var scanFound` w bloku `else` | Działa dzięki hoistingowi `var`, ale czytelnościowo słabe (użyte przez `typeof`). | Niski |
| R10 | `src/server.js` `render()` | `fs.readFileSync` przy każdym żądaniu widoku; `{{BRAND}}`/`{{MODE}}` wstrzykiwane bez escapowania (źródło: `.env`, kontrolowane przez operatora). | Niski |

---

## 3. Słabe punkty (jakość)

- **Bezpieczeństwo:** dobre podstawy (hasło-timing-safe, lockout, HMAC sesja, klucz w nagłówku,
  CSRF, `noindex`). Pozostaje R1 (spoofing IP) i R2 (most TCP bez auth).
- **Obsługa błędów:** spójna i po polsku; gateway i klient mają strażniki. OK.
- **Wydajność:** w skali (1 operator + kilku mechaników) bez zastrzeżeń. Skan sieci 1270 prób/256
  równolegle — akceptowalnie. `readFileSync` w `render` pomijalne.
- **Czytelność:** kod zwięzły, dobrze skomentowany po polsku. Leftover „reklama" myli.
- **Dług techniczny:** brak testów (R6) to największy dług. Brak CI.

---

## 4. Propozycje poprawek (wpływ / ryzyko)

### Wysoki/średni wpływ, niskie–średnie ryzyko → WDROŻYĆ (Faza 2)
- **P1 (R1):** `obd-ws.clientIp()` → użyj `CF-Connecting-IP`, w razie braku **prawego** wpisu XFF.
  Wpływ: średni (poprawność lockoutu). Ryzyko: niskie (lokalnie bez XFF — bez zmian).
- **P2 (R6):** dodać **lekki zestaw testów** (`test/run.js`, `npm test`) — testy jednostkowe
  (`devices`, `auth`, `config.validate`) + integracyjne (login/lockout/CSRF, most OBD przez WS,
  „zajęte", lockout WS). Wpływ: wysoki (utrzymanie). Ryzyko: niskie (tylko dodaje pliki).
- **P3 (R4):** `run.ps1` — przy nowym adresie tunelu **regeneruj** stronę QR. Wpływ: średni
  (poprawny QR po restarcie). Ryzyko: niskie.
- **P4 (R3):** `run.ps1` — zmień `$args` → `$cfArgs`. Wpływ: niski. Ryzyko: niskie.
- **P5 (R7):** dodać `WYNIK-DIAGNOZY.txt` do `.gitignore`. Wpływ: niski. Ryzyko: zerowe.
- **P6 (R5):** `run-obd.ps1` — zapisuj tylko LINK (bez hasła) w `obd-polaczenie.txt`,
  z krótkim wyjaśnieniem. Wpływ: niski-średni (mniej sekretów na dysku). Ryzyko: niskie
  (mechanik wpisze hasło raz; UX minimalnie gorszy).

### DO MOJEJ DECYZJI (duże/ryzykowne — NIE wdrażam sam)
- **D1 (R2):** Most TCP `tcp-bridge.js` bez autoryzacji na `0.0.0.0`. Opcje: (a) bindować do
  adresu Tailscale zamiast `0.0.0.0`, (b) dodać prosty „pre-shared" handshake, (c) zostawić
  (akceptując model „tylko za Tailscale"). Zmienia zachowanie sieciowe → decyzja.
- **D2 (R8):** Rebranding `reklama-gateway`/`reklama_auth` → `kluczyki-*`. Zmiana ciasteczka
  wylogowuje aktywne sesje. Kosmetyka — czy warto teraz?
- **D3:** Reconnect tunelu po stronie `obd-client` (re-otwieranie WS w trakcie sesji). Świadomie
  pominięte: zepsułoby stan sesji ELM327. Czy chcesz osobny tryb „auto-reconnect"?

---

## 5. Pomysły na rozbudowę (od szybkich do ambitnych)
1. **Status w panelu WWW: licznik aktywnych sesji OBD** (kto teraz diagnozuje). Szybkie.
2. **Auto-test po stronie mechanika** — po starcie pokazać „połączono z autem" (zielone).
3. **Health-endpoint rozszerzony** (`/healthz?full` z liczbą urządzeń online) — do monitoringu.
4. **CI (GitHub Actions):** `npm ci && npm test` na każdy push. Średnie.
5. **Pakiet instalacyjny .exe** (np. `pkg`/Inno Setup) zamiast rozpakowywania ZIP — ambitne.
6. **Nazwany tunel Cloudflare jako domyślny** (stały adres) z kreatora — średnie.
