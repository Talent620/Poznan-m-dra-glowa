-- ============================================================================
--  Platforma zdalnego dostepu diagnostycznego - schemat PostgreSQL (v2)
--  Wielodostepowy (multi-tenant), z RBAC, sesjami, audytem i licencjami.
--  Uruchom na PostgreSQL >= 15.  (Docelowo zarzadzane migracjami Prisma/SQL.)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid()

-- --- Organizacje (najemcy) --------------------------------------------------
CREATE TABLE tenants (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  mode         TEXT NOT NULL DEFAULT 'private'      -- private|worker|client|workshop (Tryb A/B/C/D)
                 CHECK (mode IN ('private','worker','client','workshop')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- Uzytkownicy + role (RBAC) ----------------------------------------------
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email         CITEXT NOT NULL,
  password_hash TEXT NOT NULL,                       -- argon2id
  mfa_secret    TEXT,                                -- TOTP (szyfrowane w spoczynku)
  mfa_enabled   BOOLEAN NOT NULL DEFAULT false,
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, email)
);

CREATE TABLE roles (
  id     TEXT PRIMARY KEY,                            -- owner|admin|manager|worker|client|viewer
  rank   INT  NOT NULL                                -- do porownan uprawnien
);
INSERT INTO roles(id,rank) VALUES
  ('owner',100),('admin',80),('manager',60),('worker',40),('client',20),('viewer',10);

CREATE TABLE user_roles (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id TEXT NOT NULL REFERENCES roles(id),
  PRIMARY KEY (user_id, role_id)
);

-- --- Agenci (host urzadzenia / stanowisko klienta) --------------------------
CREATE TABLE agents (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('edge','client')),  -- host vs stanowisko
  name         TEXT NOT NULL,
  cert_fingerprint TEXT,                              -- mTLS
  last_seen_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- Urzadzenia diagnostyczne ----------------------------------------------
CREATE TABLE devices (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  agent_id     UUID REFERENCES agents(id) ON DELETE SET NULL,
  name         TEXT NOT NULL,
  connector    TEXT NOT NULL CHECK (connector IN ('tcp','udp','serial','usbip','j2534','socketcan')),
  config       JSONB NOT NULL DEFAULT '{}',           -- host:port / COMx / vid:pid / kanal CAN
  online       BOOLEAN NOT NULL DEFAULT false,
  busy         BOOLEAN NOT NULL DEFAULT false,        -- 1 klient / 1 urzadzenie (konfig.)
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON devices(tenant_id);

-- --- Sesje (klient <-> urzadzenie) ------------------------------------------
CREATE TABLE sessions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  device_id    UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  client_agent UUID REFERENCES agents(id) ON DELETE SET NULL,
  state        TEXT NOT NULL DEFAULT 'pending'        -- pending|active|resumed|closed|error
                 CHECK (state IN ('pending','active','resumed','closed','error')),
  resume_token TEXT,                                  -- wznawianie po failover
  bytes_up     BIGINT NOT NULL DEFAULT 0,
  bytes_down   BIGINT NOT NULL DEFAULT 0,
  rtt_ms       INT,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at     TIMESTAMPTZ
);
CREATE INDEX ON sessions(tenant_id, started_at DESC);
CREATE INDEX ON sessions(device_id);

CREATE TABLE session_events (
  id         BIGSERIAL PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
  type       TEXT NOT NULL,                           -- open|resume|reconnect|throttle|close|error
  detail     JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX ON session_events(session_id, ts);

-- --- Kody dostepu dla klienta (Tryb C): link + QR + kod ---------------------
CREATE TABLE access_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  device_id  UUID REFERENCES devices(id) ON DELETE CASCADE,
  code       TEXT NOT NULL UNIQUE,                    -- krotki kod dostepu / w QR
  scope      JSONB NOT NULL DEFAULT '{}',             -- co wolno
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- Licencje platformy (NIE dotyczy licencji obcego oprogramowania!) --------
CREATE TABLE licenses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('local','network','token','activation_key')),
  key         TEXT NOT NULL,
  seats       INT  NOT NULL DEFAULT 1,                -- limit stanowisk/urzadzen
  valid_from  TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_until TIMESTAMPTZ,
  revoked     BOOLEAN NOT NULL DEFAULT false,
  metadata    JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX ON licenses(tenant_id);

-- --- Audit Log (append-only, hash-chain dla niezmienialnosci) ---------------
CREATE TABLE audit_log (
  id         BIGSERIAL PRIMARY KEY,
  tenant_id  UUID REFERENCES tenants(id) ON DELETE SET NULL,
  user_id    UUID REFERENCES users(id) ON DELETE SET NULL,
  ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
  action     TEXT NOT NULL,                           -- login.success, device.share, session.open...
  target     TEXT,
  ip         INET,
  detail     JSONB NOT NULL DEFAULT '{}',
  prev_hash  TEXT,                                    -- hash poprzedniego wpisu
  hash       TEXT NOT NULL                            -- sha256(prev_hash || tresc)
);
CREATE INDEX ON audit_log(tenant_id, ts DESC);

-- --- Webhooki (automatyzacja / CRM) -----------------------------------------
CREATE TABLE webhooks (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  url        TEXT NOT NULL,
  secret     TEXT NOT NULL,                           -- do podpisu HMAC
  events     TEXT[] NOT NULL DEFAULT '{}',
  active     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE api_keys (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  hash        TEXT NOT NULL,                          -- przechowujemy tylko hash klucza
  scopes      TEXT[] NOT NULL DEFAULT '{}',
  last_used   TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ip_allow_list (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  cidr       CIDR NOT NULL,
  note       TEXT
);

-- Uwaga: izolacja tenantow dodatkowo przez Row-Level Security (RLS) w aplikacji.
