-- Migration: ผูกแถวกับเจ้าของจริง แล้วปิดช่อง "ใครมี anon key ก็ลบข้อมูลคนอื่นได้"
-- issue #3 ขั้นที่ 2
--
-- ⚠️ ต้องครบสองอย่างนี้ก่อน migration ตัวนี้จะทำงานถูกต้อง:
--    1. เปิด Anonymous Sign-ins แล้ว (Authentication → Providers)
--    2. deploy client ที่เรียก signInAnonymously() ไปแล้ว (ขั้นที่ 1, PR #14)
--
--    ถ้ารันก่อนสองข้อบน client จะเขียนข้อมูลไม่ได้เลย เพราะไม่มี auth.uid()
--    ให้ policy จับคู่ด้วย — ดู docs/SECURITY.md
--
-- รันซ้ำได้ ไม่มีผลข้างเคียง

BEGIN;

-- ===== 1. คอลัมน์เจ้าของ =====
-- auth.uid() มาจาก JWT ที่ Supabase ออกให้ ปลอมจากฝั่ง client ไม่ได้
ALTER TABLE public.locations ADD COLUMN IF NOT EXISTS owner UUID DEFAULT auth.uid();
ALTER TABLE public.routes    ADD COLUMN IF NOT EXISTS owner UUID DEFAULT auth.uid();
ALTER TABLE public.pins      ADD COLUMN IF NOT EXISTS owner UUID DEFAULT auth.uid();

-- ===== 2. ล้างตำแหน่งที่ไม่มีเจ้าของ =====
-- แถวที่เขียนไว้ก่อน migration นี้จะมี owner = NULL ซึ่งไม่มีใครแก้ได้อีก
-- เจ้าของตัวจริงจะ upsert ทับไม่ได้ด้วย (USING เช็คแถวเดิม) แล้วค้างจนกว่าจะหมดอายุ
-- ตำแหน่งอายุ 15 นาทีอยู่แล้ว ลบทิ้งเลยตรงกว่าปล่อยให้ค้าง
DELETE FROM public.locations WHERE owner IS NULL;

-- routes/pins ไม่ลบ เพราะตั้งใจให้อยู่ถาวร ของเก่าจะมี owner = NULL
-- ซึ่งไม่เป็นไรเพราะ policy DELETE ของสองตารางนี้ยังเปิดให้คนในห้อง (ดูข้อ 4)

-- ===== 3. locations: ตำแหน่งของใครก็ของคนนั้น =====
-- SELECT ยังเปิดกว้าง เพราะ Supabase Realtime ประเมิน RLS ด้วย role ของผู้ subscribe
-- ถ้าปิด SELECT ระบบ realtime จะเงียบทันที (เหตุผลเต็มใน docs/SECURITY.md)
DROP POLICY IF EXISTS "Enable select for everyone" ON public.locations;
DROP POLICY IF EXISTS "Read locations" ON public.locations;
CREATE POLICY "Read locations" ON public.locations
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable insert for everyone" ON public.locations;
DROP POLICY IF EXISTS "Insert own location" ON public.locations;
CREATE POLICY "Insert own location" ON public.locations
    FOR INSERT WITH CHECK (owner IS NOT NULL AND owner = auth.uid());

DROP POLICY IF EXISTS "Enable update for everyone" ON public.locations;
DROP POLICY IF EXISTS "Update own location" ON public.locations;
CREATE POLICY "Update own location" ON public.locations
    FOR UPDATE USING (owner = auth.uid()) WITH CHECK (owner = auth.uid());

DROP POLICY IF EXISTS "Enable delete for everyone" ON public.locations;
DROP POLICY IF EXISTS "Delete own location" ON public.locations;
CREATE POLICY "Delete own location" ON public.locations
    FOR DELETE USING (owner = auth.uid());

-- ===== 4. routes / pins: ของใช้ร่วมกันในห้อง =====
-- ตั้งใจให้คนในห้องช่วยกันจัดการเส้นทาง/หมุดได้ (วางแผนทริปร่วมกัน)
-- และถ้าคนสร้างล้าง site data ไปแล้ว ต้องยังมีคนลบของที่ค้างได้
-- จึงล็อคแค่ INSERT ให้ผูกเจ้าของ ส่วน DELETE ยังเปิดให้คนในห้องตามเดิม
DROP POLICY IF EXISTS "Anyone can insert routes" ON public.routes;
DROP POLICY IF EXISTS "Insert routes as self" ON public.routes;
CREATE POLICY "Insert routes as self" ON public.routes
    FOR INSERT WITH CHECK (owner IS NOT NULL AND owner = auth.uid());

DROP POLICY IF EXISTS "Anyone can insert pins" ON public.pins;
DROP POLICY IF EXISTS "Insert pins as self" ON public.pins;
CREATE POLICY "Insert pins as self" ON public.pins
    FOR INSERT WITH CHECK (owner IS NOT NULL AND owner = auth.uid());

COMMIT;


-- ===== ทางเลือก: ให้ลบ routes/pins ได้เฉพาะคนที่สร้างเอง =====
-- ระวัง: ถ้าคนสร้างล้าง site data หรือเปลี่ยนเครื่อง จะไม่มีใครลบของนั้นได้อีก
-- และหมุดที่สร้างไว้ก่อน migration นี้ (owner = NULL) จะลบไม่ได้เลย
--
-- DROP POLICY IF EXISTS "Anyone can delete routes" ON public.routes;
-- CREATE POLICY "Delete own routes" ON public.routes
--     FOR DELETE USING (owner = auth.uid());
--
-- DROP POLICY IF EXISTS "Anyone can delete pins" ON public.pins;
-- CREATE POLICY "Delete own pins" ON public.pins
--     FOR DELETE USING (owner = auth.uid());


-- ===== ทางเลือก: ล้างบัญชี anonymous ที่ไม่ได้ใช้แล้ว =====
-- ทุกเครื่องที่เปิดแอปสร้างแถวใน auth.users หนึ่งแถวและไม่หายไปเอง
-- ไม่ได้เปิดไว้อัตโนมัติเพราะเป็นการลบจากตารางระบบของ Supabase
-- ควรดูจำนวนก่อนว่าโตจริงไหม: SELECT count(*) FROM auth.users WHERE is_anonymous;
--
-- ระวัง: last_sign_in_at ไม่ขยับตอน refresh token จึงเช็ค auth.sessions ประกอบ
-- ไม่งั้นจะลบคนที่ยังใช้งานอยู่แต่ไม่ได้ sign in ใหม่มานาน
--
-- SELECT cron.schedule('purge-anon-users', '0 4 * * *', $$
--   DELETE FROM auth.users u
--   WHERE u.is_anonymous IS TRUE
--     AND u.created_at < NOW() - INTERVAL '90 days'
--     AND NOT EXISTS (
--       SELECT 1 FROM auth.sessions s
--       WHERE s.user_id = u.id AND s.updated_at > NOW() - INTERVAL '30 days'
--     );
-- $$);
