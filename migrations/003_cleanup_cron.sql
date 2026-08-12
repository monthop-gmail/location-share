-- Migration: ตั้งเวลาลบตำแหน่งที่หมดอายุแล้วจริงๆ
--
-- db_schema.sql มี delete_expired_locations() มาตั้งแต่แรก และ trigger ก็ตั้ง
-- expires_at = NOW() + 15 นาที ให้ทุกแถว — แต่ไม่มีอะไรเรียกฟังก์ชันนั้นเลย
-- ตาราง locations จึงโตขึ้นเรื่อยๆ
--
-- รันซ้ำได้ ไม่มีผลข้างเคียง

CREATE OR REPLACE FUNCTION delete_expired_locations()
RETURNS void AS $$
BEGIN
  DELETE FROM public.locations WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- การตั้ง schedule ห่อไว้ทั้งหมด เพราะ migration ชุดนี้รันอัตโนมัติจาก CI
-- ถ้าโปรเจกต์ไหนเปิด pg_cron ไม่ได้ ต้องเตือนแล้วผ่านไป ไม่ใช่ทำให้ deploy ล้ม
DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pg_cron ใช้ไม่ได้ (%) — ข้ามการตั้ง schedule, ต้องตั้ง cleanup เอง', SQLERRM;
    RETURN;
  END;

  IF to_regprocedure('cron.schedule(text,text,text)') IS NULL THEN
    RAISE WARNING 'ไม่พบ cron.schedule — ข้ามการตั้ง schedule, ต้องตั้ง cleanup เอง';
    RETURN;
  END IF;

  -- ลบ job เดิมก่อน เพื่อให้รันไฟล์นี้ซ้ำได้
  PERFORM cron.unschedule('delete-expired-locations')
  FROM cron.job WHERE jobname = 'delete-expired-locations';

  PERFORM cron.schedule(
    'delete-expired-locations',
    '*/5 * * * *',
    'SELECT delete_expired_locations();'
  );

  RAISE NOTICE 'ตั้ง cron delete-expired-locations ทุก 5 นาทีเรียบร้อย';
END $$;

-- ตรวจว่าตั้งสำเร็จไหม:
--   SELECT jobname, schedule, active FROM cron.job;
-- ดูประวัติการรัน:
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;


-- ===== ทางเลือกถ้าเปิด pg_cron ไม่ได้ =====
-- ใช้ Supabase Edge Function + Cron trigger เรียก RPC นี้แทน:
--   GRANT EXECUTE ON FUNCTION delete_expired_locations() TO anon;
-- แล้วยิง POST https://<project>.supabase.co/rest/v1/rpc/delete_expired_locations
-- การ GRANT ให้ anon ไม่อันตราย เพราะลบเฉพาะแถวที่ expires_at < NOW() อยู่แล้ว


-- ===== ทางเลือก: ให้ routes/pins หมดอายุด้วย =====
-- ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
--   DEFAULT (NOW() + INTERVAL '30 days');
-- ALTER TABLE public.pins ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
--   DEFAULT (NOW() + INTERVAL '30 days');
