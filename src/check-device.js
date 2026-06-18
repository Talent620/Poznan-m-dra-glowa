'use strict';

/**
 * SZYBKI TEST ADAPTERA - czy ten komputer WIDZI skonfigurowane urzadzenia OBD?
 * Uruchamiany przez kreator zaraz po ustawieniu adaptera. Nic nie zmienia.
 *
 * Kody wyjscia (dla skryptu PowerShell):
 *   0 - wszystkie adaptery odpowiadaja (wszystko gra),
 *   3 - czesc odpowiada, czesc nie,
 *   1 - zaden nie odpowiada,
 *   2 - nie ustawiono zadnego adaptera.
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const devices = require('./devices');
const { testReachable } = require('./probe');

(async () => {
  const list = devices.getDevices();
  if (list.length === 0) {
    console.log('BRAK: nie ustawiono zadnego adaptera.');
    process.exit(2);
  }

  let okCount = 0;
  for (const d of list) {
    const ok = await testReachable(d.host, d.port, 1500);
    console.log(`${ok ? '[OK] WIDZE  ' : '[X]  NIE WIDZE'}  ${d.name}  (${d.host}:${d.port})`);
    if (ok) okCount++;
  }

  if (okCount === list.length) process.exit(0);
  if (okCount > 0) process.exit(3);
  process.exit(1);
})().catch((e) => { console.error('Blad testu:', e.message); process.exit(1); });
