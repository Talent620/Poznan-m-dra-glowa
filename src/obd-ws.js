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
 * Po stronie serwera (w domu) ten modul:
 *   1. przyjmuje polaczenie WebSocket na sciezce /obd (po autoryzacji haslem),
 *   2. otwiera surowe polaczenie TCP do urzadzenia (DEVICE_HOST:DEVICE_PORT),
 *   3. przekazuje bajty 1:1 w obie strony.
 *
 * Konfiguracja w .env:
 *   DEVICE_HOST  - adres urzadzenia w domowej sieci (np. 192.168.0.50) lub 127.0.0.1
 *   DEVICE_PORT  - port urzadzenia (np. 35000 dla adapterow WiFi OBD/ELM327)
 */

const net = require('net');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const auth = require('./auth');

const LOG = path.join(__dirname, '..', 'logs', 'obd.log');
try { fs.mkdirSync(path.dirname(LOG), { recursive: true }); } catch {}

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log('[OBD-WS] ' + msg);
  fs.appendFile(LOG, line + '\n', () => {});
}

const DEVICE_HOST = (process.env.DEVICE_HOST || '127.0.0.1').trim();
const DEVICE_PORT = parseInt(process.env.DEVICE_PORT || '', 10);

// Sciezka WebSocketa dla OBD (klient laczy sie pod ...trycloudflare.com/obd).
const OBD_PATH = '/obd';

/**
 * Sprawdza, czy zadanie WebSocket ma prawo polaczyc sie z urzadzeniem.
 * Akceptujemy ALBO wazna sesje (ciasteczko z przegladarki), ALBO wspolne
 * haslo podane przez klienta w parametrze ?key=... lub naglowku x-obd-key.
 * (Klient w terenie to skrypt bez przegladarki, wiec uzywa hasla.)
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

/** Czy dany upgrade dotyczy mostu OBD? */
function isObdUpgrade(req) {
  const p = (req.url || '').split('?')[0];
  return p === OBD_PATH || p.startsWith(OBD_PATH + '/');
}

/**
 * Podlacza obsluge WebSocketa OBD do istniejacego serwera HTTP.
 * Zwraca obiekt z metodami handleUpgrade(req, socket, head) i enabled.
 */
function attach() {
  const enabled = Number.isInteger(DEVICE_PORT);
  const wss = new WebSocketServer({ noServer: true });

  if (!enabled) {
    log('DEVICE_PORT nie ustawiony w .env - most OBD nieaktywny (ustaw DEVICE_PORT, np. 35000).');
  } else {
    log(`Most OBD gotowy. Klient w terenie: <link>/obd  ->  urzadzenie ${DEVICE_HOST}:${DEVICE_PORT}`);
  }

  wss.on('connection', (ws, req) => {
    const who = req.socket.remoteAddress;
    log(`Nowe polaczenie OBD od ${who} -> ${DEVICE_HOST}:${DEVICE_PORT}`);

    const tcp = net.connect(DEVICE_PORT, DEVICE_HOST);
    let closed = false;

    const closeAll = (reason) => {
      if (closed) return;
      closed = true;
      log(`Zamykam polaczenie OBD ${who} (${reason})`);
      try { tcp.destroy(); } catch {}
      try { ws.close(); } catch {}
    };

    // Urzadzenie -> przegladarka/klient (bajty TCP jako ramki binarne WS).
    tcp.on('data', (chunk) => {
      if (ws.readyState === ws.OPEN) ws.send(chunk, { binary: true });
    });
    tcp.on('connect', () => log(`Polaczono z urzadzeniem ${DEVICE_HOST}:${DEVICE_PORT}`));
    tcp.on('error', (e) => closeAll('blad urzadzenia: ' + e.message));
    tcp.on('close', () => closeAll('urzadzenie rozlaczone'));

    // Klient -> urzadzenie.
    ws.on('message', (data) => {
      // ws moze przekazac Buffer, ArrayBuffer lub tablice fragmentow.
      let buf;
      if (Buffer.isBuffer(data)) buf = data;
      else if (Array.isArray(data)) buf = Buffer.concat(data);
      else buf = Buffer.from(data);
      if (!tcp.destroyed) tcp.write(buf);
    });
    ws.on('error', (e) => closeAll('blad klienta: ' + e.message));
    ws.on('close', () => closeAll('klient rozlaczony'));
  });

  function handleUpgrade(req, socket, head) {
    if (!enabled) {
      socket.write('HTTP/1.1 503 Service Unavailable\r\n\r\n');
      socket.destroy();
      return;
    }
    if (!isAuthorized(req)) {
      log('Odrzucono polaczenie OBD - bledne lub brak hasla.');
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  }

  return { enabled, isObdUpgrade, handleUpgrade };
}

module.exports = { attach, isObdUpgrade, OBD_PATH };
