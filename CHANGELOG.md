# Changelog

Lista zmian. Najnowsze na gorze.

## Tryb OFFLINE / tylko moja siec (prywatne udostepnianie, bez internetu)

- Nowy `scripts/run-offline.ps1`: uruchamia brame BEZ publicznego linku (bez Cloudflare).
  Dostep dziala wylacznie w Twojej sieci - LAN (ta sama siec) albo prywatny Tailscale.
  Pokazuje gotowy adres lokalny (LAN IP / nazwa Tailscale) + haslo i zapisuje
  `OFFLINE-DOSTEP.txt`. Brama nasluchuje na 0.0.0.0 (nadal chroniona haslem + lockout).
- Kreator: nowa, ZALECANA opcja „W DOMU - OFFLINE / tylko moja siec" (publiczny link
  zostaje jako osobna opcja). Pracownik laczy sie jak zwykle (plik 8), wklejajac
  adres lokalny zamiast publicznego linku.
- `.gitignore`: `OFFLINE-DOSTEP.txt`.
- Zasada bez zmian: narzedzie TYLKO przekazuje surowe polaczenie i NIE dotyka licencji
  ani zabezpieczen cudzego oprogramowania diagnostycznego (nie obchodzi dongli/aktywacji).

## Audyt senior-architekta: testy + utwardzenia (Faza 2)

- **Testy automatyczne** (`test/run.js`, `npm test`): 29 testow - jednostkowe
  (`devices`, `auth`, `config.validate`) i integracyjne (logowanie/cookie/CSRF,
  most OBD przez WebSocket, blokada „zajete", lockout). Bez zewnetrznych frameworkow.
- **Lockout odporny na podrabianie IP** (`obd-ws.js`): zamiast lewego wpisu
  `X-Forwarded-For` uzywamy `CF-Connecting-IP` lub prawego (zaufanego) wpisu -
  nie da sie obejsc blokady, podstawiajac falszywy adres.
- **`run.ps1`**: po zmianie adresu tunelu odswieza tez strone z kodem QR
  (wczesniej QR prowadzil do starego adresu); `$args` -> `$cfArgs` (kolizja ze
  zmienna automatyczna PowerShell).
- **`run-obd.ps1`**: nie zapisuje juz HASLA na dysk - pamieta tylko LINK.
- `.gitignore`: dodany `WYNIK-DIAGNOZY.txt`.
- Dokumenty audytu: `AUDIT.md`, `PROGRESS.md`.

## Auto-test adaptera po ustawieniu

- Nowy szybki tester `src/check-device.js`: sprawdza, czy komputer WIDZI
  skonfigurowany adapter (bez skanowania calej sieci). Kreator po ustawieniu
  adaptera uruchamia go i pokazuje **zielone „WSZYSTKO GRA"** albo **czerwone
  „NIE WIDZE ADAPTERA"** z prosta lista, co sprawdzic — zanim wlaczy udostepnianie.

## Maksymalne uproszczenie obslugi („zeby dziecko dalo rade")

- Nowy **kreator** (`scripts/kreator.ps1`) + jeden plik startowy
  **`0 - KLIKNIJ TUTAJ (zacznij od tego).bat`**: zadaje tylko jedno pytanie
  („w domu" czy „w terenie"), a reszte robi sam — instaluje przy pierwszym razie,
  automatycznie **znajduje adapter OBD** w sieci, ustawia go i uruchamia
  udostepnianie (LINK + HASLO + kod QR). Zero recznego wpisywania adresow.
- `menu.ps1`: zamiast odsylac do „najpierw opcja 1", **samo doinstalowuje** brakujace
  rzeczy (brak slepych zaulkow). Opcja 5 (urzadzenie przez Tailscale) rozpoznaje teraz
  tez wpis `DEVICES`, nie tylko `DEVICE_PORT`.
- Zaktualizowany `START-TUTAJ.txt` i README — prowadza do jednego pliku startowego.

## Naprawa i wzmocnienie (audyt OBD przez link)

### Bezpieczenstwo
- Haslo OBD przeniesione z adresu (`?key=...`) do naglowka `x-obd-key` w kliencie
  terenowym (`obd-client.js`) i w skrypcie `run-obd.ps1` — nie wycieka do logow tunelu.
  Serwer nadal akceptuje `?key=...` dla zgodnosci wstecz.
- Dodany limit prob (lockout) na mostie OBD: `/obd` (WebSocket) oraz `/obd-devices` i
  `/obd-status` — wspolny z logowaniem, liczony po prawdziwym adresie IP (X-Forwarded-For).
  Klient pokazuje czytelny komunikat „ZA DUZO PROB" (kod 429).
- Flaga `Secure` ciasteczka sesji ustawiana dynamicznie (tylko gdy HTTPS) — logowanie
  dziala teraz tez przy tescie lokalnym po `http://` (LAN).
- Dodana lekka ochrona CSRF na `POST /login` (sprawdzenie naglowka `Origin`).
- Sciezka w `logs/access.log` zapisywana bez czesci po `?` — zaden sekret w adresie nie
  trafi do logow.

### Niezawodnosc
- `setKeepAlive(true)` na gniazdach TCP do urzadzenia (`obd-ws.js`, `tcp-bridge.js`,
  oraz po stronie klienta) — wykrywanie zerwanego/wylaczonego adaptera.
- `obd-client.js`: ograniczony bufor „pending" (max 1 MB) i timeout otwarcia tunelu
  (20 s) z czytelnym komunikatem, gdy tunel sie nie otworzy.
- `obd-client.js`: zabezpieczenie procesu (uncaughtException / unhandledRejection) — drobny
  blad jednego polaczenia nie kladzie calego klienta; nadzor/restart robi `run-obd.ps1`.
- `server.js`: czytelna obsluga zajetego portu bramy (`EADDRINUSE`) zamiast brzydkiego crasha.
- `obd-ws.js`: urzadzenie nie zostaje „zajete" na zawsze, jesli handshake padnie przed
  nawiazaniem polaczenia.

### Walidacja / konfiguracja
- `config.validate()` sprawdza teraz poprawnosc `UPSTREAM_URL` oraz wpisow `DEVICES` /
  `DEVICE_PORT` — czytelne komunikaty po polsku, zamiast cichej awarii.
- `setup.ps1` wymaga teraz wyraznie Node.js w wersji 18 lub nowszej.
