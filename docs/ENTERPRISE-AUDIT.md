# Enterprise Audit & Gap Analysis — Platforma Zdalnego Dostępu Diagnostycznego

Data: 2026-06-18 · Autor: senior architekt · Status: blueprint produkcyjny

> **Uczciwa ocena zakresu.** To, o co prosisz (uniwersalna platforma SaaS dla 100+ urządzeń,
> RBAC/MFA, Postgres/Redis/gRPC, frontend Next.js, konektory USB/Serial/J2534/CAN, monitoring,
> webhooki/CRM, failover) to **produkt wieloosobowy budowany etapami przez miesiące**, a nie
> jednorazowa generacja. Ten dokument + `ARCHITECTURE.md` + `MIGRATION.md` + `ROADMAP.md` to
> **kompletny projekt produkcyjny i szkielet fundamentu** (`platform/`). Pełny kod powstaje
> według roadmapy — każda część osobno: zaprojektowana, zaimplementowana, przetestowana.

---

## 0. Najważniejsza prawda techniczna (czytaj najpierw)

Hasło „uniwersalna kompatybilność z **dowolnym** programem **bez modyfikacji**" jest **w pełni
osiągalne tylko dla urządzeń sieciowych** (TCP/UDP). Dla USB / Serial COM / J2534 / sprzętowego
CAN **sam tunel WebSocket NIE wystarczy** — trzeba po stronie klienta odtworzyć **wirtualne
urządzenie lokalne**. To nie jest opcja, to fizyka transportu:

| Klasa urządzenia/protokołu | Transport „na drucie" | Zdalne przez tunel? | Co jest potrzebne |
|---|---|---|---|
| ELM327 WiFi (OBD2), ENET (BMW), DoIP/13400, VAS6154 (LAN), VXDIAG (sieć) | **TCP** | ✅ wprost | raw TCP ⇄ WebSocket (mamy to dziś) |
| DoIP discovery | UDP 13400 (broadcast) | ⚠️ częściowo | ręczne IP **lub** relay UDP; sesja UDS i tak po TCP |
| J2534 / PassThru (OpenPort 2.0, Mongoose, VXDIAG USB, VAS6154 USB) | **USB + DLL producenta** | ❌ nie wprost | **zdalny shim J2534 DLL** (RPC do hosta urządzenia) **albo USB-over-IP (usbip)** |
| Serial COM (część KESS/KTAG, ELS27 USB, FORScan kabel) | **USB-CDC / COM** | ❌ nie wprost | **wirtualny COM** (com0com) + most serial⇄WS **albo USB-over-IP** |
| SocketCAN, CANcase, CAN FD sprzętowy | **kontroler CAN** | ❌ nie wprost | **CAN-over-IP** (socketcand / cannelloni) + wirtualny interfejs CAN |
| USB ogólnie (dowolny dongle) | **USB** | ❌ nie wprost | **USB-over-IP** (usbipd-win na hoście, klient usbip) + sterowniki |

**Wniosek architektoniczny:** platforma musi mieć **warstwę konektorów (pluginów transportu)**
po stronie hosta urządzenia **oraz** odpowiadające im **wirtualne urządzenia** po stronie
klienta. „Bez modyfikacji programu diagnostycznego" = program widzi lokalny `127.0.0.1:port`,
wirtualny `COMx`, wirtualny J2534 DLL albo wirtualny interfejs CAN — a nie zdalny adres.

To rozróżnienie jest sercem nowej architektury i powodem, dla którego dzisiejszy „jeden plik
WebSocket" pokrywa ~30% wymaganej macierzy urządzeń (część sieciową) i musi zostać rozbudowany.

---

## 1. Audyt stanu obecnego (co mamy)

Obecny projekt (`src/`, `scripts/`) to **dobrze zrobione narzędzie jednozadaniowe**: most
**TCP ⇄ WebSocket** dla **sieciowych** adapterów OBD, z logowaniem wspólnym hasłem, lockoutem,
tunelem Cloudflare/Tailscale, kreatorem dla laików i 29 testami. Po ostatnich fazach jest
**bezpieczne i stabilne w swojej klasie**.

