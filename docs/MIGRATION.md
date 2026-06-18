# Plan migracji v1 → v2 (strangler-fig, bez przerywania działania)

Zasada: **nie wyłączamy działającego narzędzia**. v1 (`src/`, `scripts/`) zostaje produkcyjny i
obsługuje urządzenia sieciowe, a v2 (`platform/`) rośnie obok, przejmując ruch etapami. Gdy
moduł v2 jest gotowy i przetestowany, kierujemy do niego część ruchu (feature flag), aż v1
stanie się cienkim „konektorem TCP" wewnątrz Edge Agenta v2.

---

## 1. Docelowa struktura katalogów (monorepo)

```
repo/
├─ legacy/                      # dotychczasowe v1 (przeniesione z src/ i scripts/)
│  ├─ src/                      # most TCP⇄WS, działa nadal (tryb sieciowy)
│  └─ scripts/                  # .bat / PowerShell (kreator, tunele)
│
├─ platform/                    # v2 — rdzeń enterprise
│  ├─ apps/
│  │  ├─ control-plane/         # NestJS: REST + gRPC + WS, RBAC/MFA/JWT, licencje, audyt
│  │  │  ├─ src/{auth,rbac,tenants,devices,sessions,licenses,audit,webhooks,billing}/
│  │  │  └─ test/
│  │  ├─ relay/                 # Go: data-plane broker (raw bytes), Redis presence
│  │  ├─ edge-agent/            # Go: host urządzenia (konektory)
│  │  ├─ client-agent/          # Go: wirtualne urządzenie lokalne
│  │  └─ web/                   # Next.js + React + TS (dashboard)
│  ├─ packages/
│  │  ├─ proto/                 # definicje gRPC/protobuf (kontrakt control↔data)
│  │  ├─ sdk-ts/                # klient TS REST/WS (web + integracje)
│  │  └─ shared/                # typy, schematy walidacji (zod), stałe
│  ├─ src/connectors/           # interfejs + implementacje konektorów (TS ref + Go)
│  ├─ db/                       # schema.sql, migracje (Prisma/SQL)
│  ├─ deploy/                   # docker-compose, k8s, helm, terraform
│  ├─ openapi.yaml              # kontrakt REST
│  └─ .env.example
│
├─ docs/                        # ENTERPRISE-AUDIT, ARCHITECTURE, MIGRATION, ROADMAP
└─ .github/workflows/           # CI: lint, test, build, e2e
```

> Na tym etapie tworzymy `platform/` jako **szkielet fundamentu** (interfejsy, schema, kontrakt,
> compose). Pełne aplikacje powstają wg roadmapy. v1 NIE jest jeszcze przenoszony do `legacy/` —
> robimy to w M1, żeby nie zepsuć działającego narzędzia w trakcie.

---

## 2. Fazy migracji

### Faza 0 — Fundament (TERAZ)
- Dokumentacja (ten zestaw), `platform/` scaffold: interfejs konektora, `schema.sql`,
  `openapi.yaml`, `docker-compose` (Postgres+Redis), `.env.example`. v1 działa bez zmian.

### Faza 1 — Control Plane MVP + Postgres
- NestJS: tenants/users/roles (RBAC), JWT+refresh, MFA(TOTP), devices, sessions (CRUD+stany),
  audit_log. Migracje DB. Testy jednostkowe+e2e. Bez zmian w ścieżce danych (nadal v1 relay).

### Faza 2 — Relay (Go) + Edge/Client Agent (konektor TCP)
- Przeniesienie sprawdzonej logiki TCP⇄WS z v1 do Go Agentów + bezstanowy Relay (Redis presence,
  resume token). Feature flag: część urządzeń sieciowych przez v2. v1 jako fallback.

### Faza 3 — Frontend Next.js + Dashboard + tryby A–D
- Panel: logowanie/MFA, zarządzanie userami/rolami, urządzenia, sesje na żywo, link/QR/kod dla
  klienta (Tryb C), eksport CSV/PDF. Wyłączenie starych stron HTML v1.

### Faza 4 — Konektory USB/Serial/J2534/CAN + wirtualne urządzenia klienckie
- `serial`(COM)→`usbip`→`j2534` shim→`socketcan`. Każdy z testem zgodności na realnym sprzęcie.
  To największy i najtrudniejszy etap (sterowniki, podpisy Win).

### Faza 5 — Automatyzacja + skalowanie + hardening
- Webhooki, integracje CRM, IP allow-list, rate-limit globalny, mTLS rotacja, metryki/Grafana,
  testy obciążeniowe do SLO (100 urządzeń / 1000 sesji), failover, runbooki.

### Faza 6 — Wygaszenie v1
- Gdy konektor TCP v2 pokrywa 100% przypadków v1 → `legacy/` tylko awaryjnie, potem usunięcie.

---

## 3. Strategia danych
- Brak danych produkcyjnych do migracji w v1 (stan ulotny + pliki). „Migracja" = nowy model w
  Postgres od zera. Historia `access.log` opcjonalnie importowana do `audit_log` jednorazowym ETL.

## 4. Strategia ryzyka
- Każda faza za **feature flag** + możliwość natychmiastowego powrotu do v1.
- Twarde bramki jakości: testy + przegląd bezpieczeństwa przed kierowaniem ruchu produkcyjnego.
- Sprzęt: konektory USB/J2534/CAN walidowane na fizycznych urządzeniach z listy (AIR OBD2,
  OpenPort 2.0, VAS6154, ENET, CANcase) — bez tego nie uznajemy etapu za ukończony.
