'use strict';

/**
 * Generuje ladna, samodzielna strone HTML z linkiem dostepu, haslem i kodem QR.
 * Kod QR powstaje LOKALNIE (biblioteka qrcode) - nic nie jest wysylane na zewnatrz.
 *
 * Uzycie:
 *   node src/share-page.js --mode shared  --url <link> --password <haslo> --out <plik.html>
 *   node src/share-page.js --mode private --url <link> --password <haslo> --out <plik.html>
 */

const fs = require('fs');
const QRCode = require('qrcode');

function arg(name, def = '') {
  const i = process.argv.indexOf('--' + name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

const mode = arg('mode', 'shared');
const url = arg('url', '');
const password = arg('password', '');
const out = arg('out', mode === 'private' ? 'UDOSTEPNIJ-PRYWATNY.html' : 'UDOSTEPNIJ-PRACOWNIKOM.html');

const isPrivate = mode === 'private';
const title = isPrivate ? 'Twoj prywatny dostep' : 'Dostep dla pracownikow';
const lead = isPrivate
  ? 'Ten adres dziala tylko na Twoich urzadzeniach zalogowanych do Twojej sieci Tailscale.'
  : 'Wyslij ten link i haslo pracownikom. Moga tez zeskanowac kod QR telefonem.';

async function main() {
  let qrDataUrl = '';
  if (url) {
    qrDataUrl = await QRCode.toDataURL(url, { width: 320, margin: 2, errorCorrectionLevel: 'M' });
  }

  const html = `<!doctype html>
<html lang="pl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex, nofollow" />
<title>Kluczyki Poznań mądra głowa — ${escapeHtml(title)}</title>
<style>
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; display:grid; place-items:center;
    font-family: system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
    background: linear-gradient(135deg,#0f172a,#4c1d95); padding:24px; }
  .card { width:100%; max-width:460px; background:#fff; color:#1f2937;
    border-radius:18px; padding:30px; box-shadow:0 24px 70px rgba(0,0,0,.4); text-align:center; }
  h1 { font-size:22px; margin:0 0 6px; }
  .lead { color:#6b7280; font-size:14px; margin:0 0 22px; }
  .qr { background:#fff; border:1px solid #e5e7eb; border-radius:14px; padding:14px; display:inline-block; }
  .qr img { display:block; width:260px; height:260px; }
  .field { text-align:left; margin-top:18px; }
  .field label { display:block; font-size:12px; font-weight:700; color:#6b7280; text-transform:uppercase; letter-spacing:.04em; margin-bottom:6px; }
  .row { display:flex; gap:8px; }
  .row input { flex:1; padding:11px 12px; border:1px solid #d1d5db; border-radius:10px; font-size:14px; background:#f9fafb; }
  .row button { padding:11px 14px; border:0; border-radius:10px; cursor:pointer; font-weight:700;
    background:linear-gradient(135deg,#2563eb,#7c3aed); color:#fff; }
  .row button:active { transform:scale(.97); }
  .open { display:inline-block; margin-top:20px; padding:12px 18px; border-radius:10px; text-decoration:none;
    background:#111827; color:#fff; font-weight:700; font-size:14px; }
  .steps { text-align:left; margin:22px 0 0; padding:16px; background:#f3f4f6; border-radius:12px; font-size:13px; color:#374151; }
  .steps b { color:#111827; }
  .foot { margin-top:18px; font-size:11px; color:#9ca3af; }
</style>
</head>
<body>
  <div class="card">
    <h1>${escapeHtml(title)}</h1>
    <p class="lead">${escapeHtml(lead)}</p>

    ${qrDataUrl ? `<div class="qr"><img alt="Kod QR z linkiem" src="${qrDataUrl}" /></div>` : '<p style="color:#b91c1c">Brak adresu — uruchom serwer, aby wygenerowac link.</p>'}

    <div class="field">
      <label>Link</label>
      <div class="row">
        <input id="url" readonly value="${escapeHtml(url)}" />
        <button onclick="copy('url',this)">Kopiuj</button>
      </div>
    </div>

    <div class="field">
      <label>Haslo</label>
      <div class="row">
        <input id="pwd" readonly value="${escapeHtml(password)}" />
        <button onclick="copy('pwd',this)">Kopiuj</button>
      </div>
    </div>

    ${url ? `<a class="open" href="${escapeHtml(url)}" target="_blank" rel="noopener">Otworz narzedzie</a>` : ''}

    <div class="steps">
      <b>Instrukcja:</b><br/>
      1. Otworz link (lub zeskanuj kod QR telefonem).<br/>
      2. Wpisz haslo.<br/>
      3. Gotowe — korzystaj z narzedzia.
    </div>

    <div class="foot">Wygenerowano ${new Date().toLocaleString('pl-PL')} • polaczenie szyfrowane</div>
  </div>

<script>
  function copy(id, btn){
    const el = document.getElementById(id);
    el.select(); el.setSelectionRange(0, 9999);
    navigator.clipboard.writeText(el.value).then(()=>{
      const t = btn.textContent; btn.textContent = 'Skopiowano!';
      setTimeout(()=>btn.textContent = t, 1200);
    }).catch(()=>{ document.execCommand('copy'); });
  }
</script>
</body>
</html>`;

  fs.writeFileSync(out, html, 'utf8');
  console.log(out);
}

main().catch((e) => { console.error('share-page error:', e.message); process.exit(1); });
