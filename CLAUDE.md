# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A realtime location-sharing PWA for LINE groups: Leaflet + Supabase (Postgres +
Realtime), served as static files from Cloudflare Pages. Thai-language UI.

There is **no build step, no framework, and no package.json**. `index.html` is
the entire application — markup, CSS and JavaScript in one file, loading Leaflet
and supabase-js from CDNs. Edit it directly; nothing compiles it.

## Commands

```bash
node tests/smoke.js        # executes index.html's inline script against browser stubs
tests/migrations.sh        # needs DATABASE_URL pointing at a THROWAWAY database
```

`tests/migrations.sh` applies real DDL and deletes rows — never point it at
production. Against a scratch Postgres in Docker:

```bash
docker run -d --rm --name pgtest -e POSTGRES_PASSWORD=test -e POSTGRES_DB=testdb postgres:16
docker run --rm --network container:pgtest -v "$PWD":/repo:ro \
  -e DATABASE_URL='postgres://postgres:test@127.0.0.1:5432/testdb' \
  postgres:16 bash /repo/tests/migrations.sh
docker stop pgtest
```

Both tests are all-or-nothing scripts — there is no way to run a single case, so
comment out the assertion you are not interested in while iterating.

## Deploy pipeline

Push to `main` runs `.github/workflows/deploy.yml`: a `migrate` job applies
`migrations/*.sql` to the live database, then a `deploy` job (`needs: migrate`)
publishes to Cloudflare Pages. **Schema always lands before the code that needs
it.** A missing `SUPABASE_DB_URL` secret fails the migrate job on purpose rather
than deploying against an unmigrated database.

`SUPABASE_DB_URL` must be the **session pooler** URL (`*.pooler.supabase.com:5432`).
The transaction pooler (6543) cannot run the migrations' DDL, and the direct
connection (`db.*.supabase.co`) is IPv6-only and unreachable from GitHub runners.
`ci.yml`'s `db-preflight` job catches all three mistakes on the PR.

## Migrations

`migrations/` runs automatically on **every** push, so every file there must be
re-runnable — `IF NOT EXISTS`, `DROP ... IF EXISTS` before `CREATE`, `NOT VALID`
on CHECK constraints. `tests/migrations.sh` enforces this by applying the whole
set twice. Anything requiring a dashboard toggle or a coordinated client deploy
does not belong in `migrations/`; see `migrations/README.md`.

`docs/db_schema.sql` is the end state for a fresh project, not something to run
against the existing one. `tests/baseline-schema.sql` is the schema as production
looked at commit `e79616b` and must not be "updated" to match current schema —
it is the starting point the migration test migrates *from*.

## Architecture

### Rooms

The URL hash is the room (`#ทริปเชียงใหม่`). `getRoom()` strips `@` because an
earlier schema encoded the room inside `user_id` as `user_xxxx@room`; that shape
must never reappear. Every table has a `room` column and every query filters on
it server-side. Room names are Thai-friendly and act as the only secret guarding
a room's data.

### Identity and RLS

Each device signs in anonymously at boot (`ensureSession()`), which gives it a
real `auth.uid()` for policies to key on. Rows are stamped with `owner` and
locations can only be updated or deleted by their owner.

**`SELECT` is deliberately left open to `anon`.** Supabase Realtime evaluates RLS
as the subscribing role, so revoking anon's SELECT silences `postgres_changes`
and the app stops being realtime. Do not "fix" this without replacing the
realtime layer. Reading across rooms therefore remains possible for anyone
holding the anon key — `docs/SECURITY.md` is the authority on what is and is not
closed, and why.

Writes go through `withSession()`, which re-authenticates once and retries when a
session has expired or its anonymous user was purged. `routes` and `pins` keep an
open DELETE on purpose: a trip is planned collaboratively, and pins created
before ownership existed have `owner IS NULL`.

### Realtime and the reconciling poll

Realtime handles INSERT and UPDATE. DELETE events are **ignored** — their payload
carries only the primary key, so there is nothing to match on. Removal is handled
by `fetchLocations()`, which runs every 10s and reconciles: rows missing from the
payload lose their marker and list entry. This also covers events missed while
the phone was asleep. Polling pauses on `visibilitychange`.

### Untrusted data from the database

Anyone holding the anon key can write rows, so values arriving from Supabase are
not trusted at render time: `safeIcon()` allowlists against `PIN_ICONS`,
`safeColor()` requires `#rrggbb`, `safeCoord()`/`navUrl()` require finite
numbers. `migrations/002_validation.sql` enforces the same rules in the database.
Adding a new field that reaches the DOM means adding a sanitiser for it.

### Initialization order

All mutable state is declared in one block near the top of the script and all
boot calls sit in one block at the very bottom. This is not stylistic — the app
has shipped a Temporal Dead Zone crash before (commit `179df7b`). `tests/smoke.js`
resolves its Supabase stub *synchronously*, which is stricter than reality, so
using state before its declaration fails in CI rather than on a phone.

### Time windows

Friends are filtered by a rolling 12-hour window (`isRecent`), never by calendar
date — an earlier `isToday()` made everyone sharing at 23:59 vanish at 00:00.
Online/offline is a separate 15-minute threshold. Rows expire server-side after
15 minutes and pg_cron deletes them every 5 minutes.

## Gotchas

- **`_headers`**: Cloudflare Pages *concatenates* values when several rules set
  the same header — a later, more specific rule does not win. Keep `Cache-Control`
  on non-overlapping paths only.
- **`sw.js` is network-first on purpose.** This app fought stale copies in LINE
  Browser hard enough to end up with `no-store` on the app shell; a cache-first
  worker would bring that back. Supabase requests are never cached.
- **`prompt()` does not work in some in-app browsers** (LINE among them). Use
  `askForName()`.
- The Supabase anon key in `index.html` is public by design — the app has no
  backend. Security lives in RLS policies and CHECK constraints, not in hiding it.
- Free-tier Supabase projects pause after ~7 days without requests, which takes
  the whole app down until restored.

## Conventions

- Thai for user-facing strings and documentation; English for code comments and
  commit messages.
- Comments explain *why*, especially where a choice looks wrong without the
  history (the open SELECT, the ignored DELETE events, network-first caching).
- PRs must reference an issue in the body — `ci.yml` enforces it.
- `docs/ROADMAP.md` tracks phases and open issues; keep it current with the code.
