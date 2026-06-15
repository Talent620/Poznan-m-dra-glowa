# Changelog

Lista zmian. Najnowsze na gorze.

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
