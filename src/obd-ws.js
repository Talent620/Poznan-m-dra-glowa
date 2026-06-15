'use strict';

/**
 * MOST OBD PRZEZ WEBSOCKET (dziala przez darmowy tunel Cloudflare!)
 * ----------------------------------------------------------------------------
 * Problem: surowy port TCP urzadzenia OBD (np. adapter WiFi/ELM327 na porcie
 * 35000) NIE przechodzi przez darmowy tunel Cloudflare, ktory obsluguje tylko
 * HTTP. Dlatego "narzedzie sie laczy, ale OBD nie przekazuje".
 *
 * Rozwiazanie: opakowujemy ruch OBD w WebSocket. WebSocket to HTTP (upgrade),
 * wiec swobodnie przechodzi przez ten sam link Cloudflare, ktory juz dziala.
 *
 *   [program diagnostyczny w terenie]
 *         | TCP 127.0.0.1:35000
 *         v
 *   [obd-client.js na laptopie]  ==WSS (link Cloudflare)==>  [TEN most]  --TCP-->  [OBD2 w domu]
 *
 * Obsluguje WIELE urzadzen (patrz src/devices.js). Klient wybiera urzadzenie
 * parametrem ?device=NAZWA. Bez parametru uzywane jest pierwsze (domyslne).
 *
 * Wlasciwosci wazne dla diagnostyki OBD:
 *   - TCP_NODELAY (setNoDelay) - male komendy ELM327 ida natychmiast (bez ~40ms
 *     opoznienia algorytmu Nagle'a); diagnostyka jest "zywa".
 *   - Brak kompresji WebSocket (perMessageDeflate=false) - mniejsze opoznienie.
 *   - Blokada 1 klient na 1 urzadzenie - adaptery ELM327 (zwlaszcza klony)
 *     przyjmuja tylko jedno polaczenie naraz; drugie zepsuloby sesje.
 *   - Ping/pong (heartbeat) - wykrywa zerwane polaczenia i zwalnia urzadzenie.
 */

const net = require('net');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const auth = require('./auth');
const config = require('./config');
const devices = require('./devices');
const { testReachable } = require('./probe');

const LOG = path.join(__dirname, '..', 'logs', 'obd.log');
try { fs.mkdirSync(path.dirname(LOG), { recursive: true }); } catch {}

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log('[OBD-WS] ' + msg);
  fs.appendFile(LOG, line + '\n', () => {});
}

const OBD_PATH = '/obd';
const HEARTBEAT_MS = 20000; // co ile sekund pingujemy klienta

// Ktore urzadzenia sa aktualnie zajete (nazwa -> true). 1 klient na 1 urzadzenie.
const busy = new Set();

/**
 * Sprawdza, czy zadanie ma prawo polaczyc sie z urzadzeniem.
 * Akceptujemy ALBO wazna sesje (ciasteczko z przegladarki), ALBO wspolne
 * haslo podane przez klienta w parametrze ?key=... lub naglowku x-obd-key.
 */
function isAuthorized(req) {
  if (auth.isAuthenticated(req)) return true;
  let key = req.headers['x-obd-key'] || '';
  try {
    const u = new URL(req.url, 'http://localhost');
    key = key || u.searchParams.get('key') || '';
  } catch { /* ignore */ }
  return auth.passwordMatches(key);
}

/**
 * Adres IP klienta dla limitu prob (lockout). Za tunelem Cloudflare wszystkie
 * polaczenia przychodza z 127.0.0.1, dlatego - gdy ufamy proxy - bierzemy
 * prawdziwy adres z naglowka X-Forwarded-For (pierwszy wpis).
 */
function clientIp(req) {
  if (config.trustProxy) {
    const xff = req.headers['x-forwarded-for'];
    if (xff) return String(xff).split(',')[0].trim();
  }
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}

/** Czy dany upgrade dotyczy mostu OBD? */
function isObdUpgrade(req) {
  const p = (req.url || '').split('?')[0];
  return p === OBD_PATH || p.startsWith(OBD_PATH + '/');
}

/** Nazwa urzadzenia z adresu (?device=...). */
function deviceNameFromReq(req) {
  try {
    const u = new URL(req.url, 'http://localhost');
    return u.searchParams.get('device') || '';
  } catch { return ''; }
}

/** Lista urzadzen do pokazania klientowi (nazwa + czy zajete). */
function listDevices() {
  return devices.getDevices().map((d) => ({ name: d.name, busy: busy.has(d.name) }));
}

/**
 * Status urzadzen z aktywnym testem dostepnosci (czy adapter odpowiada w sieci
 * domowej) + czy jest zajety. Uzywane przez panel WWW. Zwraca Promise.
 */
async function statusDevices() {
  const list = devices.getDevices();
  const out = await Promise.all(list.map(async (d) => ({
    name: d.name,
    online: await testReachable(d.host, d.port, 1200),
    busy: busy.has(d.name),
  })));
  return out;
}

