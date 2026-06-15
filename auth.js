'use strict';

/**
 * Lekka autoryzacja oparta na jednym wspolnym hasle (dostep anonimowy, bez kont).
 *
 * Po poprawnym podaniu hasla wystawiamy podpisane (HMAC) ciasteczko sesji.
 * Nie uzywamy zewnetrznego magazynu sesji - token jest samowystarczalny
 * i zweryfikowalny kryptograficznie. Dodatkowo limitujemy proby logowania,
 * zeby utrudnic zgadywanie hasla metoda brute-force.
 */

const crypto = require('crypto');
const config = require('./config');

const COOKIE_NAME = 'reklama_auth';

// --- Podpisywanie tokenow ---------------------------------------------------

function sign(payload) {
  const data = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const mac = crypto
    .createHmac('sha256', config.sessionSecret)
    .update(data)
    .digest('base64url');
  return `${data}.${mac}`;
}

function verify(token) {
  if (!token || typeof token !== 'string' || !token.includes('.')) return null;
  const [data, mac] = token.split('.');
  const expected = crypto
    .createHmac('sha256', config.sessionSecret)
    .update(data)
    .digest('base64url');

  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  try {
    const payload = JSON.parse(Buffer.from(data, 'base64url').toString('utf8'));
    if (!payload || typeof payload.exp !== 'number' || Date.now() > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}

// --- Porownanie hasla (odporne na timing attack) ----------------------------

function passwordMatches(input) {
  const a = Buffer.from(String(input || ''));
  const b = Buffer.from(String(config.accessPassword || ''));
  // Najpierw porownujemy dlugosci na stalym buforze, by nie wyciekala dlugosc.
  const padded = Buffer.alloc(Math.max(a.length, b.length, 1));
  const aPad = Buffer.alloc(padded.length);
  const bPad = Buffer.alloc(padded.length);
  a.copy(aPad);
  b.copy(bPad);
  return a.length === b.length && crypto.timingSafeEqual(aPad, bPad);
}

// --- Limit prob logowania (in-memory, per IP) -------------------------------

const attempts = new Map(); // ip -> { count, resetAt }
const MAX_ATTEMPTS = 8;
const WINDOW_MS = 10 * 60 * 1000; // 10 minut

function recordFailure(ip) {
  const now = Date.now();
  const rec = attempts.get(ip);
  if (!rec || now > rec.resetAt) {
    attempts.set(ip, { count: 1, resetAt: now + WINDOW_MS });
  } else {
    rec.count += 1;
  }
}

function isLockedOut(ip) {
  const rec = attempts.get(ip);
  if (!rec) return false;
  if (Date.now() > rec.resetAt) {
    attempts.delete(ip);
    return false;
  }
  return rec.count >= MAX_ATTEMPTS;
}

function clearAttempts(ip) {
  attempts.delete(ip);
}

// Sprzatanie wygaslych wpisow co jakis czas, by Mapa nie rosla w nieskonczonosc.
setInterval(() => {
  const now = Date.now();
  for (const [ip, rec] of attempts) {
    if (now > rec.resetAt) attempts.delete(ip);
  }
}, WINDOW_MS).unref();

// --- Pomocnicze: cookie -----------------------------------------------------

function buildSessionCookie() {
  const exp = Date.now() + config.sessionTtlHours * 60 * 60 * 1000;
  const token = sign({ exp });
  const maxAge = Math.floor((exp - Date.now()) / 1000);
  // HttpOnly + SameSite=Lax + Secure (ruch idzie przez HTTPS tunelu Cloudflare).
  return `${COOKIE_NAME}=${token}; Path=/; Max-Age=${maxAge}; HttpOnly; SameSite=Lax; Secure`;
}

function clearSessionCookie() {
  return `${COOKIE_NAME}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax; Secure`;
}

function readCookie(req, name) {
  const header = req.headers['cookie'];
  if (!header) return null;
  for (const part of header.split(';')) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const k = part.slice(0, idx).trim();
    if (k === name) return part.slice(idx + 1).trim();
  }
  return null;
}

function isAuthenticated(req) {
  const token = readCookie(req, COOKIE_NAME);
  return verify(token) !== null;
}

module.exports = {
  COOKIE_NAME,
  passwordMatches,
  recordFailure,
  isLockedOut,
  clearAttempts,
  buildSessionCookie,
  clearSessionCookie,
  isAuthenticated,
};
