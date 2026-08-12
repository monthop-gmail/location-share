-- Migration: ตั้งเวลาลบตำแหน่งที่หมดอายุแล้วจริงๆ
--
-- db_schema.sql มี delete_expired_locations() มาตั้งแต่แรก และ trigger ก็ตั้ง
-- expires_at = NOW() + 15 นาที ให้ทุกแถว — แต่ไม่มีอะไรเรียกฟังก์ชันนั้นเลย
-- ตาราง locations จึงโตขึ้นเรื่อยๆ และทุกเครื่องต้องดาวน์โหลดแถวที่ตายแล้วทุก 10 วินาที
--
-- รันซ้ำได้ ไม่มีผลข้างเคียง

BEGIN;

-- เผื่อกรณียังไม่เคยรัน db_schema.sql เวอร์ชันล่าสุด
CREATE OR REPLACE FUNCTION delete_expired_locations()
RETURNS void AS $$
BEGIN
  DELETE FROM public.locations WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- routes/pins ไม่มี expires_at เพราะตั้งใจให้อยู่ถาวรต่อห้อง
-- ถ้าอยากให้หายเองด้วย ให้ปลดคอมเมนต์บล็อกท้ายไฟล์

COMMIT;

-- ===== ตั้ง schedule =====
-- pg_cron มีให้ใช้ในทุก Supabase project แต่ต้องเปิด extension ก่อน
-- (Dashboard → Database → Extensions → เปิด "pg_cron" หรือรันบรรทัดล่างนี้)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ลบ job เดิมก่อนถ้ามี เพื่อให้รันไฟล์ซ้ำได้
SELECT cron.unschedule('delete-expired-locations')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'delete-expired-locations'
);

-- ทุก 5 นาที
SELECT cron.schedule(
  'delete-expired-locations',
  '*/5 * * * *',
  $$ SELECT delete_expired_locations(); $$
);

-- ตรวจว่าตั้งสำเร็จไหม:
--   SELECT jobname, schedule, active FROM cron.job;
-- ดูประวัติการรัน:
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;


-- ===== ทางเลือกถ้าเปิด pg_cron ไม่ได้ =====
-- ใช้ Supabase Edge Function + Cron trigger เรียก RPC นี้แทน:
--   GRANT EXECUTE ON FUNCTION delete_expired_locations() TO anon;
-- แล้วยิง POST https://<project>.supabase.co/rest/v1/rpc/delete_expired_locations
-- หมายเหตุ: การ GRANT ให้ anon แปลว่าใครก็สั่งลบแถวที่หมดอายุได้
-- ซึ่งไม่อันตราย เพราะลบเฉพาะแถวที่ expires_at < NOW() อยู่แล้ว


-- ===== ทางเลือก: ให้ routes/pins หมดอายุด้วย =====
-- ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
--   DEFAULT (NOW() + INTERVAL '30 days');
-- ALTER TABLE public.pins ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
--   DEFAULT (NOW() + INTERVAL '30 days');
-- SELECT cron.schedule('delete-expired-map-data', '0 3 * * *', $$
--   DELETE FROM public.routes WHERE expires_at < NOW();
--   DELETE FROM public.pins   WHERE expires_at < NOW();
-- $$);
