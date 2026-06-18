'use strict';

/**
 * SZUKACZ ADAPTERA OBD W SIECI DOMOWEJ
 * ----------------------------------------------------------------------------
 * Skanuje Twoja siec domowa i typowe porty OBD/diagnostyczne (35000, 13400, ...),
 * zeby ZNALEZC adres i port adaptera (np. AIR OBD2 / ELM327 WiFi) - bez recznego
 * sprawdzania ustawien sieci.
 *
 * Uzycie:
 *   node src/scan-obd.js                 # skanuje wykryte podsieci domowe
 *   node src/scan-obd.js 192.168.0       # skanuje konkretna podsiec /24
 *   node src/scan-obd.js 192.168.0.10    # sprawdza konkretny adres (wszystkie porty)
 *
 * Wynik: lista znalezionych "adres:port" + gotowy wpis do .env (DEVICES=...).
 */

const { testReachable, localSubnets, COMMON_OBD_PORTS } = require('./probe');

function arg() { return (process.argv[2] || '').trim(); }

async function pool(items, worker, concurrency = 256) {
  const results = [];
  let i = 0;
  const runners = new Array(Math.min(concurrency, items.length)).fill(0).map(async () => {
    while (i < items.length) {
      const idx = i++;
      const r = await worker(items[idx]);
      if (r) results.push(r);
    }
  });
  await Promise.all(runners);
  return results;
}

function buildTargets(spec) {
  // Pojedynczy adres (3 kropki) -> sprawdz wszystkie porty.
  if (/^\d+\.\d+\.\d+\.\d+$/.test(spec)) {
    return COMMON_OBD_PORTS.map((port) => ({ host: spec, port }));
  }
  // Podsiec "a.b.c" -> a.b.c.1..254 x porty.
  let subnets = [];
  if (/^\d+\.\d+\.\d+$/.test(spec)) subnets = [spec];
  else subnets = localSubnets();

  if (subnets.length === 0) {
    console.error('[SKAN] Nie wykryto sieci domowej. Podaj podsiec recznie, np.: node src/scan-obd.js 192.168.0');
    process.exit(1);
  }
  const targets = [];
  for (const sub of subnets) {
    for (let h = 1; h <= 254; h++) {
      for (const port of COMMON_OBD_PORTS) targets.push({ host: `${sub}.${h}`, port });
    }
  }
  return targets;
}

async function main() {
  const spec = arg();
  const targets = buildTargets(spec);
  console.log(`[SKAN] Szukam adaptera OBD... (${targets.length} prob, chwila cierpliwosci)`);

  const found = await pool(targets, async (t) => {
    const ok = await testReachable(t.host, t.port, 800);
    if (ok) { console.log(`   [+] Znaleziono: ${t.host}:${t.port}`); return t; }
    return null;
  });

  console.log('');
  if (found.length === 0) {
    console.log('[SKAN] Nie znalazlem nic na typowych portach OBD.');
    console.log('       Upewnij sie, ze adapter jest wpiety do auta, wlaczony i w tej samej sieci WiFi.');
    console.log('       Mozesz tez podac adres recznie, np.: node src/scan-obd.js 192.168.0.10');
    process.exit(2);
  }

  // Posortuj: najpierw najbardziej "obd-owe" porty.
  const rank = (p) => COMMON_OBD_PORTS.indexOf(p);
  found.sort((a, b) => rank(a.port) - rank(b.port));

  console.log('[SKAN] Znalezione urzadzenia (kandydaci na adapter OBD):');
  const devicesLine = found
    .map((t, i) => `urzadzenie${i + 1}=${t.host}:${t.port}`)
    .join('; ');
  for (const t of found) console.log(`   - ${t.host}:${t.port}`);
  console.log('');
  console.log('Gotowy wpis do pliku .env (mozesz zmienic nazwy):');
  console.log('   DEVICES=' + devicesLine);

  // Maszynowy wynik (dla skryptu PowerShell), w ostatniej linii:
  console.log('JSON:' + JSON.stringify(found));
}

main().catch((e) => { console.error('[SKAN] Blad:', e.message); process.exit(1); });
