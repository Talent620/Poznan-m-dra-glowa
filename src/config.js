'use strict';

/**
 * Wczytuje konfiguracje z pliku .env i udostepnia ja reszcie aplikacji.
 * Wszystkie wartosci maja sensowne domyslne ustawienia.
 */

const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

function bool(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  return /^(1|true|yes|on|tak)$/i.test(String(value).trim());
}

function int(value, fallback) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

const config = {
  port: int(process.env.PORT, 8080),
  host: process.env.HOST || '127.0.0.1',

  upstreamUrl: (process.env.UPSTREAM_URL || '').trim(),
  staticDir: (process.env.STATIC_DIR || '').trim(),

  accessPassword: process.env.ACCESS_PASSWORD || '',
  sessionSecret: process.env.SESSION_SECRET || '',
  sessionTtlHours: int(process.env.SESSION_TTL_HOURS, 12),

  brandName: process.env.BRAND_NAME || 'Kluczyki Poznań mądra głowa',
  trustProxy: bool(process.env.TRUST_PROXY, true),
};

/**
 * Sprawdza, czy konfiguracja jest gotowa do uruchomienia.
 * Zwraca liste bledow (pusta = wszystko OK).
 */
config.validate = function validate() {
  const errors = [];
  if (!config.accessPassword || config.accessPassword.length < 6) {
    errors.push('ACCESS_PASSWORD jest pusty lub krotszy niz 6 znakow. Uruchom scripts\\setup.ps1.');
  }
  if (!config.sessionSecret || config.sessionSecret.length < 16) {
    errors.push('SESSION_SECRET jest pusty lub za krotki. Uruchom scripts\\setup.ps1.');
  }

  // UPSTREAM_URL (jesli podany) musi byc poprawnym adresem http(s).
  if (config.upstreamUrl) {
    let ok = false;
    try {
      const u = new URL(config.upstreamUrl);
      ok = (u.protocol === 'http:' || u.protocol === 'https:');
    } catch { ok = false; }
    if (!ok) {
      errors.push('UPSTREAM_URL ma zly format. Wpisz pelny adres, np. http://127.0.0.1:3000 (z http:// na poczatku).');
    }
  }

  // Urzadzenia OBD: jesli cokolwiek ustawiono (DEVICES albo DEVICE_PORT),
  // sprawdzamy, czy da sie to odczytac. Inaczej most OBD nie wystartuje po cichu.
  const rawDevices = (process.env.DEVICES || '').trim();
  const rawPort = (process.env.DEVICE_PORT || '').trim();
  if (rawDevices || rawPort) {
    let list = [];
    try { list = require('./devices').getDevices(); } catch { list = []; }
    if (list.length === 0) {
      errors.push(
        'Ustawienia urzadzen OBD (DEVICES / DEVICE_PORT) sa nieczytelne. ' +
        'Format: nazwa=adres:port, np. auto1=192.168.0.10:35000 (kilka oddzielaj srednikiem). ' +
        'Najprosciej ustaw je przez MENU -> opcja 2.'
      );
    }
  }

  return errors;
};

module.exports = config;
