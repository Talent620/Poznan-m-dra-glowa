'use strict';

/**
 * REJESTR URZADZEN OBD
 * ----------------------------------------------------------------------------
 * Pozwala udostepnic WIELE urzadzen (np. kilka adapterow OBD / kilka aut /
 * kilka lokalizacji) przez jeden link. Kazde urzadzenie ma nazwe, adres i port.
 *
 * Konfiguracja w .env - dwa sposoby (mozna laczyc):
 *
 *  1) Wiele urzadzen w jednej linii (rozdzielone srednikiem):
 *       DEVICES=warsztat1=192.168.0.10:35000; warsztat2=192.168.0.11:35000
 *
 *  2) Jedno urzadzenie "po staremu" (zgodnosc wstecz):
 *       DEVICE_HOST=192.168.0.10
 *       DEVICE_PORT=35000
 *       DEVICE_NAME=domyslne        (opcjonalnie - domyslnie "domyslne")
 *
 * Nazwy urzadzen sa oczyszczane do [A-Za-z0-9_-], zeby bezpiecznie przechodzily
 * w adresie (?device=...). Pierwsze urzadzenie na liscie jest domyslne.
 */

function sanitizeName(raw, fallback) {
  const n = String(raw || '').trim().replace(/[^A-Za-z0-9_-]/g, '-').replace(/^-+|-+$/g, '');
  return n || fallback;
}

function parseList() {
  const out = [];
  const seen = new Set();

  function add(name, host, port) {
    const p = parseInt(port, 10);
    if (!Number.isInteger(p) || p <= 0 || p > 65535) return;
    let nm = sanitizeName(name, `urzadzenie${out.length + 1}`);
    // Unikalne nazwy - dopisujemy numer w razie kolizji.
    let base = nm, i = 2;
    while (seen.has(nm.toLowerCase())) { nm = `${base}-${i++}`; }
    seen.add(nm.toLowerCase());
    out.push({ name: nm, host: String(host || '127.0.0.1').trim(), port: p });
  }

  // 1) DEVICES=name=host:port; name2=host2:port2
  const raw = (process.env.DEVICES || '').trim();
  if (raw) {
    for (const part of raw.split(/[;\n]+/)) {
      const item = part.trim();
      if (!item) continue;
      // name=host:port  albo  host:port (bez nazwy)
      let name = '', hostPort = item;
      const eq = item.indexOf('=');
      if (eq !== -1) { name = item.slice(0, eq); hostPort = item.slice(eq + 1); }
      const colon = hostPort.lastIndexOf(':');
      if (colon === -1) continue;
      const host = hostPort.slice(0, colon).trim();
      const port = hostPort.slice(colon + 1).trim();
      add(name, host, port);
    }
  }

  // 2) Zgodnosc wstecz: DEVICE_HOST / DEVICE_PORT
  const legacyPort = (process.env.DEVICE_PORT || '').trim();
  if (legacyPort) {
    add(process.env.DEVICE_NAME || 'domyslne', process.env.DEVICE_HOST || '127.0.0.1', legacyPort);
  }

  return out;
}

let cache = null;
function getDevices() {
  if (!cache) cache = parseList();
  return cache;
}

function getDefault() {
  const list = getDevices();
  return list.length ? list[0] : null;
}

function getByName(name) {
  const list = getDevices();
  if (!name) return getDefault();
  const target = String(name).trim().toLowerCase();
  return list.find((d) => d.name.toLowerCase() === target) || null;
}

module.exports = { getDevices, getDefault, getByName, sanitizeName };
