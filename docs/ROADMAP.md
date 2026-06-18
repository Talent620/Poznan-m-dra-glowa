# Roadmapa rozwoju

Szacunki orientacyjne (zespół 2–3 os.). Każdy kamień milowy = działający, przetestowany przyrost.

| Milestone | Zakres | Główne rezultaty | Szac. |
|---|---|---|---|
| **M0 — Fundament** ✅ rozpoczęte | docs + `platform/` scaffold | architektura, schema.sql, openapi, compose, interfejs konektora | 1–2 tyg |
| **M1 — Control Plane MVP** | NestJS + Postgres | RBAC, JWT+refresh, MFA(TOTP), tenants/users/devices/sessions, audit_log, migracje, testy e2e | 4–6 tyg |
| **M2 — Data Plane v2** | Relay (Go) + Edge/Client Agent (konektor TCP) | bezstanowy relay, Redis presence, resume token, failover, mTLS; parytet z v1 dla sieci | 4–6 tyg |
| **M3 — Web + tryby A–D** | Next.js dashboard | logowanie/MFA, zarządzanie, sesje live, link/QR/kod (Tryb C), eksport CSV/PDF, tryby A/B/C/D | 4–6 tyg |
| **M4 — Konektory sprzętowe** | serial→usbip→j2534→socketcan | wirtualne urządzenia klienckie; zgodność z OpenPort2/VAS6154/CANcase; testy na sprzęcie | 8–12 tyg |
| **M5 — Licencje + automatyzacja** | moduł licencji + API/webhooki | licencje lokalne/sieciowe/token/klucz, webhooki HMAC, integracja CRM/serwis | 3–5 tyg |
| **M6 — Skala + hardening + GA** | obciążenia, HA, monitoring | SLO 100 urz./1000 sesji, Grafana, IP allow-list, rate-limit, runbooki, pen-test | 4–6 tyg |

## Szybkie wygrane (równolegle, niskie ryzyko)
1. CI (GitHub Actions): `npm test` v1 na każdy push — **mogę zrobić od razu**.
2. Zabezpieczenie mostu TCP v1 (decyzja D1 z `AUDIT.md`) — bind do Tailscale / pre-shared key.
3. Licznik aktywnych sesji w panelu v1.

## Kamienie pod „uniwersalną kompatybilność"
Kolejność konektorów dobrana wg pokrycia rynku i trudności:
`tcp` (ELM327/ENET/DoIP/VAS6154-LAN) → `serial` (FORScan/ELS27/część KESS) →
`usbip` (dowolny dongle) → `j2534` (ODIS/Xentry/HDS/Techstream z PassThru) → `socketcan` (CAN/CAN FD).

## Definicja sukcesu GA
ODIS/Xentry/VCDS/FORScan łączą się **bez modyfikacji** ze zdalnym urządzeniem (sieciowym wprost,
USB/J2534/CAN przez wirtualne urządzenie klienckie), przy SLO wydajności, z RBAC/MFA/Audit/licencjami,
panelem i automatyzacją — a platforma **nie narusza** licencji cudzego oprogramowania.
