-- Schema เต็มสำหรับตั้งโปรเจกต์ใหม่จากศูนย์
--
-- ถ้าเป็นโปรเจกต์ที่มีข้อมูลอยู่แล้ว อย่ารันไฟล์นี้ — ให้ไล่ตาม MIGRATE.md แทน
-- ไฟล์นี้คือสถานะปลายทางหลังรัน migration ครบทุกตัว (ยกเว้น migrate-rls-owner.sql
-- ซึ่งเป็นทางเลือก อ่าน SECURITY.md ประกอบ)

-- ============================================================
-- 1. locations — ตำแหน่งเรียลไทม์ อายุสั้น
-- ============================================================
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    room TEXT NOT NULL DEFAULT 'main',
    lat FLOAT8 NOT NULL,
    lng FLOAT8 NOT NULL,
    display_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ -- ตั้งโดย trigger ด้านล่าง
);

-- คนคนเดียวอยู่ได้หลายห้องพร้อมกัน แต่ห้องละแถวเดียว — เป็น target ของ upsert
CREATE UNIQUE INDEX IF NOT EXISTS locations_user_id_room_key
    ON public.locations (user_id, room);

CREATE INDEX IF NOT EXISTS locations_room_updated_idx
    ON public.locations (room, updated_at DESC);

-- updated_at/expires_at ต้องมาจากนาฬิกา server ไม่ใช่นาฬิกาเครื่อง client
CREATE OR REPLACE FUNCTION set_updated_and_expires()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  NEW.expires_at = NOW() + INTERVAL '15 minutes';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_expires_at ON public.locations;
DROP TRIGGER IF EXISTS trigger_set_updated_and_expires ON public.locations;
CREATE TRIGGER trigger_set_updated_and_expires
BEFORE INSERT OR UPDATE ON public.locations
FOR EACH ROW
EXECUTE FUNCTION set_updated_and_expires();

-- ============================================================
-- 2. routes — เส้นทางที่วาดบนแผนที่
-- ============================================================
CREATE TABLE IF NOT EXISTS public.routes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    room TEXT NOT NULL DEFAULT 'main',
    name TEXT,
    coordinates JSONB NOT NULL,   -- [[lat,lng], [lat,lng], ...]
    color TEXT DEFAULT '#3388ff',
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS routes_room_idx ON public.routes (room);

-- ============================================================
-- 3. pins — หมุดจุดหมาย
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pins (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    room TEXT NOT NULL DEFAULT 'main',
    name TEXT NOT NULL,
    lat FLOAT8 NOT NULL,
    lng FLOAT8 NOT NULL,
    icon TEXT DEFAULT '📍',
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS pins_room_idx ON public.pins (room);

-- ============================================================
-- 4. Validation — anon key อยู่ในหน้าเว็บ ห้ามเชื่อ client
-- ============================================================
ALTER TABLE public.locations ADD CONSTRAINT locations_bounds_chk
    CHECK (lat >= 0 AND lat <= 25 AND lng >= 90 AND lng <= 115);
ALTER TABLE public.locations ADD CONSTRAINT locations_room_chk
    CHECK (char_length(room) BETWEEN 1 AND 64 AND position('@' in room) = 0);
ALTER TABLE public.locations ADD CONSTRAINT locations_display_name_chk
    CHECK (display_name IS NULL OR char_length(display_name) <= 64);

ALTER TABLE public.routes ADD CONSTRAINT routes_color_chk
    CHECK (color ~ '^#[0-9A-Fa-f]{6}$');
ALTER TABLE public.routes ADD CONSTRAINT routes_name_chk
    CHECK (name IS NULL OR char_length(name) <= 80);
ALTER TABLE public.routes ADD CONSTRAINT routes_room_chk
    CHECK (char_length(room) BETWEEN 1 AND 64);
ALTER TABLE public.routes ADD CONSTRAINT routes_coordinates_chk
    CHECK (jsonb_typeof(coordinates) = 'array'
           AND jsonb_array_length(coordinates) BETWEEN 2 AND 1000);

-- icon สั้นและห้ามมีอักขระ HTML — กัน stored XSS ตั้งแต่ต้นทาง
ALTER TABLE public.pins ADD CONSTRAINT pins_icon_chk
    CHECK (icon IS NULL OR (char_length(icon) <= 8 AND icon !~ '[<>&"'']'));
ALTER TABLE public.pins ADD CONSTRAINT pins_name_chk
    CHECK (char_length(name) BETWEEN 1 AND 80);
ALTER TABLE public.pins ADD CONSTRAINT pins_bounds_chk
    CHECK (lat >= 0 AND lat <= 25 AND lng >= 90 AND lng <= 115);
ALTER TABLE public.pins ADD CONSTRAINT pins_room_chk
    CHECK (char_length(room) BETWEEN 1 AND 64);

-- ============================================================
-- 5. Row Level Security
--
-- ⚠️ policy ชุดนี้เปิดกว้าง: ใครมี anon key ก็อ่านและลบข้อมูลได้ทุกห้อง
--    เป็นสถานะปัจจุบันของ issue #3 — อ่าน SECURITY.md ก่อนใช้งานจริง
--    และดู migrate-rls-owner.sql สำหรับเวอร์ชันที่ล็อคด้วย auth.uid()
--
--    SELECT ต้องเปิดไว้ เพราะ Supabase Realtime ประเมิน RLS ด้วย role
--    ของผู้ subscribe — ถ้าปิด SELECT ระบบ realtime จะเงียบทั้งหมด
-- ============================================================
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pins      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable select for everyone" ON public.locations;
CREATE POLICY "Enable select for everyone" ON public.locations FOR SELECT USING (true);
DROP POLICY IF EXISTS "Enable insert for everyone" ON public.locations;
CREATE POLICY "Enable insert for everyone" ON public.locations FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Enable update for everyone" ON public.locations;
CREATE POLICY "Enable update for everyone" ON public.locations FOR UPDATE USING (true);
DROP POLICY IF EXISTS "Enable delete for everyone" ON public.locations;
CREATE POLICY "Enable delete for everyone" ON public.locations FOR DELETE USING (true);

DROP POLICY IF EXISTS "Anyone can read routes" ON public.routes;
CREATE POLICY "Anyone can read routes" ON public.routes FOR SELECT USING (true);
DROP POLICY IF EXISTS "Anyone can insert routes" ON public.routes;
CREATE POLICY "Anyone can insert routes" ON public.routes FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Anyone can delete routes" ON public.routes;
CREATE POLICY "Anyone can delete routes" ON public.routes FOR DELETE USING (true);

DROP POLICY IF EXISTS "Anyone can read pins" ON public.pins;
CREATE POLICY "Anyone can read pins" ON public.pins FOR SELECT USING (true);
DROP POLICY IF EXISTS "Anyone can insert pins" ON public.pins;
CREATE POLICY "Anyone can insert pins" ON public.pins FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Anyone can delete pins" ON public.pins;
CREATE POLICY "Anyone can delete pins" ON public.pins FOR DELETE USING (true);

-- ============================================================
-- 6. Cleanup — ต้องมี schedule ไม่งั้นตารางโตไม่หยุด
-- ============================================================
CREATE OR REPLACE FUNCTION delete_expired_locations()
RETURNS void AS $$
BEGIN
  DELETE FROM public.locations WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('delete-expired-locations')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'delete-expired-locations');

SELECT cron.schedule(
  'delete-expired-locations',
  '*/5 * * * *',
  $$ SELECT delete_expired_locations(); $$
);
