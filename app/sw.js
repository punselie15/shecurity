// Keeps Shecurity working offline and shows alerts from your circle when the app is closed.
const CACHE = "shecurity-v13";
const FILES = ["./", "./index.html", "./manifest.webmanifest", "./icon.svg", "./icon-192.png", "./icon-512.png", "./icon-maskable-512.png", "./apple-touch-icon.png", "./favicon-32.png", "./shortcut-sos.png", "./shortcut-walk.png", "./shortcut-timer.png", "./shortcut-call.png", "./vendor/supabase.js"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET" || new URL(e.request.url).origin !== location.origin) return;
  // Network first so updates arrive; cached copy when offline.
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return res;
      })
      .catch(() => caches.match(e.request).then((r) => r || caches.match("./index.html")))
  );
});

self.addEventListener("push", (e) => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch (err) { data = { title: "Shecurity", body: e.data ? e.data.text() : "" }; }
  const title = data.title || "Shecurity";
  e.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || "Open Shecurity",
      icon: "icon-192.png",
      badge: "icon-192.png",
      tag: data.tag || "shecurity",
      renotify: true,
      requireInteraction: !!data.urgent,
      vibrate: data.urgent ? [600, 200, 600, 200, 600] : [200],
      data: { url: data.url || "./#circle" },
    })
  );
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL(e.notification.data && e.notification.data.url ? e.notification.data.url : "./#circle", self.registration.scope).href;
  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.startsWith(self.registration.scope)) { c.navigate(url); return c.focus(); }
      }
      return self.clients.openWindow(url);
    })
  );
});
