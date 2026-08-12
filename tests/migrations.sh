#!/usr/bin/env bash
#
# Proves migrations/ takes the real production schema to the intended end state.
#
# CI runs migrations against the live database on every push to main, so a
# broken migration would be a production incident, not a failed build. This
# rehearses the whole thing against a throwaway Postgres first:
#
#   1. load the schema as production actually looks today (tests/baseline-schema.sql)
#   2. apply migrations/ in order
#   3. apply them a SECOND time — they must be safe to re-run, because CI
#      re-runs them on every single push
#   4. assert the end state
#
# Usage: DATABASE_URL=postgres://... tests/migrations.sh
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL to a scratch database — this script drops objects}"
cd "$(dirname "$0")/.."

psql() { command psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q "$@"; }

echo "→ baseline (schema as of e79616b)"
psql -f tests/baseline-schema.sql

# Rows in the old "user_xxxx@room" format, so the backfill has something to chew on
echo "→ seeding pre-migration rows"
psql -c "
  INSERT INTO public.locations (user_id, lat, lng, display_name) VALUES
    ('user_aaa',            13.75, 100.50, 'ห้อง main'),
    ('user_aaa@ทริปเชียงใหม่', 18.79,  98.98, 'คนเดียวกัน อีกห้อง'),
    ('user_bbb@ทริปเชียงใหม่', 18.80,  98.99, 'อีกคน');
"

# 001 is checked on its own: later migrations legitimately delete the rows it
# backfills, so the backfill can only be observed here.
echo "→ applying 001 and checking the backfill"
psql -f migrations/001_rooms.sql

check() {
  local label="$1" sql="$2" got
  got=$(command psql "$DATABASE_URL" -tAc "$sql")
  if [ "$got" = "t" ]; then echo "   ✅ $label"; else echo "   ❌ $label (got '$got')"; exit 1; fi
}

check "old user_id@room split into user_id + room" \
  "SELECT NOT EXISTS (SELECT 1 FROM public.locations WHERE user_id LIKE '%@%');"
check "backfilled room values landed" \
  "SELECT count(*) = 2 FROM public.locations WHERE room = 'ทริปเชียงใหม่';"
check "same person kept both rooms" \
  "SELECT count(*) = 2 FROM public.locations WHERE user_id = 'user_aaa';"

