'use strict';

/**
 * Drobne narzedzia sieciowe: sprawdzanie, czy cos nasluchuje pod host:port,
 * oraz typowe porty interfejsow OBD/diagnostycznych.
 */

const net = require('net');
const os = require('os');

// Typowe porty interfejsow OBD / diagnostycznych (wg researchu):
//  35000        - adaptery WiFi ELM327 (transparentny TCP<->serial)
//  13400        - DoIP (Diagnostics over IP) - profesjonalne interfejsy VAG itp.
//  3000         - czesty port aplikacji/bram diagnostycznych
//  23 (telnet)  - niektore adaptery udostepniaja surowy strumien przez telnet
//  48100        - spotykane w niektorych interfejsach J2534-over-IP
const COMMON_OBD_PORTS = [35000, 13400, 3000, 23, 48100];

/**
 * Sprawdza, czy pod host:port cos nasluchuje (proba polaczenia TCP).
 * Zwraca Promise<boolean>. Krotki limit czasu, zeby skan byl szybki.
 */
function testReachable(host, port, timeoutMs = 1000) {
  return new Promise((resolve) => {
    const sock = new net.Socket();
    let done = false;
    const finish = (ok) => { if (done) return; done = true; try { sock.destroy(); } catch {} resolve(ok); };
    sock.setTimeout(timeoutMs);
    sock.once('connect', () => finish(true));
    sock.once('timeout', () => finish(false));
    sock.once('error', () => finish(false));
    try { sock.connect(port, host); } catch { finish(false); }
  });
}

/** Lista lokalnych podsieci IPv4 (np. ["192.168.0"]) - do skanowania domowej sieci. */
function localSubnets() {
  const out = [];
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const a of ifaces[name] || []) {
      if (a.family === 'IPv4' && !a.internal) {
        const parts = a.address.split('.');
        if (parts.length === 4) out.push(parts.slice(0, 3).join('.'));
      }
    }
  }
  return [...new Set(out)];
}

module.exports = { testReachable, localSubnets, COMMON_OBD_PORTS };
