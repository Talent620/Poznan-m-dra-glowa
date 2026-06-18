'use strict';

/**
 * Czyta logs/access.log (JSON-lines) i tworzy ladny raport HTML:
 * kto (adres IP) i kiedy sie laczyl, ile bylo wejsc i logowan.
 * Dostep jest anonimowy, wiec raport pokazuje adresy IP + czas, bez danych osobowych.
 *
 * Uzycie:  node src/log-report.js
 * Wynik:   RAPORT-POLACZEN.html  (w katalogu glownym projektu)
 */

const fs = require('fs');
const path = require('path');

const ACCESS_LOG = path.join(__dirname, '..', 'logs', 'access.log');
const OUT = path.join(__dirname, '..', 'RAPORT-POLACZEN.html');

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

let lines = [];
if (fs.existsSync(ACCESS_LOG)) {
  lines = fs.readFileSync(ACCESS_LOG, 'utf8').split('\n').filter(Boolean);
}

const events = [];
for (const line of lines) {
  try { events.push(JSON.parse(line)); } catch {}
}

// Statystyki
const logins = events.filter((e) => e.type === 'login').length;
const failed = events.filter((e) => e.type === 'login_failed').length;
const visits = events.filter((e) => e.type === 'visit').length;
const ips = new Map(); // ip -> { count, last }
for (const e of events) {
  if (!e.ip) continue;
  const rec = ips.get(e.ip) || { count: 0, last: e.ts };
  rec.count += 1;
  if (e.ts > rec.last) rec.last = e.ts;
  ips.set(e.ip, rec);
}

function fmt(ts) {
  try { return new Date(ts).toLocaleString('pl-PL'); } catch { return ts; }
}

// Ostatnie 200 zdarzen, od najnowszych
const recent = events.slice(-200).reverse();

const typeLabel = {
  login: '<span style="color:#16a34a">zalogowano</span>',
  login_failed: '<span style="color:#dc2626">bledne haslo</span>',
  visit: '<span style="color:#2563eb">wejscie</span>',
};

const rows = recent.map((e) => `
  <tr>
    <td>${escapeHtml(fmt(e.ts))}</td>
    <td>${typeLabel[e.type] || escapeHtml(e.type || '')}</td>
    <td><code>${escapeHtml(e.ip || '')}</code></td>
    <td class="path">${escapeHtml(e.path || '')}</td>
  </tr>`).join('');

const ipRows = [...ips.entries()]
  .sort((a, b) => b[1].count - a[1].count)
  .map(([ip, r]) => `<tr><td><code>${escapeHtml(ip)}</code></td><td>${r.count}</td><td>${escapeHtml(fmt(r.last))}</td></tr>`)
  .join('');

const html = `<!doctype html>
<html lang="pl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Kluczyki Poznań mądra głowa — raport polaczen</title>
<style>
  body { font-family: system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; margin:0; background:#f3f4f6; color:#1f2937; }
  header { background:linear-gradient(135deg,#1e3a8a,#6d28d9); color:#fff; padding:26px 28px; }
  header h1 { margin:0 0 4px; font-size:22px; }
  header p { margin:0; opacity:.85; font-size:13px; }
  .wrap { max-width:980px; margin:0 auto; padding:24px 16px 60px; }
  .cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:14px; margin-bottom:24px; }
  .stat { background:#fff; border-radius:14px; padding:18px; box-shadow:0 4px 14px rgba(0,0,0,.05); }
  .stat .n { font-size:30px; font-weight:800; }
  .stat .l { font-size:12px; color:#6b7280; text-transform:uppercase; letter-spacing:.04em; margin-top:2px; }
  h2 { font-size:16px; margin:26px 0 10px; }
  table { width:100%; border-collapse:collapse; background:#fff; border-radius:12px; overflow:hidden; box-shadow:0 4px 14px rgba(0,0,0,.05); }
  th,td { text-align:left; padding:10px 12px; font-size:13px; border-bottom:1px solid #f1f5f9; }
  th { background:#f8fafc; font-size:11px; text-transform:uppercase; letter-spacing:.04em; color:#6b7280; }
  td.path { color:#6b7280; max-width:340px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  code { background:#f1f5f9; padding:1px 6px; border-radius:6px; }
  .empty { background:#fff; border-radius:12px; padding:30px; text-align:center; color:#6b7280; }
  .foot { margin-top:18px; font-size:12px; color:#9ca3af; }
</style>
</head>
<body>
  <header>
    <h1>Raport polaczen — Kluczyki Poznań mądra głowa</h1>
    <p>Kto i kiedy laczyl sie z narzedziem. Dane anonimowe (adres IP + czas).</p>
  </header>
  <div class="wrap">
    <div class="cards">
      <div class="stat"><div class="n">${visits}</div><div class="l">Wejscia</div></div>
      <div class="stat"><div class="n">${logins}</div><div class="l">Logowania</div></div>
      <div class="stat"><div class="n">${ips.size}</div><div class="l">Unikalne adresy</div></div>
      <div class="stat"><div class="n">${failed}</div><div class="l">Bledne haslo</div></div>
    </div>

    ${events.length === 0 ? '<div class="empty">Brak zarejestrowanych polaczen. Raport wypelni sie, gdy ktos sie zaloguje.</div>' : `
    <h2>Adresy (od najaktywniejszych)</h2>
    <table>
      <thead><tr><th>Adres IP</th><th>Liczba zdarzen</th><th>Ostatnio</th></tr></thead>
      <tbody>${ipRows}</tbody>
    </table>

    <h2>Ostatnie zdarzenia (max 200)</h2>
    <table>
      <thead><tr><th>Czas</th><th>Zdarzenie</th><th>Adres IP</th><th>Strona</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`}

    <div class="foot">Wygenerowano ${new Date().toLocaleString('pl-PL')}</div>
  </div>
</body>
</html>`;

fs.writeFileSync(OUT, html, 'utf8');
console.log(OUT);
