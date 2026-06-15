'use strict';

/**
 * DIAGNOZA OBD - uruchamiana NA KOMPUTERZE W DOMU.
 * Sprawdza po kolei, gdzie lezy problem "nie przekazuje OBD" i mowi wprost,
 * co zrobic. Nic nie zmienia - tylko sprawdza i raportuje.
 */

const path = require('path');
const http = require('http');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const devices = require('./devices');
const { testReachable, localSubnets, COMMON_OBD_PORTS } = require('./probe');

const config = require('./config');

function line(s) { console.log(s); }
function hr() { line('------------------------------------------------------------'); }

async function pool(items, worker, concurrency = 256) {
  const results = []; let i = 0;
  await Promise.all(new Array(Math.min(concurrency, items.length || 1)).fill(0).map(async () => {
    while (i < items.length) { const r = await worker(items[i++]); if (r) results.push(r); }
  }));
  return results;
}

function httpGet(url, timeoutMs = 1500) {
  return new Promise((resolve) => {
    const req = http.get(url, (res) => { res.resume(); resolve(res.statusCode); });
    req.on('error', () => resolve(null));
    req.setTimeout(timeoutMs, () => { req.destroy(); resolve(null); });
  });
}

async function main() {
  line('');
  line('============================================================');
  line('   DIAGNOZA OBD  (komputer w domu)');
  line('============================================================');

  // --- 1. Co jest skonfigurowane? -------------------------------------------
  hr();
  line('1) USTAWIENIA (.env)');
  const list = devices.getDevices();
  if (list.length === 0) {
    line('   [!] Brak skonfigurowanych urzadzen OBD.');
    line('       -> W MENU wybierz opcje 2 (USTAW) i podaj adres oraz port adaptera,');
    line('          albo uruchom "9 - Znajdz adapter OBD.bat".');
  } else {
    line(`   Skonfigurowane urzadzenia (${list.length}):`);
    for (const d of list) line(`     - ${d.name}  ->  ${d.host}:${d.port}`);
  }
  if (config.upstreamUrl) line(`   Narzedzie webowe (UPSTREAM_URL): ${config.upstreamUrl}`);

  // --- 2. Czy komputer w domu WIDZI adapter? --------------------------------
  hr();
  line('2) CZY TEN KOMPUTER WIDZI ADAPTER? (najwazniejsze)');
  let anyReachable = false;
  for (const d of list) {
    const ok = await testReachable(d.host, d.port, 1500);
    line(`   ${ok ? '[OK] OSIAGALNY ' : '[X]  NIE widac '}  ${d.name}: ${d.host}:${d.port}`);
    if (ok) anyReachable = true;
  }
  if (list.length === 0) line('   (pomijam - brak urzadzen w ustawieniach)');

  // --- 3. Skan sieci: co naprawde odpowiada? --------------------------------
  hr();
  line('3) SKAN SIECI DOMOWEJ (szukam adapterow na typowych portach)');
  const subs = localSubnets();
  if (subs.length === 0) {
    line('   [!] Nie wykryto sieci domowej (czy komputer jest podlaczony do WiFi/LAN?).');
  } else {
    line(`   Sieci: ${subs.join(', ')}  |  porty: ${COMMON_OBD_PORTS.join(', ')}`);
    const targets = [];
    for (const s of subs) for (let h = 1; h <= 254; h++) for (const p of COMMON_OBD_PORTS) targets.push({ host: `${s}.${h}`, port: p });
    const found = await pool(targets, async (t) => (await testReachable(t.host, t.port, 700)) ? t : null);
    if (found.length === 0) {
      line('   [X] Nic nie odpowiada na typowych portach OBD.');
    } else {
      const rank = (p) => COMMON_OBD_PORTS.indexOf(p);
      found.sort((a, b) => rank(a.port) - rank(b.port));
      for (const t of found) line(`   [+] Znaleziono: ${t.host}:${t.port}`);
    }
    var scanFound = found;
  }

  // --- 4. Czy brama dziala? --------------------------------------------------
  hr();
  line('4) CZY BRAMA (serwer) DZIALA?');
  const code = await httpGet(`http://127.0.0.1:${config.port}/healthz`);
  if (code === 200) line(`   [OK] Brama odpowiada na 127.0.0.1:${config.port}`);
  else line(`   [X] Brama NIE odpowiada na 127.0.0.1:${config.port} - uruchom tryb START (opcja 3).`);

  // --- 5. WERDYKT ------------------------------------------------------------
  hr();
  line('WERDYKT:');
  if (list.length === 0) {
    line('   * Najpierw USTAW urzadzenie (opcja 2) lub ZNAJDZ adapter (plik 9).');
  } else if (anyReachable) {
    line('   * Komputer w domu WIDZI adapter - most OBD ma z czym gadac. :)');
    line('   * Jesli mimo to "nie przekazuje" w terenie, to problem jest po stronie');
    line('     MECHANIKA/programu. Sprawdz:');
    line('       - czy mechanik uruchomil plik "8 - Polacz OBD w terenie (mechanik).bat",');
    line('       - czy w programie diagnostycznym wybral polaczenie "po sieci/WiFi/TCP",');
    line('       - czy wpisal adres 127.0.0.1 i WLASCIWY port (np. 35000),');
    line('       - czy uzyl tego samego LINKU i HASLA.');
  } else {
    line('   * UWAGA: komputer w domu NIE WIDZI skonfigurowanego adaptera.');
    if (typeof scanFound !== 'undefined' && scanFound && scanFound.length) {
      line(`   * Ale w sieci ODPOWIADA: ${scanFound.map((t) => t.host + ':' + t.port).join(', ')}`);
      line('     -> Prawdopodobnie adapter ma INNY adres/port. Ustaw go w opcji 2.');
    } else {
      line('   * I skan NIC nie znalazl. Najczestsze przyczyny:');
      line('       - adapter robi WLASNA siec WiFi (tryb AP): podlacz ten komputer');
      line('         do sieci adaptera ALBO przestaw adapter na Twoja siec domowa,');
      line('       - adapter jest po USB/Bluetooth, nie po sieci - wtedy ten most go nie');
      line('         dosięgnie (most dziala dla adapterow SIECIOWYCH: WiFi/LAN, TCP/IP),');
      line('       - adapter wylaczony albo nie wpiety do auta.');
    }
  }
  hr();
  line('Skopiuj CALY ten wynik i wyslij - na tej podstawie wskaze dokladna przyczyne.');
  line('');
}

main().catch((e) => { console.error('Blad diagnozy:', e.message); process.exit(1); });
