// Offline shell for the course player: the page, its key and the encrypted list stay usable without internet.
// Network first (so updates arrive), cached copy when offline. Downloaded recordings live in the "pl-videos" cache,
// which the page reads itself; lecture notes (notes/*.enc) are cached as they are opened; this worker never touches cross-origin requests.
const SHELL = "pl-shell-v2";
const FILES = ["./", "./index.html", "./videos.json.enc", "../key.json", "./manifest.webmanifest"];
self.addEventListener("install", e => { e.waitUntil(caches.open(SHELL).then(c => c.addAll(FILES)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(self.clients.claim()); });
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(fetch(e.request).then(r => {
    if (r.ok && (FILES.some(f => new URL(f, self.registration.scope).pathname === u.pathname) || /\/notes\/[^/]+\.enc$/.test(u.pathname))) { const c = r.clone(); caches.open(SHELL).then(x => x.put(u.pathname, c)); }
    return r;
  }).catch(() => caches.match(u.pathname).then(r => r || Response.error())));
});
