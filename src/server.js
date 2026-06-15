'use strict';

/**
 * REKLAMA GATEWAY
 * ----------------------------------------------------------------------------
 * Brama, ktora:
 *   1. wymaga jednego wspolnego hasla (dostep anonimowy, bez kont),
 *   2. po zalogowaniu przekierowuje ruch do Twojego narzedzia webowego
 *      (reverse-proxy z obsluga WebSocketow) ALBO serwuje pliki statyczne
 *      ALBO pokazuje strone powitalna,
 *   3. nasluchuje tylko lokalnie - na swiat wystawia ja tunel Cloudflare.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const config = require('./config');
const auth = require('./auth');
const obdWs = require('./obd-ws');

const VIEWS = path.join(__dirname, 'views');
const LOG_DIR = path.join(__dirname, '..', 'logs');
const ACCESS_LOG = path.join(LOG_DIR, 'access.log');

try { fs.mkdirSync(LOG_DIR, { recursive: true }); } catch {}

// --- Rejestr polaczen (kto i kiedy sie laczyl) ------------------------------
// Zapisujemy zdarzenia w formacie JSON-lines do logs/access.log.
// Dostep jest anonimowy, wiec logujemy adres IP + czas, bez danych osobowych.

function logEvent(type, req, extra = {}) {
  const entry = {
    ts: new Date().toISOString(),
    type,
    ip: (req.ip || req.connection?.remoteAddress || 'unknown').replace('::ffff:', ''),
    // Logujemy sciezke BEZ czesci po "?" - dzieki temu zaden ewentualny
    // sekret w adresie (np. stare ?key=...) nie trafi do pliku z logami.
    path: (req.originalUrl || req.url || '').split('?')[0],
    ua: (req.headers['user-agent'] || '').slice(0, 200),
    ...extra,
  };
  fs.appendFile(ACCESS_LOG, JSON.stringify(entry) + '\n', () => {});
}

// Pomijamy zasoby statyczne (css/js/grafika) - logujemy realne wejscia.
const ASSET_RE = /\.(css|js|mjs|png|jpe?g|gif|svg|ico|webp|woff2?|ttf|eot|map)$/i;

// --- Walidacja startowa -----------------------------------------------------

const errors = config.validate();
if (errors.length) {
  console.error('\n[Kluczyki Poznan] Nie moge wystartowac - popraw konfiguracje:\n');
  for (const e of errors) console.error('  - ' + e);
  console.error('');
  process.exit(1);
}

const app = express();
if (config.trustProxy) app.set('trust proxy', 1);
app.disable('x-powered-by');

// --- Naglowki bezpieczenstwa ------------------------------------------------

app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow'); // nie indeksowac w wyszukiwarkach
  next();
});

// --- Pomocnicze: renderowanie prostych widokow ------------------------------

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function render(res, file, replacements = {}, status = 200) {
  let html = fs.readFileSync(path.join(VIEWS, file), 'utf8');
  for (const [key, val] of Object.entries(replacements)) {
    html = html.replaceAll(`{{${key}}}`, val);
  }
  res.status(status).type('html').send(html);
}

// Buduje gotowy blok komunikatu bledu (lub pusty string).
function errorBlock(message) {
  return message ? `<div class="error">${escapeHtml(message)}</div>` : '';
}

function clientIp(req) {
  return req.ip || req.connection?.remoteAddress || 'unknown';
}

// Lekka ochrona przed CSRF na formularzu logowania.
// Jesli przegladarka przysle naglowek Origin, jego host musi zgadzac sie z
// hostem, pod ktorym dziala brama (Host lub X-Forwarded-Host od tunelu).
// Gdy Origin nie ma (np. dostep bezposredni, starsze przegladarki) - nie
// blokujemy; dodatkowo chroni nas SameSite=Lax na ciasteczku sesji.
function sameOriginPost(req) {
  const origin = req.headers['origin'];
  if (!origin) return true;
  let originHost;
  try { originHost = new URL(origin).host; } catch { return false; }
  const candidates = [req.headers['host'], req.headers['x-forwarded-host']]
    .filter(Boolean)
    .map((h) => String(h).split(',')[0].trim());
  return candidates.includes(originHost);
}

// Pomocnik dla endpointow OBD po HTTP: limit prob (lockout) wspolny z /login.
// Zwraca true, gdy zadanie zostalo obsluzone (odrzucone) - wtedy handler konczy.
function obdHttpAuthFails(req, res) {
  const ip = clientIp(req);
  if (auth.isLockedOut(ip)) {
    res.status(429).type('text').send('Zbyt wiele prob. Sprobuj ponownie za kilka minut.');
    return true;
  }
  if (auth.isAuthenticated(req) || obd.isAuthorized(req)) {
    auth.clearAttempts(ip);
    return false;
  }
  auth.recordFailure(ip);
  res.status(401).type('text').send('Unauthorized');
  return true;
}

// --- Most OBD przez WebSocket (wiele urzadzen) ------------------------------
// Pozwala diagnostyce OBD2 dzialac przez zwykly link Cloudflare (bez Tailscale).
// Aktywny, gdy w .env sa urzadzenia (DEVICE_PORT lub DEVICES).
const obd = obdWs.attach();

// --- Endpoint zdrowia (bez autoryzacji) -------------------------------------

app.get('/healthz', (req, res) => {
  res.type('text').send('ok');
});

// --- Lista urzadzen OBD (dla klienta w terenie) -----------------------------
// Autoryzacja wspolnym haslem (?key=...) lub wazna sesja. Zwraca tylko NAZWY
// urzadzen i czy sa zajete - bez ujawniania adresow/portow z sieci domowej.
app.get('/obd-devices', (req, res) => {
  if (obdHttpAuthFails(req, res)) return; // 401/429 + limit prob
  res.json({ enabled: obd.enabled, devices: obd.listDevices() });
});

// Status urzadzen z testem dostepnosci (online/offline + zajete) - dla panelu WWW.
app.get('/obd-status', async (req, res) => {
  if (obdHttpAuthFails(req, res)) return; // 401/429 + limit prob
  try {
    const list = obd.enabled ? await obd.statusDevices() : [];
    res.json({ enabled: obd.enabled, devices: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Logowanie / wylogowanie ------------------------------------------------

app.get('/login', (req, res) => {
  if (auth.isAuthenticated(req)) return res.redirect('/');
  render(res, 'login.html', { BRAND: config.brandName, ERROR: '' });
});

// Maly parser formularza, bez dodatkowych zaleznosci.
app.use('/login', express.urlencoded({ extended: false, limit: '4kb' }));

app.post('/login', (req, res) => {
  const ip = clientIp(req);

  // Ochrona CSRF: odrzucamy zadania z obcej strony (zly Origin).
  if (!sameOriginPost(req)) {
    return render(res, 'login.html', {
      BRAND: config.brandName,
      ERROR: errorBlock('Blad bezpieczenstwa (zle zrodlo zadania). Otworz strone logowania na nowo.'),
    }, 403);
  }

  if (auth.isLockedOut(ip)) {
    return render(res, 'login.html', {
      BRAND: config.brandName,
      ERROR: errorBlock('Zbyt wiele prob. Sprobuj ponownie za kilka minut.'),
    }, 429);
  }

  const password = (req.body && req.body.password) || '';
  if (auth.passwordMatches(password)) {
    auth.clearAttempts(ip);
    logEvent('login', req); // udane logowanie
    res.setHeader('Set-Cookie', auth.buildSessionCookie(req.secure));
    return res.redirect('/');
  }

  auth.recordFailure(ip);
  logEvent('login_failed', req); // nieudana proba
  return render(res, 'login.html', {
    BRAND: config.brandName,
    ERROR: errorBlock('Nieprawidlowe haslo.'),
  }, 401);
});

app.get('/logout', (req, res) => {
  res.setHeader('Set-Cookie', auth.clearSessionCookie(req.secure));
  res.redirect('/login');
});

// --- Bramka autoryzacji dla calej reszty ------------------------------------

app.use((req, res, next) => {
  if (auth.isAuthenticated(req)) return next();
  // Zapytania "API/XHR" dostaja 401, przegladarka - przekierowanie na login.
  const accepts = req.headers['accept'] || '';
  if (!accepts.includes('text/html')) {
    return res.status(401).type('text').send('Unauthorized');
  }
  return res.redirect('/login');
});

// Rejestrujemy realne wejscia zalogowanych (pomijamy zasoby statyczne).
app.use((req, res, next) => {
  if (!ASSET_RE.test(req.path)) logEvent('visit', req);
  next();
});

// --- Za bramka: proxy / pliki statyczne / strona powitalna ------------------

let proxyMiddleware = null;

if (config.upstreamUrl) {
  proxyMiddleware = createProxyMiddleware({
    target: config.upstreamUrl,
    changeOrigin: true,
    ws: true,
    xfwd: true,
    logger: console,
    on: {
      error(err, req, res) {
        console.error('[proxy] blad polaczenia z UPSTREAM_URL:', err.message);
        if (res && res.writeHead && !res.headersSent) {
          res.writeHead(502, { 'Content-Type': 'text/html; charset=utf-8' });
        }
        if (res && res.end) {
          res.end(
            '<h1>502 - narzedzie chwilowo niedostepne</h1>' +
            '<p>Brama dziala, ale nie moze polaczyc sie z Twoim narzedziem ' +
            `(${config.upstreamUrl}). Sprawdz, czy aplikacja jest uruchomiona.</p>`
          );
        }
      },
    },
  });
  app.use(proxyMiddleware);
  console.log(`[Kluczyki Poznan] Reverse-proxy -> ${config.upstreamUrl}`);
} else if (config.staticDir) {
  const dir = path.resolve(config.staticDir);
  app.use(express.static(dir));
  app.get('*', (req, res) => render(res, 'landing.html', {
    BRAND: config.brandName,
    MODE: `Serwuje pliki z: ${dir}`,
  }));
  console.log(`[Kluczyki Poznan] Serwuje pliki statyczne z: ${dir}`);
} else if (obd.enabled) {
  // Brak narzedzia webowego, ale sa urzadzenia OBD -> pokaz panel OBD.
  app.get('*', (req, res) => render(res, 'panel.html', { BRAND: config.brandName }));
  console.log('[Kluczyki Poznan] Tryb panelu OBD (podglad urzadzen).');
} else {
  app.get('*', (req, res) => render(res, 'landing.html', {
    BRAND: config.brandName,
    MODE: 'Tryb powitalny - ustaw UPSTREAM_URL w pliku .env, aby podlaczyc swoje narzedzie.',
  }));
  console.log('[Kluczyki Poznan] Brak UPSTREAM_URL/STATIC_DIR - tryb strony powitalnej.');
}

// --- Start serwera + obsluga WebSocketow ------------------------------------

const server = http.createServer(app);

if (obd.enabled) {
  console.log('[Kluczyki Poznan] Most OBD przez WebSocket aktywny na sciezce /obd');
}

// WebSockety: obslugujemy upgrade dla mostu OBD oraz dla narzedzia (proxy).
server.on('upgrade', (req, socket, head) => {
  // 1) Most OBD ma wlasna autoryzacje (haslo w ?key=... lub wazna sesja).
  if (obd.isObdUpgrade(req)) {
    obd.handleUpgrade(req, socket, head);
    return;
  }
  // 2) WebSockety narzedzia (np. panel webowy) - tylko dla zalogowanych.
  if (proxyMiddleware && proxyMiddleware.upgrade) {
    if (!auth.isAuthenticated(req)) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    proxyMiddleware.upgrade(req, socket, head);
    return;
  }
  // 3) Nikt nie obsluguje tego upgrade.
  socket.destroy();
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`\n[Kluczyki Poznan] Port ${config.port} jest juz zajety przez inny program.`);
    console.error('  -> Zamknij drugi uruchomiony serwer (albo zmien PORT w pliku .env) i sprobuj ponownie.\n');
  } else {
    console.error('\n[Kluczyki Poznan] Blad serwera: ' + e.message + '\n');
  }
  process.exit(1);
});

server.listen(config.port, config.host, () => {
  console.log('');
  console.log('  Serwer dziala (Kluczyki Poznan madra glowa)');
  console.log(`  Lokalnie:  http://${config.host}:${config.port}`);
  console.log(`  Dostep:    chroniony wspolnym haslem (bez kont)`);
  console.log('  Na swiat wystawia go tunel Cloudflare (patrz okno cloudflared / share-info.txt).');
  console.log('');
});

// Czyste zamkniecie.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log(`\n[Kluczyki Poznan] Otrzymano ${sig}, zamykam...`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  });
}