function attach() {
  const list = devices.getDevices();
  const enabled = list.length > 0;
  const wss = new WebSocketServer({ noServer: true, perMessageDeflate: false });

  if (!enabled) {
    log('Brak urzadzen w .env - most OBD nieaktywny (ustaw DEVICE_PORT lub DEVICES, np. 35000).');
  } else {
    log(`Most OBD gotowy. Urzadzenia: ${list.map((d) => `${d.name} -> ${d.host}:${d.port}`).join(', ')}`);
  }

  // Heartbeat: regularnie pingujemy klientow; martwych zamykamy (zwalnia urzadzenie).
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) { try { ws.terminate(); } catch {} continue; }
      ws.isAlive = false;
      try { ws.ping(); } catch {}
    }
  }, HEARTBEAT_MS);
  heartbeat.unref();

  wss.on('connection', (ws, req) => {
    const device = req._obdDevice;
    const who = req.socket.remoteAddress;
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    log(`Polaczenie OBD od ${who} -> urzadzenie "${device.name}" (${device.host}:${device.port})`);

    req._obdConnected = true; // upgrade sie udal - zwalnianiem zajmie sie closeAll
    const tcp = net.connect(device.port, device.host);
    tcp.setNoDelay(true);           // male komendy OBD natychmiast
    tcp.setKeepAlive(true, 15000);  // wykryj zerwany/wylaczony adapter (martwe TCP)
    let closed = false;

    const closeAll = (reason) => {
      if (closed) return;
      closed = true;
      busy.delete(device.name); // zwalniamy urzadzenie
      log(`Zamykam OBD ${who} / "${device.name}" (${reason})`);
      try { tcp.destroy(); } catch {}
      try { ws.close(); } catch {}
    };

    // Urzadzenie -> klient (bajty TCP jako ramki binarne WS).
    tcp.on('data', (chunk) => {
      if (ws.readyState === ws.OPEN) ws.send(chunk, { binary: true });
    });
    tcp.on('connect', () => log(`Polaczono z urzadzeniem "${device.name}" ${device.host}:${device.port}`));
    tcp.on('error', (e) => closeAll('blad urzadzenia: ' + e.message));
    tcp.on('close', () => closeAll('urzadzenie rozlaczone'));

    // Klient -> urzadzenie.
    ws.on('message', (data) => {
      let buf;
      if (Buffer.isBuffer(data)) buf = data;
      else if (Array.isArray(data)) buf = Buffer.concat(data);
      else buf = Buffer.from(data);
      if (!tcp.destroyed) tcp.write(buf);
    });
    ws.on('error', (e) => closeAll('blad klienta: ' + e.message));
    ws.on('close', () => closeAll('klient rozlaczony'));
  });

  function rejectUpgrade(socket, code, text) {
    socket.write(`HTTP/1.1 ${code} ${text}\r\nConnection: close\r\n\r\n`);
    socket.destroy();
  }

  function handleUpgrade(req, socket, head) {
    if (!enabled) return rejectUpgrade(socket, 503, 'Service Unavailable');

    const ip = clientIp(req);

    // Limit prob (lockout) - tak samo jak na stronie logowania - zeby nie dalo
    // sie zgadywac hasla przez WebSocket bez ograniczen.
    if (auth.isLockedOut(ip)) {
      log(`Odrzucono OBD - zbyt wiele prob z ${ip} (chwilowa blokada).`);
      return rejectUpgrade(socket, 429, 'Too Many Requests');
    }

    if (!isAuthorized(req)) {
      auth.recordFailure(ip);
      log('Odrzucono OBD - bledne lub brak hasla.'); // nie logujemy samego hasla
      return rejectUpgrade(socket, 401, 'Unauthorized');
    }
    auth.clearAttempts(ip); // poprawne haslo/sesja - kasujemy licznik prob

    const wanted = deviceNameFromReq(req);
    const device = devices.getByName(wanted);
    if (!device) {
      log(`Odrzucono OBD - nieznane urzadzenie "${wanted}". Dostepne: ${list.map((d) => d.name).join(', ')}`);
      return rejectUpgrade(socket, 404, 'Unknown Device');
    }

    if (busy.has(device.name)) {
      log(`Odrzucono OBD - urzadzenie "${device.name}" jest zajete przez inne polaczenie.`);
      return rejectUpgrade(socket, 409, 'Device Busy');
    }

    busy.add(device.name);
    req._obdDevice = device;
    req._obdConnected = false;

    // Zabezpieczenie: gdyby handshake padl PRZED zdarzeniem "connection"
    // (np. klient sie rozmyslil), zwolnij urzadzenie, by nie zostalo "zajete".
    const releaseIfUnused = () => { if (!req._obdConnected) busy.delete(device.name); };
    socket.once('error', releaseIfUnused);
    socket.once('close', releaseIfUnused);

    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  }

  return { enabled, isObdUpgrade, handleUpgrade, isAuthorized, listDevices, statusDevices };
}

module.exports = { attach, isObdUpgrade, listDevices, OBD_PATH };
