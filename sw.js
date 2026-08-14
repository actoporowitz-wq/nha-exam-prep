/* App-shell-only service worker. Deliberately narrow: caches nothing but
   this fixed list of same-origin static files, and the fetch handler
   below bails out (falls through to an untouched network request) for
   anything that isn't an exact match -- in particular every Supabase
   request (different origin entirely: *.supabase.co), which is the one
   thing this app goes out of its way to keep out of client-side storage
   (per-account watermarked exam content, auth tokens). Do not widen the
   match below to a prefix/wildcard without re-checking that guarantee. */
/* Bump this version string on every deploy that changes the app shell in a
   way worth force-invalidating immediately (see the controllerchange
   listener in exam_practice_app.html) -- this file itself had never been
   touched since it was first added, across many deploys, which meant the
   browser's own SW-update byte-diff check had nothing to detect and never
   installed a fresh copy on its own. Combined with no controllerchange
   listener existing at all (the page never reloaded itself even once a new
   SW DID activate), this is the real reason "reload twice" repeatedly
   failed to show a genuinely new deploy across multiple rounds of testing. */
const CACHE_NAME = 'nha-exam-prep-shell-v33';
const SHELL_URLS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_URLS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if(url.origin !== self.location.origin || event.request.method !== 'GET') return;
  if(!SHELL_URLS.includes(url.pathname)) return;

  /* Stale-while-revalidate: serve the cached shell instantly (fast load,
     works offline), but always re-fetch in the background and refresh the
     cache -- so a new deploy shows up on the next load or two without
     needing a hard refresh, rather than being stuck on a stale shell. */
  event.respondWith(
    caches.open(CACHE_NAME).then((cache) =>
      cache.match(event.request).then((cached) => {
        const fetchPromise = fetch(event.request).then((networkResponse) => {
          cache.put(event.request, networkResponse.clone());
          return networkResponse;
        }).catch(() => cached);
        return cached || fetchPromise;
      })
    )
  );
});
