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

// Anonymous auth stub. authCalls lets the checks below assert that the app
// reuses an existing session instead of minting a user on every page load.
const authCalls = { getSession: 0, signInAnonymously: 0, signOut: 0 };
let storedSession = null;

const auth = {
  getSession: async () => { authCalls.getSession++; return { data: { session: storedSession } }; },
  signInAnonymously: async () => {
    authCalls.signInAnonymously++;
    storedSession = { user: { id: '00000000-0000-4000-8000-000000000001', is_anonymous: true } };
    return { data: { session: storedSession }, error: null };
  },
  signOut: async () => { authCalls.signOut++; storedSession = null; return { error: null }; },
};

const supabase = {
  createClient: () => ({
    from: () => query,
    channel: () => channel,
    removeChannel: () => {},
    auth,
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
const ago = (ms) => sandbox.isRecent({ updated_at: new Date(Date.now() - ms).toISOString() });

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
  ['isRecent rejects an unparseable timestamp', () => sandbox.isRecent({ updated_at: 'not a date' }) === false],

  // The midnight bug was isToday() keying off the calendar date in Asia/Bangkok,
  // so 23:59 vanished at 00:00. These pin the replacement to elapsed time and
  // nothing else — which is what makes the calendar boundary irrelevant. Written
  // as fixed offsets from now so the result cannot depend on the hour CI runs at.
  ['isRecent keeps a row from 10 minutes ago', () => ago(10 * 60 * 1000) === true],
  ['isRecent keeps a row from 11h59m ago', () => ago(11 * 3600e3 + 59 * 60e3) === true],
  ['isRecent drops a row from 12h01m ago', () => ago(12 * 3600e3 + 60e3) === false],
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

// Auth behaviour is async, so it runs after the synchronous checks above.
async function authChecks() {
  const results = [];
  const t = (name, ok) => results.push([name, ok]);

  // Boot deliberately does not await its sign-in, and top-level `let` bindings
  // are not properties of the vm global, so the promise cannot be reached from
  // out here. Drain the microtask queue instead — the auth stubs resolve
  // immediately, so one macrotask boundary is enough to settle the whole chain.
  const settle = () => new Promise(resolve => setImmediate(resolve));
  await settle();
  await settle();

  // Exactly one: a second sign-in per load would mint a second anonymous user
  // in auth.users every time anyone opens the app.
  t('boot signed in anonymously exactly once', authCalls.signInAnonymously === 1);

  const before = authCalls.signInAnonymously;
  await sandbox.ensureSession();
  t('an existing session is reused, not replaced', authCalls.signInAnonymously === before);

  t('requireSession passes once signed in', await sandbox.requireSession() === true);

  // RLS rejections arrive as ordinary error objects; they must be recognised
  // so the retry path fires instead of the user seeing a Postgres error.
  t('RLS rejection counts as an auth error',
    sandbox.isAuthError({ code: '42501', message: 'new row violates row-level security policy' }) === true);
  t('expired JWT counts as an auth error',
    sandbox.isAuthError({ message: 'JWT expired' }) === true);
  t('a constraint violation does not',
    sandbox.isAuthError({ code: '23514', message: 'violates check constraint' }) === false);
  t('no error is not an auth error', sandbox.isAuthError(null) === false);

  // A stale session must cost one silent re-auth and a retry, not a visible failure.
  const signOutsBefore = authCalls.signOut;
  let attempts = 0;
  const res = await sandbox.withSession(async () => {
    attempts++;
    return attempts === 1
      ? { error: { code: '42501', message: 'row-level security' } }
      : { error: null, data: [] };
  });
  t('a stale session is retried once and succeeds', attempts === 2 && !res.error);
  t('the retry signed out first', authCalls.signOut === signOutsBefore + 1);

  return results;
}

(async () => {
  if (!failed) {
    for (const [name, ok] of await authChecks()) {
      console.log((ok ? '  ✅ ' : '  ❌ ') + name);
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
})();
