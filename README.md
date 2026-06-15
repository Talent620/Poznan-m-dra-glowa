# Kluczyki Poznań mądra głowa

Autonomiczny serwer-brama na Windows, ktory udostepnia Twoje **narzedzie webowe**
— bez konfiguracji routera, z automatycznym startem i restartem.

Dostepne sa **dwie wersje**:

| Wersja | Dla kogo | Jak dziala | Skrypt |
|---|---|---|---|
| **Wspolna** | dla pracownikow | publiczny link + jedno wspolne haslo (bez kont), przez tunel Cloudflare | `run.ps1` |
| **Prywatna** | tylko dla Ciebie | prywatna siec Tailscale — widoczna wylacznie na Twoim koncie, sterujesz z domu | `run-private.ps1` |

Obie wersje korzystaja z tej samej bramy i tego samego pliku `.env`. Mozesz miec obie naraz.

---

## Najprosciej: jedno MENU (polecane dla osob nietechnicznych)

Kliknij dwa razy **`MENU - kliknij tutaj.bat`**. Otworzy sie lista opcji
(instalacja, ustawienia, trzy tryby udostepniania, autostart, raport) — wybierasz
numer i Enter. Kazda pozycja ma opis, co robi. Gdy cos nie dziala — wybierz
opcje **1 (ZAINSTALUJ / NAPRAW)**, mozna powtarzac bez obaw.

Konfigurator (opcja 2 w menu) pyta prostym jezykiem, co chcesz udostepnic, i sam
zapisuje ustawienia — **nie trzeba recznie edytowac pliku `.env`**.

### Alternatywnie: pojedyncze pliki do dwuklika

Jesli wolisz, sa tez osobne pliki `.bat` — wystarczy kliknac dwa razy:

| Plik | Co robi |
|---|---|
| `1 - INSTALACJA.bat` | instaluje wszystko i generuje haslo (raz) |
| `2 - START dla pracownikow.bat` | uruchamia wersje wspolna; pokazuje link + haslo i **otwiera strone z kodem QR** |
| `3 - START prywatny (tylko ja).bat` | uruchamia wersje prywatna (Tailscale) |
| `4 - Wlacz autostart (pracownicy).bat` | serwer wstaje sam z Windows (wersja wspolna) |
| `5 - Wlacz autostart (prywatny).bat` | autostart wersji prywatnej |
| `6 - Pokaz kto sie laczyl.bat` | otwiera **raport polaczen** (wejscia, logowania, adresy) |
| `Wylacz autostart.bat` | cofa autostart |

> Pelna sciezka: zacznij od `START-TUTAJ.txt`.

