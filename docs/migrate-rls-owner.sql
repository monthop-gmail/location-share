-- Migration: ผูกแถวกับเจ้าของจริง แล้วล็อค UPDATE/DELETE (issue #3)
--
-- ⚠️ ต้องทำก่อนรันไฟล์นี้:
--    Supabase Dashboard → Authentication → Providers → เปิด "Anonymous Sign-ins"
--
-- ⚠️ ต้อง deploy index.html ที่เรียก supabaseClient.auth.signInAnonymously()
--    "พร้อมกัน" กับการรันไฟล์นี้ ไม่งั้น client เดิมจะเขียนข้อมูลไม่ได้เลย
--    (ดู docs/SECURITY.md ประกอบก่อนตัดสินใจ)
--
-- รันซ้ำได้ ไม่มีผลข้างเคียง

BEGIN;

-- ===== 1. คอลัมน์เจ้าของ =====
-- auth.uid() มาจาก JWT ของ anonymous user ปลอมไม่ได้จากฝั่ง client
ALTER TABLE public.locations ADD COLUMN IF NOT EXISTS owner UUID DEFAULT auth.uid();
ALTER TABLE public.routes    ADD COLUMN IF NOT EXISTS owner UUID DEFAULT auth.uid();
ALTER TABLE public.pins      ADD COLUMN IF NOT EXISTS owner UUID DEFAULT auth.uid();

-- แถวเก่าจะมี owner = NULL และจะแก้/ลบผ่าน anon ไม่ได้อีกต่อไป
-- locations ไม่เป็นไรเพราะหมดอายุใน 15 นาทีอยู่แล้ว
-- ส่วน routes/pins เก่า ถ้าต้องการล้างทิ้ง ให้รันเองตามต้องการ:
--   DELETE FROM public.routes WHERE owner IS NULL;
--   DELETE FROM public.pins   WHERE owner IS NULL;

-- ===== 2. locations: ตำแหน่งของใครก็ของคนนั้น =====
-- SELECT ยังเปิดกว้าง เพราะ Supabase Realtime ประเมิน RLS ด้วย role ของผู้ subscribe
-- ถ้าปิด SELECT ระบบ realtime จะเงียบทันที (อ่านเหตุผลเต็มใน docs/SECURITY.md)
DROP POLICY IF EXISTS "Enable select for everyone" ON public.locations;
CREATE POLICY "Read locations" ON public.locations
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable insert for everyone" ON public.locations;
CREATE POLICY "Insert own location" ON public.locations
    FOR INSERT WITH CHECK (owner = auth.uid());

DROP POLICY IF EXISTS "Enable update for everyone" ON public.locations;
CREATE POLICY "Update own location" ON public.locations
    FOR UPDATE USING (owner = auth.uid()) WITH CHECK (owner = auth.uid());

DROP POLICY IF EXISTS "Enable delete for everyone" ON public.locations;
CREATE POLICY "Delete own location" ON public.locations
    FOR DELETE USING (owner = auth.uid());

-- ===== 3. routes / pins: ของใช้ร่วมกันในห้อง =====
-- ตั้งใจให้คนในห้องช่วยกันจัดการเส้นทาง/หมุดได้ (วางแผนทริปร่วมกัน)
-- จึงล็อคแค่ INSERT ให้ผูกเจ้าของ ส่วน DELETE ยังเปิดให้คนในห้อง
-- ถ้าต้องการให้ลบได้เฉพาะคนที่สร้าง ให้ใช้บล็อกที่คอมเมนต์ไว้ท้ายไฟล์แทน
DROP POLICY IF EXISTS "Anyone can insert routes" ON public.routes;
CREATE POLICY "Insert routes as self" ON public.routes
    FOR INSERT WITH CHECK (owner = auth.uid());

DROP POLICY IF EXISTS "Anyone can insert pins" ON public.pins;
CREATE POLICY "Insert pins as self" ON public.pins
    FOR INSERT WITH CHECK (owner = auth.uid());

COMMIT;


-- ===== ทางเลือก: ให้ลบได้เฉพาะคนที่สร้างเอง =====
-- ระวัง: ถ้าคนสร้างล้าง site data หรือเปลี่ยนเครื่อง จะไม่มีใครลบหมุดนั้นได้อีก
--
-- DROP POLICY IF EXISTS "Anyone can delete routes" ON public.routes;
-- CREATE POLICY "Delete own routes" ON public.routes
--     FOR DELETE USING (owner = auth.uid());
--
-- DROP POLICY IF EXISTS "Anyone can delete pins" ON public.pins;
-- CREATE POLICY "Delete own pins" ON public.pins
--     FOR DELETE USING (owner = auth.uid());


-- ===== หมายเหตุเรื่องบัญชี anonymous =====
-- ทุกเครื่องที่เปิดแอปจะสร้างแถวใน auth.users หนึ่งแถว และไม่หายไปเอง
-- ควรตั้ง cron ล้างบัญชีที่ไม่ได้ใช้งานนานทิ้ง:
--
-- SELECT cron.schedule('purge-anon-users', '0 4 * * *', $$
--   DELETE FROM auth.users
--   WHERE is_anonymous IS TRUE
--     AND last_sign_in_at < NOW() - INTERVAL '30 days';
-- $$);
