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

for pass in 1 2; do
  echo "→ applying migrations (pass $pass)"
  for f in migrations/*.sql; do
    echo "   $f"
    psql -f "$f"
  done
done

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

assert "old user_id@room split into user_id + room" "
  SELECT NOT EXISTS (SELECT 1 FROM public.locations WHERE user_id LIKE '%@%');"

assert "backfilled room values landed" "
  SELECT count(*) = 2 FROM public.locations WHERE room = 'ทริปเชียงใหม่';"

assert "same person kept both rooms" "
  SELECT count(*) = 2 FROM public.locations WHERE user_id = 'user_aaa';"

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
echo "✅ migrations verified end to end"
