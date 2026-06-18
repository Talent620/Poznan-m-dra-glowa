# platform/ — fundament wersji enterprise (v2)

To **szkielet** docelowej platformy (Milestone M0). NIE jest jeszcze działającą aplikacją —
zawiera kontrakty, schemat bazy i infrastrukturę, na których budujemy kolejne milestone'y.
Pełny plan: `../docs/ARCHITECTURE.md`, `../docs/MIGRATION.md`, `../docs/ROADMAP.md`.

## Co już jest (M0)
- `db/schema.sql` — pełny schemat PostgreSQL (tenants, users/RBAC, devices, sessions,
  access_tokens, licenses, audit_log, webhooks, api_keys, ip_allow_list).
- `src/connectors/connector.ts` — kontrakt warstwy konektorów (transport urządzenia).
- `src/connectors/tcp.ts` — referencyjny konektor TCP (logika z v1 w nowym kontrakcie).
- `openapi.yaml` — szkic kontraktu REST control-plane.
- `deploy/docker-compose.yml` — Postgres + Redis do developmentu.
- `.env.example` — konfiguracja.

## Czego jeszcze NIE ma (kolejne milestone'y)
- `apps/control-plane` (NestJS: RBAC/MFA/JWT/audyt) — **M1**
- `apps/relay` + `apps/edge-agent` + `apps/client-agent` (Go, data-plane) — **M2**
- `apps/web` (Next.js dashboard, tryby A–D, eksport CSV/PDF) — **M3**
- konektory `serial/usbip/j2534/socketcan` + wirtualne urządzenia klienckie — **M4**

## Najważniejsze ograniczenie (czytaj `../docs/ENTERPRISE-AUDIT.md` §0)
„Bez modyfikacji programu diagnostycznego" działa **wprost tylko dla urządzeń sieciowych**
(TCP/UDP). USB / Serial / J2534 / sprzętowy CAN wymagają **wirtualnego urządzenia po stronie
klienta** (usbip / wirtualny COM / shim J2534 / vcan). To osobny, duży etap (M4).

## Start (gdy powstaną aplikacje)
```bash
docker compose -f platform/deploy/docker-compose.yml up -d   # Postgres + Redis
# nast.: budowa apps/* wg roadmapy
```
