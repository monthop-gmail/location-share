/*
 * Smoke test — run with: node tests/smoke.js
 *
 * There is no build step and no browser in CI, so this executes index.html's
 * inline script against minimal browser stubs. It exists to catch two things
 * that have actually broken this app before:
 *
 *   1. Initialization-order crashes (Temporal Dead Zone). The Supabase stub
 *      resolves queries SYNCHRONOUSLY on purpose — stricter than reality — so
 *      any state used before its declaration fails here instead of on a phone.
 *   2. Untrusted values from the database reaching the DOM unfiltered.
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const REPO = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(REPO, 'index.html'), 'utf8');

// --- ids that really exist in the markup ---
const realIds = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]));
const missing = [];

const listeners = {};
const makeEl = (id) => ({
  id,
  value: '',
  style: {},
  dataset: {},
  classList: { add() {}, remove() {}, contains: () => false },
  textContent: '',
  innerHTML: '',
  innerText: '',
  appendChild() {},
  remove() {},
  focus() {},
  addEventListener() {},
  removeEventListener() {},
  querySelector: () => makeEl('q'),
  querySelectorAll: () => [],
  closest: () => makeEl('c'),
});

const document = {
  title: '',
  hidden: false,
  createElement: (tag) => makeEl(tag),
  getElementById(id) {
    if (!realIds.has(id)) missing.push(id);
    return realIds.has(id) ? makeEl(id) : null;
  },
  querySelector: () => makeEl('q'),
  querySelectorAll: () => [],
  addEventListener(t, fn) { (listeners[t] ||= []).push(fn); },
  body: makeEl('body'),
};

// Chainable Leaflet stub
const leafletObj = new Proxy(function () {}, {
  get: (t, p) => {
    if (p === 'then') return undefined;
    if (p === 'length') return 0;
    if (p === 'getLayers') return () => [];
    if (p === Symbol.toPrimitive) return () => 0;
    return leafletObj;
  },
  apply: () => leafletObj,
  construct: () => leafletObj,
});
const L = new Proxy({}, {
  get: (t, p) => {
    if (p === 'Draw') return undefined; // simulate the plugin not being ready
    return leafletObj;
  },
});

// Supabase stub: thenable query builder, resolves to an empty result set
const query = new Proxy({}, {
  get: (t, p) => {
    if (p === 'then') return (fn) => { fn({ data: [], error: null }); return Promise.resolve(); };
    return () => query;
  },
});
const channel = { on: () => channel, subscribe: () => channel };
const supabase = {
  createClient: () => ({
    from: () => query,
    channel: () => channel,
    removeChannel: () => {},
  }),
};

const store = {};
const sandbox = {
  document,
  L,
  supabase,
  console,
  setInterval: () => 1,
  clearInterval: () => {},
  setTimeout: () => 1,
  Promise, Date, Math, Number, Set, Map, Array, Object, JSON, String, RegExp, Error, isNaN,
  URL,
  alert: (m) => { throw new Error('unexpected alert(): ' + m); },
  confirm: () => true,
  localStorage: {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
  },
  navigator: { geolocation: { watchPosition: () => 1, clearWatch() {} }, serviceWorker: undefined },
};
sandbox.window = {
  location: { hash: '#ทริปเชียงใหม่' },
  addEventListener(t, fn) { (listeners[t] ||= []).push(fn); },
};
sandbox.globalThis = sandbox;

const code = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');

let failed = false;
try {
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: 'index.html' });
  console.log('✅ script executed to completion (no init-order errors)');
} catch (e) {
  failed = true;
  console.log('❌ runtime error during init: ' + e.message);
  console.log(e.stack.split('\n').slice(0, 4).join('\n'));
}

// Exercise the room parser + sanitizers directly
const checks = [
  ['getRoom strips @', () => sandbox.getRoom() === 'ทริปเชียงใหม่'],
  ['safeIcon allows known', () => sandbox.safeIcon('🏁') === '🏁'],
  ['safeIcon rejects HTML', () => sandbox.safeIcon('<img src=x onerror=alert(1)>') === '📍'],
  ['safeColor allows hex', () => sandbox.safeColor('#FF5252') === '#FF5252'],
  ['safeColor rejects breakout', () => sandbox.safeColor('#fff" onmouseover="alert(1)') === '#3388ff'],
  ['safeCoord rejects junk', () => sandbox.safeCoord('abc') === null],
  ['navUrl rejects junk', () => sandbox.navUrl('a', 'b') === null],
  ['navUrl builds url', () => sandbox.navUrl('13.75', 100.5) === 'https://www.google.com/maps/dir/?api=1&destination=13.75,100.5'],
  ['isInBounds rejects junk', () => sandbox.isInBounds({ lat: 'x', lng: 'y' }) === false],
  ['isInBounds accepts BKK', () => sandbox.isInBounds({ lat: 13.75, lng: 100.5 }) === true],
  ['isRecent rejects old', () => sandbox.isRecent({ updated_at: '2020-01-01T00:00:00Z' }) === false],
  ['isRecent accepts now', () => sandbox.isRecent({ updated_at: new Date().toISOString() }) === true],
  ['isRecent survives midnight', () => {
    const d = new Date(); d.setHours(0, 5, 0, 0);           // 00:05 today
    const earlier = new Date(d.getTime() - 10 * 60 * 1000); // 23:55 yesterday
    return sandbox.isRecent({ updated_at: earlier.toISOString() }) === true;
  }],
  ['shouldShow rejects other room', () => sandbox.shouldShow({
    user_id: 'someone', room: 'อื่น', lat: 13.75, lng: 100.5, updated_at: new Date().toISOString(),
  }) === false],
  ['shouldShow accepts same room', () => sandbox.shouldShow({
    user_id: 'someone', room: 'ทริปเชียงใหม่', lat: 13.75, lng: 100.5, updated_at: new Date().toISOString(),
  }) === true],
];

if (!failed) {
  for (const [name, fn] of checks) {
    let ok = false, err = '';
    try { ok = fn(); } catch (e) { err = ' (' + e.message + ')'; }
    console.log((ok ? '  ✅ ' : '  ❌ ') + name + err);
    if (!ok) failed = true;
  }
}

if (missing.length) {
  console.log('❌ getElementById on ids not present in markup: ' + [...new Set(missing)].join(', '));
  failed = true;
} else {
  console.log('✅ every getElementById target exists in the markup');
}

process.exit(failed ? 1 : 0);
