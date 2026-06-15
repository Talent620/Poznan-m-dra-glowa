'use strict';

/**
 * MOST TCP - udostepnia surowe urzadzenie sieciowe (np. interfejs OBD2 AIR)
 * tak, by dalo sie do niego polaczyc zdalnie przez prywatna siec Tailscale.
 *
 * Jak to dziala:
 *   [program diagnostyczny w terenie]  --(Tailscale)-->  [ten most na serwerze]  -->  [urzadzenie OBD2]
 *
 * Most nasluchuje lokalnie na porcie DEVICE_LISTEN_PORT (na wszystkich interfejsach,
 * zeby Tailscale mogl go dosiegnac) i przekazuje ruch 1:1 do urzadzenia
 * (DEVICE_HOST:DEVICE_PORT). Obsluguje wiele polaczen naraz.
 *
 * Konfiguracja w pliku .env:
 *   DEVICE_HOST          - adres urzadzenia w domowej sieci (np. 192.168.0.50) lub 127.0.0.1
 *   DEVICE_PORT          - port urzadzenia (np. 35000 - typowy dla adapterow WiFi OBD/ELM327)
 *   DEVICE_LISTEN_PORT   - port, na ktorym most czeka (domyslnie taki sam jak DEVICE_PORT)
 */

const net = require('net');
const fs = require('fs');
const path = require('path');

const LOG = path.join(__dirname, '..', 'logs', 'device.log');
try { fs.mkdirSync(path.dirname(LOG), { recursive: true }); } catch {}

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  fs.appendFile(LOG, line + '\n', () => {});
}

const DEVICE_HOST = process.env.DEVICE_HOST || '127.0.0.1';
const DEVICE_PORT = parseInt(process.env.DEVICE_PORT || '', 10);
const LISTEN_PORT = parseInt(process.env.DEVICE_LISTEN_PORT || process.env.DEVICE_PORT || '', 10);
const LISTEN_HOST = '0.0.0.0'; // aby Tailscale mogl dosiegnac portu

if (!Number.isInteger(DEVICE_PORT) || !Number.isInteger(LISTEN_PORT)) {
  console.error('[most TCP] Brak DEVICE_PORT w .env. Ustaw port urzadzenia (np. DEVICE_PORT=35000).');
  process.exit(1);
}

const server = net.createServer((client) => {
  const who = `${client.remoteAddress}:${client.remotePort}`;
  log(`Nowe polaczenie od ${who} -> ${DEVICE_HOST}:${DEVICE_PORT}`);

  const upstream = net.connect(DEVICE_PORT, DEVICE_HOST);

  // Przekazujemy dane w obie strony.
  client.pipe(upstream);
  upstream.pipe(client);

  const cleanup = (reason) => {
    if (client.destroyed && upstream.destroyed) return;
    log(`Zakonczono polaczenie ${who} (${reason})`);
    client.destroy();
    upstream.destroy();
  };

  upstream.on('error', (e) => { log(`Blad urzadzenia: ${e.message}`); cleanup('blad urzadzenia'); });
  client.on('error', (e) => { log(`Blad klienta: ${e.message}`); cleanup('blad klienta'); });
  upstream.on('close', () => cleanup('urzadzenie rozlaczone'));
  client.on('close', () => cleanup('klient rozlaczony'));
});

server.on('error', (e) => {
  log(`Blad serwera mostu: ${e.message}`);
  process.exit(1);
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  log(`Most TCP gotowy. Nasluch ${LISTEN_HOST}:${LISTEN_PORT}  ->  urzadzenie ${DEVICE_HOST}:${DEVICE_PORT}`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => { log(`Otrzymano ${sig}, zamykam most.`); server.close(() => process.exit(0)); });
}