**Mocne strony (do zachowania w v2):**
- Sprawdzony, niskolatencyjny relay raw-bytes (TCP_NODELAY, brak kompresji, keep-alive, 1‑klient/1‑urządzenie, heartbeat).
- Realne UX dla nietechnicznych (kreator, QR, auto-test adaptera).
- Dwie drogi tunelowania (Cloudflare quick + Tailscale).

## 2. Lista błędów / luk względem klasy enterprise

| # | Luka | Obecnie | Wymóg enterprise |
|---|---|---|---|
| E1 | **Model tożsamości** | jedno wspólne hasło, brak kont | użytkownicy, **role (RBAC)**, **MFA**, JWT, tenant/organizacja |
| E2 | **Trwałość** | stan w pamięci + pliki `.txt`/`.log` | **PostgreSQL** (urządzenia, sesje, audyt, licencje) |
| E3 | **Skala/HA** | 1 proces, 1 klient/urządzenie | **wiele instancji**, Redis pub/sub, **failover**, resume sesji |
| E4 | **Macierz urządzeń** | tylko TCP | **+ USB/Serial/J2534/CAN** (konektory + wirtualne urządzenia) |
| E5 | **Tryby pracy** | „pracownicy/prywatny/urządzenie" ad hoc | **A/B/C/D** jako pierwszorzędne tryby z politykami |
| E6 | **Licencjonowanie** | brak | **moduł licencji** platformy (lokalne/sieciowe/token/klucz) |
| E7 | **Monitoring** | log + raport HTML | **dashboard**: sesje, urządzenia, przepustowość, latencja; **eksport CSV/PDF** |
| E8 | **Automatyzacja** | brak | **REST API**, **webhooki**, integracja CRM/serwis |
| E9 | **Audyt** | `access.log` (IP+czas) | **Audit Log** strukturalny, niezmienialny, per-akcja/per-user |
| E10 | **Bezpieczeństwo transportu** | most TCP `0.0.0.0` bez auth (tryb Tailscale) | mTLS/uwierzytelniony kanał danych, IP allow-list, rate limit globalny |
| E11 | **Frontend** | statyczne strony HTML | **Next.js + React + TypeScript** (panel zarządzania) |
| E12 | **Wieloplatformowość agenta** | skrypty `.bat`/PowerShell (tylko Windows) | **agent** Win/Linux/mac (host i klient) |

## 3. Ryzyka i decyzje projektowe

- **Backend Go vs Node.** Rekomendacja: **Go** dla **data-plane** (relay/agent — wydajność,
  goroutines, jeden statyczny binarny agent na Win/Linux/mac) i **Node/TypeScript (NestJS)** dla
  **control-plane** (API/RBAC/DB) — szybkość developmentu + wspólny TS z frontendem. Alternatywa:
  całość w Go. Decyzja w `ARCHITECTURE.md` §Backend.
- **„Bez modyfikacji programu"** wymaga sterowników klienckich (usbip/com0com/J2534 shim) — to
  **instalacja po stronie klienta** i kwestie **podpisu sterowników na Windows**. Ujęte w roadmapie.
- **Legalność/licencje cudzego oprogramowania.** Platforma zarządza **wyłącznie własną** licencją
  i **nie obchodzi** zabezpieczeń programów diagnostycznych (dongle/aktywacja) — zasada twarda,
  zapisana w kodzie i dokumentach (zgodnie z dotychczasowym podejściem).

## 4. Definicja „gotowe" dla wersji enterprise (skrót)
Wieloinstancyjny control-plane (Postgres+Redis) + bezstanowe relay + agenci host/klient z
konektorami (TCP→USB/Serial/J2534/CAN etapami) + RBAC/MFA/JWT + Audit + licencje + dashboard z
eksportem + REST/webhooki + tryby A–D + tunelowanie Tailscale/Cloudflare/WireGuard, z testami,
CI i SLO (100 urządzeń / 1000 sesji dziennie, auto-recovery, failover).