for pass in 1 2; do
  echo "→ applying the full set (pass $pass)"
  for f in migrations/*.sql; do
    echo "   $f"
    psql -f "$f"
  done
done

check "004 cleared locations that predate ownership" \
  "SELECT NOT EXISTS (SELECT 1 FROM public.locations WHERE owner IS NULL);"

echo "→ asserting end state"
assert() {
  local label="$1" sql="$2"
  local got
  got=$(command psql "$DATABASE_URL" -tAc "$sql")
  if [ "$got" = "t" ]; then
    echo "   ✅ $label"
  else
    echo "   ❌ $label (got '$got')"
    exit 1
  fi
}

assert "locations.room exists" "
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='locations' AND column_name='room');"

assert "unique moved to (user_id, room)" "
  SELECT EXISTS (SELECT 1 FROM pg_indexes
                 WHERE tablename='locations' AND indexname='locations_user_id_room_key');"

assert "old single-column unique is gone" "
  SELECT NOT EXISTS (SELECT 1 FROM pg_constraint
                     WHERE conname='locations_user_id_key');"

assert "validation constraints present" "
  SELECT count(*) = 11 FROM pg_constraint
  WHERE contype='c' AND conname LIKE '%_chk'
    AND conrelid IN ('public.locations'::regclass,
                     'public.routes'::regclass,
                     'public.pins'::regclass);"

assert "cleanup function exists" "
  SELECT to_regprocedure('delete_expired_locations()') IS NOT NULL;"

assert "owner columns exist on all three tables" "
  SELECT count(*) = 3 FROM information_schema.columns
  WHERE table_schema='public' AND column_name='owner'
    AND table_name IN ('locations','routes','pins');"

# The constraints must actually bite — this is the XSS hole they close
echo "→ checking constraints reject bad rows"
reject() {
  local label="$1" sql="$2"
  if command psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "$sql" >/dev/null 2>&1; then
    echo "   ❌ $label — insert was allowed"
    exit 1
  fi
  echo "   ✅ $label"
}

reject "pins.icon carrying HTML is rejected" "
  INSERT INTO public.pins (room, name, lat, lng, icon)
  VALUES ('main', 'x', 13.7, 100.5, '<img src=x onerror=alert(1)>');"

reject "routes.color breaking out of the attribute is rejected" "
  INSERT INTO public.routes (room, name, coordinates, color)
  VALUES ('main', 'x', '[[13.7,100.5],[13.8,100.6]]'::jsonb, '#fff\" onmouseover=\"alert(1)');"

reject "out-of-region coordinates are rejected" "
  INSERT INTO public.pins (room, name, lat, lng) VALUES ('main', 'x', 51.5, -0.12);"

reject "a route with a single point is rejected" "
  INSERT INTO public.routes (room, name, coordinates)
  VALUES ('main', 'x', '[[13.7,100.5]]'::jsonb);"

# And must still accept what the app really sends
echo "→ checking a legitimate row still inserts"
psql -c "
  INSERT INTO public.pins (room, name, lat, lng, icon)
  VALUES ('ทริปเชียงใหม่', 'จุดพักรถ', 18.79, 98.98, '☕');"
echo "   ✅ normal pin accepted"

echo


# ===== RLS: prove the policies actually separate one device from another =====
# The whole point of 004 is that holding the anon key is no longer enough to
# touch someone else's row. Assert that against real policies, as the real
# roles — postgres bypasses RLS, so every check below runs SET ROLE first.
echo "→ checking row ownership policies"

A='11111111-1111-4111-8111-111111111111'
B='22222222-2222-4222-8222-222222222222'

# -q matters: without it psql prints BEGIN/SET/DELETE/COMMIT status lines and
# "tail -1" picks up COMMIT instead of the value the caller wants.
as_user() { # as_user <uuid> <sql>
  command psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAq <<SQL
BEGIN;
SELECT set_config('request.jwt.claim.sub', '$1', true);
SET LOCAL ROLE authenticated;
$2
COMMIT;
SQL
}

as_anon() { # as_anon <sql> — no JWT at all, i.e. someone with just the key
  command psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAq <<SQL
BEGIN;
SET LOCAL ROLE anon;
$1
COMMIT;
SQL
}

# A and B each share a location
as_user "$A" "INSERT INTO public.locations (user_id, room, lat, lng, display_name)
               VALUES ('dev_a', 'main', 13.75, 100.50, 'A');" >/dev/null
as_user "$B" "INSERT INTO public.locations (user_id, room, lat, lng, display_name)
               VALUES ('dev_b', 'main', 13.76, 100.51, 'B');" >/dev/null
echo "   ✅ signed-in devices can share their own location"

owner_a=$(command psql "$DATABASE_URL" -tAc "SELECT owner FROM public.locations WHERE user_id='dev_a';")
[ "$owner_a" = "$A" ] || { echo "   ❌ owner was not stamped from the JWT (got '$owner_a')"; exit 1; }
echo "   ✅ owner stamped from the JWT, not from the client"

# B tries to delete A's location
deleted=$(as_user "$B" "DELETE FROM public.locations WHERE user_id='dev_a';
                        SELECT count(*) FROM public.locations WHERE user_id='dev_a';" | tail -1)
[ "$deleted" = "1" ] || { echo "   ❌ another device deleted A's location"; exit 1; }
echo "   ✅ one device cannot delete another's location"

# B tries to move A's location somewhere else
moved=$(as_user "$B" "UPDATE public.locations SET lat=0.1, lng=90.1 WHERE user_id='dev_a';
                      SELECT lat FROM public.locations WHERE user_id='dev_a';" | tail -1)
case "$moved" in 13.75*) echo "   ✅ one device cannot move another's location";;
  *) echo "   ❌ another device moved A's location (lat=$moved)"; exit 1;; esac

# Someone with only the anon key, no session
if as_anon "INSERT INTO public.locations (user_id, room, lat, lng)
            VALUES ('dev_key_only', 'main', 13.7, 100.5);" >/dev/null 2>&1; then
  echo "   ❌ a keyholder with no session still inserted a location"; exit 1
fi
echo "   ✅ the anon key alone can no longer write"

wiped=$(as_anon "DELETE FROM public.locations;
                 SELECT count(*) FROM public.locations;" 2>/dev/null | tail -1)
[ "$wiped" = "2" ] || { echo "   ❌ the anon key alone wiped the table (left '$wiped')"; exit 1; }
echo "   ✅ the anon key alone can no longer delete"

# Reads must stay open or Realtime goes silent — that is a deliberate trade-off
visible=$(as_anon "SELECT count(*) FROM public.locations;" | tail -1)
[ "$visible" = "2" ] || { echo "   ❌ anon lost SELECT — realtime would go silent"; exit 1; }
echo "   ✅ anon can still read (required by realtime)"

# A can still manage its own row
own=$(as_user "$A" "DELETE FROM public.locations WHERE user_id='dev_a';
                    SELECT count(*) FROM public.locations WHERE user_id='dev_a';" | tail -1)
[ "$own" = "0" ] || { echo "   ❌ a device could not delete its own location"; exit 1; }
echo "   ✅ a device can still delete its own location"

echo
echo "✅ row ownership verified"
