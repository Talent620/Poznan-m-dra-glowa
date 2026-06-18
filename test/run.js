'use strict';

/**
 * TESTY (bez zewnetrznych frameworkow - tylko Node + biblioteka ws).
 * Uruchom:  npm test    albo    node test/run.js
 *
 * Czesc A: testy jednostkowe (devices, auth, config.validate) w tym procesie.
 * Czesc B: testy integracyjne - startuje brame (src/server.js) jako osobny
 *          proces + atrape adaptera OBD, i sprawdza logowanie, lockout, CSRF
 *          oraz most OBD przez WebSocket.
 */

const net = require('net');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const WebSocket = require('ws');

const ROOT = path.join(__dirname, '..');

let pass = 0, fail = 0;
const failed = [];
function check(name, cond) {
  if (cond) { pass++; console.log('  ✓ ' + name); }
  else { fail++; failed.push(name); console.log('  ✗ ' + name); }
}
function section(t) { console.log('\n=== ' + t + ' ==='); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- pomocnik: swiezy require (czysci cache modulu) -------------------------
function freshRequire(rel) {
  const p = require.resolve(rel);
  delete require.cache[p];
  return require(rel);
}
function freshConfig() {
  delete require.cache[require.resolve('../src/devices')];
  delete require.cache[require.resolve('../src/config')];
  return require('../src/config');
}

// ============================================================================
//  CZESC A - TESTY JEDNOSTKOWE
// ============================================================================
function unitTests() {
  section('Jednostkowe: devices.js');
  process.env.DEVICES = 'auto1=192.168.0.10:35000; auto2=192.168.0.11:13400';
  process.env.DEVICE_PORT = '';
  process.env.DEVICE_HOST = '';
  const devices = freshRequire('../src/devices');
  const list = devices.getDevices();
  check('parsuje 2 urzadzenia', list.length === 2);
  check('pierwsze: nazwa auto1, port 35000', list[0].name === 'auto1' && list[0].port === 35000);
  check('getByName zwraca DoIP 13400', devices.getByName('auto2') && devices.getByName('auto2').port === 13400);
  check('getByName bez nazwy -> domyslne (pierwsze)', devices.getByName('').name === 'auto1');
  check('sanitizeName czysci znaki', devices.sanitizeName('a b/c', 'x') === 'a-b-c');

  section('Jednostkowe: auth.js');
  process.env.ACCESS_PASSWORD = 'Tajne-Haslo-123';
  process.env.SESSION_SECRET = '0123456789abcdef0123456789';
  const auth = freshRequire('../src/auth');
  const cookie = auth.buildSessionCookie(true);
  check('cookie z HTTPS ma flage Secure', /Secure/.test(cookie));
  check('cookie po http NIE ma Secure', !/Secure/.test(auth.buildSessionCookie(false)));
  const token = cookie.split('=')[1].split(';')[0];
  const okReq = { headers: { cookie: 'reklama_auth=' + token } };
  check('wazny token => isAuthenticated', auth.isAuthenticated(okReq) === true);
  const tampered = token.slice(0, -2) + (token.slice(-2) === 'aa' ? 'bb' : 'aa');
  check('podrobiony token => odrzucony', auth.isAuthenticated({ headers: { cookie: 'reklama_auth=' + tampered } }) === false);
  check('passwordMatches: poprawne', auth.passwordMatches('Tajne-Haslo-123') === true);
  check('passwordMatches: bledne', auth.passwordMatches('zle') === false);
  // lockout
  const ip = '203.0.113.7';
  for (let i = 0; i < 8; i++) auth.recordFailure(ip);
  check('lockout po 8 probach', auth.isLockedOut(ip) === true);
  auth.clearAttempts(ip);
  check('clearAttempts zwalnia', auth.isLockedOut(ip) === false);

  section('Jednostkowe: config.validate()');
  process.env.ACCESS_PASSWORD = 'dlugie-haslo';
  process.env.SESSION_SECRET = '0123456789abcdef0123456789';
  process.env.DEVICE_PORT = ''; process.env.DEVICE_HOST = '';
  process.env.UPSTREAM_URL = 'to-nie-jest-adres'; process.env.DEVICES = '';
  let errs = freshConfig().validate();
  check('zly UPSTREAM_URL wykryty', errs.some((e) => e.includes('UPSTREAM_URL')));
  process.env.UPSTREAM_URL = ''; process.env.DEVICES = 'x=1.2.3.4'; // brak portu
  errs = freshConfig().validate();
  check('zle DEVICES wykryte', errs.some((e) => e.includes('urzadzen OBD')));
  process.env.UPSTREAM_URL = 'http://127.0.0.1:3000'; process.env.DEVICES = 'a=1.2.3.4:35000';
  errs = freshConfig().validate();
  check('poprawna konfiguracja => brak bledow', errs.length === 0);
}

// ============================================================================
//  CZESC B - TESTY INTEGRACYJNE
// ============================================================================
const ADAPTER_PORT = 35790;
const SERVER_PORT = 8799;
const PASSWORD = 'Test-Haslo-123';
const BASE = `http://127.0.0.1:${SERVER_PORT}`;
const WS_OBD = `ws://127.0.0.1:${SERVER_PORT}/obd`;

function startAdapter() {
  return new Promise((resolve) => {
    const s = net.createServer((c) => {
      c.on('data', (d) => { c.write('ECHO:' + d.toString().trim() + '\r>'); });
      c.on('error', () => {});
    });
    s.listen(ADAPTER_PORT, '127.0.0.1', () => resolve(s));
  });
}

function startServer() {
  const env = {
    PATH: process.env.PATH,
    PORT: String(SERVER_PORT), HOST: '127.0.0.1',
    DEVICES: `test=127.0.0.1:${ADAPTER_PORT}`,
    DEVICE_PORT: '', DEVICE_HOST: '', UPSTREAM_URL: '', STATIC_DIR: '',
    ACCESS_PASSWORD: PASSWORD, SESSION_SECRET: '0123456789abcdef0123456789',
    BRAND_NAME: 'Test', TRUST_PROXY: 'true',
  };
  const child = spawn('node', ['src/server.js'], { cwd: ROOT, env, stdio: 'ignore' });
  return child;
}

function httpReq(method, urlPath, { headers = {}, body = null } = {}) {
  return new Promise((resolve, reject) => {
    const data = body != null ? Buffer.from(body) : null;
    const h = Object.assign({}, headers);
    if (data) { h['Content-Type'] = 'application/x-www-form-urlencoded'; h['Content-Length'] = data.length; }
    const req = http.request(BASE + urlPath, { method, headers: h }, (res) => {
      let buf = '';
      res.on('data', (c) => buf += c);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: buf }));
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

function wsTry(key, { sendCmd = null, holdMs = 0 } = {}) {
  return new Promise((resolve) => {
    const opts = { perMessageDeflate: false };
    if (key != null) opts.headers = { 'x-obd-key': key };
    const ws = new WebSocket(WS_OBD, opts);
    let settled = false, got = null;
    const done = (r) => { if (!settled) { settled = true; resolve(r); } try { ws.terminate(); } catch {} };
    ws.on('unexpected-response', (_r, res) => done({ open: false, status: res.statusCode }));
    ws.on('open', () => { if (sendCmd) ws.send(Buffer.from(sendCmd)); });
    ws.on('message', (d) => {
      if (got === null) got = Buffer.isBuffer(d) ? d : Buffer.from(d);
      if (!holdMs) done({ open: true, status: 200, msg: got.toString() });
    });
    ws.on('error', () => {}); // obsluzone przez unexpected-response/timeout
    if (holdMs) setTimeout(() => done({ open: true, status: 200, msg: got ? got.toString() : '' }), holdMs);
    setTimeout(() => done({ open: false, status: null }), 4000);
  });
}

async function waitHealthy() {
  for (let i = 0; i < 50; i++) {
    try { const r = await httpReq('GET', '/healthz'); if (r.status === 200) return true; } catch {}
    await sleep(100);
  }
  return false;
}

async function integrationTests() {
  const adapter = await startAdapter();
  const server = startServer();
  try {
    section('Integracyjne: start serwera');
    const healthy = await waitHealthy();
    check('brama odpowiada na /healthz', healthy);
    if (!healthy) return;

    section('Integracyjne: autoryzacja OBD (HTTP)');
    check('/obd-devices bez hasla => 401', (await httpReq('GET', '/obd-devices')).status === 401);
    const dev = await httpReq('GET', '/obd-devices', { headers: { 'x-obd-key': PASSWORD } });
    check('/obd-devices z naglowkiem => 200', dev.status === 200);
    check('lista zawiera urzadzenie "test"', /"test"/.test(dev.body));

    section('Integracyjne: logowanie / cookie / CSRF');
    const badLogin = await httpReq('POST', '/login', { headers: { Origin: BASE }, body: 'password=zle' });
    check('zle haslo => 401', badLogin.status === 401);
    const okLogin = await httpReq('POST', '/login', { headers: { Origin: BASE }, body: 'password=' + PASSWORD });
    check('poprawne haslo => 302', okLogin.status === 302);
    const setCookie = String(okLogin.headers['set-cookie'] || '');
    check('po http cookie BEZ Secure', setCookie.length > 0 && !/Secure/.test(setCookie));
    const httpsLogin = await httpReq('POST', '/login', {
      headers: { Origin: 'https://foo.example', 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': 'foo.example' },
      body: 'password=' + PASSWORD,
    });
    check('przez HTTPS cookie Z Secure', /Secure/.test(String(httpsLogin.headers['set-cookie'] || '')));
    const csrf = await httpReq('POST', '/login', { headers: { Origin: 'http://evil.example' }, body: 'password=' + PASSWORD });
    check('obcy Origin => 403 (CSRF)', csrf.status === 403);

    section('Integracyjne: most OBD przez WebSocket');
    const aP = wsTry(PASSWORD, { sendCmd: 'ATZ\r', holdMs: 1000 }); // trzyma urzadzenie
    await sleep(300);
    const b = await wsTry(PASSWORD, { sendCmd: 'ATZ\r' });          // drugi - ma byc odrzucony
    check('drugi klient na to samo urzadzenie => 409', b.status === 409);
    const a = await aP;
    check('most przekazuje OBD tam i z powrotem (ECHO)', !!(a.msg && a.msg.includes('ECHO:ATZ')));
    await sleep(200); // urzadzenie zwolnione

    section('Integracyjne: lockout na /obd (WebSocket)');
    let saw429 = false, first = null;
    for (let i = 0; i < 9; i++) {
      const r = await wsTry('ZLE-HASLO');
      if (first === null) first = r.status;
      if (r.status === 429) { saw429 = true; break; }
    }
    check('pierwsza zla proba => 401', first === 401);
    check('po wielu probach => 429 (blokada)', saw429);
  } finally {
    try { server.kill(); } catch {}
    try { adapter.close(); } catch {}
  }
}

// ============================================================================
(async () => {
  console.log('URUCHAMIAM TESTY\n----------------');
  try {
    unitTests();
    await integrationTests();
  } catch (e) {
    console.error('\nBLAD WYKONANIA TESTOW:', e && e.stack ? e.stack : e);
    fail++;
  }
  console.log('\n----------------');
  console.log(`WYNIK: ${pass} OK, ${fail} bledow`);
  if (fail) { console.log('Nieudane: ' + failed.join(', ')); process.exit(1); }
  console.log('Wszystko przeszlo. ✓');
  process.exit(0);
})();