### Kod QR do udostepniania
Po starcie wersji wspolnej powstaje strona `UDOSTEPNIJ-PRACOWNIKOM.html` z linkiem,
haslem (przyciski „Kopiuj") i **kodem QR** — pracownik moze go po prostu zeskanowac
telefonem. Kod QR generowany jest lokalnie, nic nie jest wysylane na zewnatrz.

### Raport „kto sie laczyl"
Brama zapisuje kazde wejscie i logowanie do `logs\access.log` (anonimowo: adres IP +
czas, bez danych osobowych). Plik `6 - Pokaz kto sie laczyl.bat` tworzy z tego ladny
`RAPORT-POLACZEN.html`: liczba wejsc, logowan, unikalne adresy i ostatnie zdarzenia.

---

## Jak to dziala (w skrocie)

```
            WERSJA WSPOLNA (pracownicy)              WERSJA PRYWATNA (tylko Ty)

  pracownik --HTTPS--> Cloudflare ----+        Ty (telefon/laptop, Tailscale)
                                      |                      |
                                      v                      v  (prywatna siec)
                            [ Brama: haslo ]  <----  [ Tailscale Serve, HTTPS ]
                                      |                      |
                                      +-------> Twoje narzedzie (localhost) <----+
```

Brama nasluchuje tylko lokalnie (`127.0.0.1`). Na swiat nie wystawia jej router,
tylko tunel (Cloudflare) albo prywatna siec (Tailscale). Twoja siec domowa
pozostaje zamknieta.

---

## Wymagania

- Windows 10/11
- [Node.js LTS](https://nodejs.org) (setup pomoze zainstalowac)
- Twoje narzedzie webowe dzialajace lokalnie (np. `http://127.0.0.1:3000`)

---

## Instalacja (raz)

W PowerShell, w katalogu projektu:

```powershell
.\scripts\setup.ps1
```

Skrypt:
1. sprawdzi Node.js,
2. zainstaluje zaleznosci,
3. utworzy `.env` i **wygeneruje mocne haslo** oraz sekret sesji,
4. pobierze `cloudflared.exe`.

Nastepnie wpisz adres swojego narzedzia w pliku `.env`:

```ini
UPSTREAM_URL=http://127.0.0.1:3000
```

> Jesli zostawisz `UPSTREAM_URL` puste, brama pokaze strone powitalna —
> przydatne do pierwszego testu.

---

## Wersja WSPOLNA — udostepnij pracownikom

```powershell
.\scripts\run.ps1
```

Po chwili w oknie pojawi sie **link i haslo**, np.:

```
   Link  : https://losowe-slowa.trycloudflare.com
   Haslo : Xy7k-Qm2p-9Rt
```

To samo zapisze sie w pliku **`share-info.txt`** — wyslij go (albo sam link + haslo)
pracownikom. Otwieraja link, wpisuja haslo i korzystaja z narzedzia.

### Staly adres (opcjonalnie)
W trybie szybkim adres `trycloudflare.com` zmienia sie po restarcie. Aby miec
**staly adres na wlasnej domenie**:
1. zaloz darmowe konto na [Cloudflare](https://dash.cloudflare.com),
2. Zero Trust → Networks → Tunnels → *Create tunnel*,
3. skopiuj **token** tunelu i wklej do `.env`:
   ```ini
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...twoj-token...
   ```
4. w panelu tunelu ustaw Public Hostname → Service: `http://127.0.0.1:8080`.

Od teraz `run.ps1` uzyje stalego adresu Twojej domeny.

---

## Wersja PRYWATNA — tylko Ty, zdalnie z domu

```powershell
.\scripts\run-private.ps1
```

Skrypt:
1. zainstaluje/uruchomi **Tailscale** (prywatna siec mesh),
2. zaloguje maszyne **Twoim kontem** (raz, przez przegladarke),
3. udostepni narzedzie **wylacznie w Twojej sieci** (Tailscale Serve, HTTPS).

Adres prywatny (typu `https://twoj-pc.twoj-tailnet.ts.net`) zapisze sie w pliku
**`private-access.txt`**.

Aby laczyc sie z domu / w podrozy:
1. na telefonie lub laptopie zainstaluj Tailscale i zaloguj sie **tym samym kontem**,
2. otworz adres prywatny,
3. wpisz haslo — masz pelna kontrole nad narzedziem zdalnie.

Narzedzie **nie jest widoczne publicznie** ani w wyszukiwarkach. Dostep ma
wylacznie Twoje konto i urzadzenia, ktore do niego dodasz.

---

## Wersja URZADZENIE — udostepnij sprzet (np. interfejs OBD2) w terenie

Gdy chcesz dosiegnac nie strony, lecz **urzadzenia sieciowego** stojacego w domu
(np. bezprzewodowy interfejs diagnostyczny OBD2), uzyj:

```powershell
.\scripts\run-device.ps1
```

albo pliku **`7 - Udostepnij urzadzenie w terenie.bat`**.

Wczesniej ustaw w `.env`:

```ini
DEVICE_HOST=192.168.0.50   # adres urzadzenia w domowej sieci (lub 127.0.0.1)
DEVICE_PORT=35000          # port urzadzenia (dla adapterow WiFi OBD czesto 35000)
```

Jak to dziala: na serwerze startuje **most TCP** (`src/tcp-bridge.js`), ktory
przekazuje ruch do urzadzenia, a **Tailscale** udostepnia ten port wylacznie
w Twojej prywatnej sieci. W terenie laczysz sie programem diagnostycznym pod
adres Tailscale serwera i podany port — tak, jakbys stal obok urzadzenia.

```
[program diagnostyczny w terenie] --(Tailscale)--> [most TCP na serwerze] --> [OBD2 w domu]
```

Adres do wpisania w programie zapisuje sie w pliku **`DOSTEP-URZADZENIE.txt`**.

> Uwaga: surowy port TCP wymaga **Tailscale** (nie dziala przez darmowy tunel
> Cloudflare, ktory obsluguje tylko HTTP/strony).

---

## Pelna autonomia — start z Windows

Aby serwer uruchamial sie **sam po kazdym zalogowaniu** i sam wstawal po awarii:

```powershell
# wersja wspolna (pracownicy):
.\scripts\install-autostart.ps1

# wersja prywatna (tylko Ty):
.\scripts\install-autostart.ps1 -Mode private
```

Uruchomienie od razu, bez restartu:
```powershell
Start-ScheduledTask -TaskName KluczykiPoznan          # wspolna
Start-ScheduledTask -TaskName KluczykiPoznanPrivate   # prywatna
```

Wylaczenie autostartu:
```powershell
.\scripts\uninstall-autostart.ps1
```

---

## Konfiguracja (`.env`)

| Klucz | Znaczenie |
|---|---|
| `PORT` | port lokalny bramy (domyslnie 8080) |
| `UPSTREAM_URL` | adres Twojego narzedzia, np. `http://127.0.0.1:3000` |
| `STATIC_DIR` | alternatywnie: folder z plikami do serwowania |
| `ACCESS_PASSWORD` | wspolne haslo dostepu (generowane automatycznie) |
| `SESSION_SECRET` | sekret podpisu sesji (generowany automatycznie) |
| `SESSION_TTL_HOURS` | jak dlugo wazna jest sesja po zalogowaniu |
| `CLOUDFLARE_TUNNEL_TOKEN` | token dla stalego adresu (opcjonalnie) |

Plik `.env` jest prywatny — nie trafia do gita i nie opuszcza Twojego komputera.

---

## Bezpieczenstwo

- Brama nasluchuje tylko na `127.0.0.1` — nie wystawiamy nic bezposrednio do internetu.
- Caly ruch zewnetrzny idzie przez **HTTPS** (Cloudflare / Tailscale).
- Haslo porownywane odpornie na ataki czasowe; limit prob logowania chroni przed zgadywaniem.
- Naglowek `X-Robots-Tag: noindex` — serwis nie trafia do wyszukiwarek.
- **Router pozostaje nietkniety** — brak otwartych portow, brak ryzyka wystawienia sieci domowej.

> Uwaga prawna: udostepniajac narzedzie pracownikom upewnij sie, ze masz do tego
> prawo (licencja narzedzia) i ze konfiguracja jest zgodna z polityka Twojej firmy.

---

## Rozwiazywanie problemow

| Problem | Rozwiazanie |
|---|---|
| `502 - narzedzie niedostepne` | Twoje narzedzie nie dziala lub zly `UPSTREAM_URL`. Uruchom narzedzie i sprawdz adres. |
| Brak linku w `run.ps1` | Zajrzyj do `logs\cloudflared.log`. Sprawdz polaczenie z internetem. |
| Tailscale nie laczy | Uruchom `tailscale status`; zaloguj sie ponownie `tailscale up`. |
| Zmienil sie adres trycloudflare | To normalne w trybie szybkim — uzyj `CLOUDFLARE_TUNNEL_TOKEN` dla stalego adresu. |

Logi znajdziesz w folderze `logs\`.
