# PROGRESS — Kluczyki Poznań mądra głowa

## Faza 1 — audyt
- [x] Przegląd całego kodu (Node + PowerShell + .bat + widoki)
- [x] `AUDIT.md` zapisany (mapa, ryzyka R1–R10, propozycje P1–P6, decyzje D1–D3)

## Faza 2 — wdrożenie bezpiecznych poprawek
- [x] P1 (R1) — `obd-ws.clientIp()` odporny na spoofing XFF (CF-Connecting-IP / prawy hop)
- [x] P2 (R6) — zestaw testów `test/run.js` + `npm test` (**29 testów, wszystkie zielone**)
- [x] P3 (R4) — `run.ps1` regeneruje stronę QR przy nowym adresie tunelu
- [x] P4 (R3) — `run.ps1` `$args` → `$cfArgs`
- [x] P5 (R7) — `.gitignore`: `WYNIK-DIAGNOZY.txt`
- [x] P6 (R5) — `run-obd.ps1` nie zapisuje hasła na dysk (tylko link)

## DO DECYZJI (nie wdrażam)
- D1 — most TCP `tcp-bridge.js` bez auth na `0.0.0.0`
- D2 — rebranding `reklama-*` → `kluczyki-*`
- D3 — auto-reconnect tunelu w `obd-client`

## Faza 3 — podsumowanie

### Co naprawiono/ulepszono w tej sesji (Faza 2)
- Dodano **29 testów** (`npm test`) — pierwsza siatka bezpieczeństwa przeciw regresjom.
- Utwardzono **lockout** przeciw podrabianiu adresu IP (`obd-ws.js`).
- Naprawiono **stary kod QR** po zmianie adresu tunelu (`run.ps1`).
- Usunięto **kolizję `$args`** w `run.ps1`.
- `run-obd.ps1` **nie trzyma już hasła** na dysku mechanika.
- Domknięto `.gitignore` (`WYNIK-DIAGNOZY.txt`).
- (Wcześniejsze fazy: klucz w nagłówku, lockout `/obd`, dynamiczne `Secure`, CSRF,
  keep-alive, walidacja `.env`, `EADDRINUSE`, kreator „jedno kliknięcie", auto-test adaptera.)

### Do mojej decyzji (nie wdrożone — patrz AUDIT.md sekcja 4)
- **D1** — most TCP `tcp-bridge.js` bez autoryzacji na `0.0.0.0` (zmiana zachowania sieci).
- **D2** — rebranding `reklama-*` → `kluczyki-*` (zmiana ciasteczka wyloguje sesje).
- **D3** — auto-reconnect tunelu w `obd-client` (ryzyko dla stanu sesji ELM327).

### TOP 5 następnych kroków (wg priorytetu)
1. **D1** — zabezpieczyć most TCP (bind do adresu Tailscale lub pre-shared key). Bezpieczeństwo.
2. **CI (GitHub Actions)** — `npm ci && npm test` na każdy push/PR. Utrzymanie.
3. **Panel WWW: licznik aktywnych sesji OBD** (kto teraz diagnozuje). UX/diagnostyka.
4. **Auto-test po stronie mechanika** — „połączono z autem" (zielone) zaraz po starcie.
5. **D2 rebranding** + ujednolicenie nazw (`reklama` → `kluczyki`). Czytelność.

---

## Blueprint enterprise (v2) — Faza M0 (fundament)

Na życzenie „przebuduj do wersji produkcyjnej klasy enterprise" dostarczono **kompletny projekt
produkcyjny + szkielet fundamentu** (pełny kod to build etapowy wg roadmapy — nie jednorazowa
generacja). Pliki:
- `docs/ENTERPRISE-AUDIT.md` — audyt enterprise, lista luk E1–E12, prawda o transporcie (USB/J2534).
- `docs/ARCHITECTURE.md` — architektura (control/data plane, Go+NestJS, konektory, tryby A–D,
  bezpieczeństwo TLS/MFA/RBAC/audyt, monitoring, skala/failover, model danych).
- `docs/MIGRATION.md` — struktura katalogów + migracja strangler-fig (Fazy 0–6).
- `docs/ROADMAP.md` — kamienie M0–M6 z szacunkami.
- `platform/` — szkielet: `db/schema.sql`, `src/connectors/{connector,tcp}.ts`, `openapi.yaml`,
  `deploy/docker-compose.yml`, `.env.example`, `README.md`.

**Status:** M0 gotowy. Następny rekomendowany krok do implementacji: **M1 (Control Plane MVP:
NestJS + Postgres + RBAC/MFA/JWT)** — lub szybka wygrana: **CI dla v1**.

**Kluczowe ograniczenie (do świadomej akceptacji):** „dowolne oprogramowanie bez modyfikacji"
działa wprost tylko dla urządzeń **sieciowych**; USB/Serial/J2534/CAN wymagają **wirtualnego
urządzenia klienckiego** (M4) — szczegóły w `docs/ENTERPRISE-AUDIT.md §0`.
