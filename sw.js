/*
 * Service worker — network-first, cache only as an offline fallback.
 *
 * Deliberately NOT cache-first: this app fought stale copies inside LINE
 * Browser hard enough to end up with no-store headers everywhere, and a
 * cache-first worker would hand that problem straight back. Online users
 * always get the live file; the cache only speaks up when the network fails.
 */
const CACHE = 'location-share-v1';

// Local shell only. CDN assets get cached opportunistically on first use.
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE)
      // Individually, so one bad URL can't fail the whole install.
      .then(cache => Promise.allSettled(PRECACHE.map(url => cache.add(url))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;

  if (req.method !== 'GET') return;

  // Never cache Supabase — realtime and REST must always hit the network,
  // and serving a stale location would be worse than showing nothing.
  const url = new URL(req.url);
  if (url.hostname.endsWith('.supabase.co')) return;

  event.respondWith(
    fetch(req)
      .then(res => {
        // Opaque cross-origin responses (CDN) are still worth keeping for offline.
        if (res && (res.ok || res.type === 'opaque')) {
          const copy = res.clone();
          caches.open(CACHE).then(cache => cache.put(req, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() =>
        caches.match(req).then(hit =>
          hit || (req.mode === 'navigate' ? caches.match('./index.html') : undefined)
        )
      )
  );
});
