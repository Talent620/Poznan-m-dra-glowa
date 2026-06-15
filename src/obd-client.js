'use strict';

/**
 * KLIENT OBD W TERENIE (uruchamiasz na laptopie u mechanika / w terenie)
 * ----------------------------------------------------------------------------
 * Tworzy lokalny port TCP (domyslnie 127.0.0.1:35000), do ktorego podlaczasz
 * program diagnostyczny - tak, jakby adapter OBD lezal obok. Caly ruch jedzie
 * bezpiecznie przez link Cloudflare (WebSocket/WSS) do komputera w domu, a tam
 * trafia do prawdziwego urzadzenia OBD.
 *
 *   [program diagnostyczny] --TCP--> [TEN klient] ==WSS==> [serwer w domu] --TCP--> [OBD2]
 *
 * Dzieki temu OBD dziala przez ZWYKLY darmowy link Cloudflare - bez Tailscale,
 * bez konfiguracji routera.
 *
 * Konfiguracja przez zmienne srodowiskowe (ustawia je run-obd.ps1):
 *   OBD_LINK        - link od pracodawcy, np. https://cos-tam.trycloudflare.com
 *   OBD_KEY         - wspolne haslo (to samo co do strony)
 *   OBD_LOCAL_PORT  - lokalny port, na ktorym slucha klient (domyslnie 35000)
 *   OBD_LOCAL_HOST  - lokalny adres nasluchu (domyslnie 127.0.0.1)
 */

const net = require('net');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const LOG = path.join(__dirname, '..', 'logs', 'obd-client.log');
try { fs.mkdirSync(path.dirname(LOG), { recursive: true }); } catch {}

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  fs.appendFile(LOG, line + '\n', () => {});
}

const LINK = (process.env.OBD_LINK || '').trim();
const KEY = (process.env.OBD_KEY || '').trim();
const DEVICE = (process.env.OBD_DEVICE || '').trim(); // nazwa urzadzenia (opcjonalnie)
const LOCAL_PORT = parseInt(process.env.OBD_LOCAL_PORT || '35000', 10);
const LOCAL_HOST = (process.env.OBD_LOCAL_HOST || '127.0.0.1').trim();

if (!LINK) {
  console.error('[KLIENT OBD] Brak OBD_LINK. Podaj link od pracodawcy (https://...trycloudflare.com).');
  process.exit(1);
}
if (!KEY) {
  console.error('[KLIENT OBD] Brak OBD_KEY (wspolne haslo).');
  process.exit(1);
}

// Zamieniamy http(s):// na ws(s):// i dopinamy sciezke /obd, haslo i urzadzenie.
function buildWsUrl() {
  let base = LINK.replace(/\/+$/, '');
  if (base.startsWith('https://')) base = 'wss://' + base.slice('https://'.length);
  else if (base.startsWith('http://')) base = 'ws://' + base.slice('http://'.length);
  else base = 'wss://' + base; // sam adres bez schematu - zakladamy wss
  let url = base + '/obd?key=' + encodeURIComponent(KEY);
  if (DEVICE) url += '&device=' + encodeURIComponent(DEVICE);
  return url;
}

const WS_URL = buildWsUrl();

const server = net.createServer((client) => {
  const who = `${client.remoteAddress}:${client.remotePort}`;
  client.setNoDelay(true); // male komendy OBD natychmiast (bez opoznienia Nagle'a)
  log(`Program diagnostyczny podlaczyl sie (${who}). Otwieram tunel do urzadzenia...`);

  const ws = new WebSocket(WS_URL, { handshakeTimeout: 15000, perMessageDeflate: false });
  let open = false;
  let closed = false;
  const pending = []; // dane, ktore przyszly zanim WS sie otworzyl

  const closeAll = (reason) => {
    if (closed) return;
    closed = true;
    log(`Rozlaczono (${reason}).`);
    try { client.destroy(); } catch {}
    try { ws.close(); } catch {}
  };

  // Czytelny komunikat, gdy serwer odrzuci polaczenie (zle haslo / zajete / brak urzadzenia).
  ws.on('unexpected-response', (_req, res) => {
    const code = res.statusCode;
    let why = 'serwer odrzucil polaczenie (' + code + ')';
    if (code === 401) why = 'BLEDNE HASLO - sprawdz haslo od pracodawcy';
    else if (code === 404) why = 'NIE MA TAKIEGO URZADZENIA - sprawdz nazwe urzadzenia';
    else if (code === 409) why = 'URZADZENIE ZAJETE - ktos inny wlasnie z niego korzysta';
    else if (code === 503) why = 'most OBD wylaczony na serwerze (brak urzadzen w .env)';
    closeAll(why);
  });

  ws.on('open', () => {
    open = true;
    log(`Tunel do urzadzenia${DEVICE ? ' "' + DEVICE + '"' : ''} otwarty - mozna diagnozowac.`);
    for (const chunk of pending) ws.send(chunk, { binary: true });
    pending.length = 0;
  });

  // urzadzenie (przez serwer) -> program diagnostyczny
  ws.on('message', (data) => {
    let buf;
    if (Buffer.isBuffer(data)) buf = data;
    else if (Array.isArray(data)) buf = Buffer.concat(data);
    else buf = Buffer.from(data);
    if (!client.destroyed) client.write(buf);
  });
  ws.on('error', (e) => closeAll('blad tunelu: ' + e.message));
  ws.on('close', () => closeAll('tunel zamkniety'));

  // program diagnostyczny -> urzadzenie
  client.on('data', (chunk) => {
    if (open && ws.readyState === WebSocket.OPEN) ws.send(chunk, { binary: true });
    else pending.push(chunk);
  });
  client.on('error', (e) => closeAll('blad programu: ' + e.message));
  client.on('close', () => closeAll('program rozlaczyl sie'));
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    log(`Port ${LOCAL_PORT} jest zajety. Zamknij inny program uzywajacy tego portu albo zmien OBD_LOCAL_PORT.`);
  } else {
    log('Blad lokalnego serwera: ' + e.message);
  }
  process.exit(1);
});

server.listen(LOCAL_PORT, LOCAL_HOST, () => {
  log('============================================================');
  log('  KLIENT OBD GOTOWY' + (DEVICE ? ` (urzadzenie: ${DEVICE})` : ''));
  log(`  W programie diagnostycznym ustaw polaczenie sieciowe (WiFi/TCP) na:`);
  log(`     Adres: ${LOCAL_HOST}   Port: ${LOCAL_PORT}`);
  log(`  Tunel: ${LINK}  (/obd${DEVICE ? '?device=' + DEVICE : ''})`);
  log('============================================================');
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => { log(`Otrzymano ${sig}, zamykam klienta OBD.`); server.close(() => process.exit(0)); });
}
