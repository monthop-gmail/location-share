-- Migration: เก็บตำแหน่งสุดท้ายไว้หลังกดหยุดแชร์ (issue #11)
--
-- เดิมกดหยุดแชร์ = DELETE ข้อมูลหายถาวรทันที
-- เปลี่ยนเป็น soft delete: ตั้ง is_sharing = false แล้วเก็บแถวไว้อีก 24 ชั่วโมง
--
-- ⚠️ ไม่ได้ทำให้ข้อมูลนี้เป็นความลับ — RLS ยังเปิด SELECT ให้ anon อยู่ (ต้องเปิดไว้
--    ไม่งั้น Realtime เงียบ ดู #16) แปลว่าใครถือ anon key ก็อ่านตำแหน่งของคน
--    ที่กดหยุดแชร์ไปแล้วได้ "admin mode" ฝั่ง client เป็นแค่สวิตช์ซ่อน/แสดง
--    ไม่ใช่การควบคุมสิทธิ์ ดู docs/SECURITY.md
--
-- รันซ้ำได้ ไม่มีผลข้างเคียง

BEGIN;

-- ===== 1. คอลัมน์บอกว่ายังแชร์อยู่ไหม =====
ALTER TABLE public.locations
    ADD COLUMN IF NOT EXISTS is_sharing BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS locations_room_sharing_idx
    ON public.locations (room, is_sharing);

-- ===== 2. trigger ต้องแยกสองกรณี =====
-- เดิม trigger เป็น BEFORE INSERT OR UPDATE และ reset expires_at ทุกครั้ง
-- ถ้าปล่อยไว้ แถวที่เพิ่ง soft delete จะได้ expires_at = NOW() + 15 นาที
-- แล้ว cron ก็เก็บกวาดทิ้งตามปกติ = ฟีเจอร์นี้ไม่ทำงานเลยโดยไม่มีใครรู้
--
-- และ updated_at ต้องไม่ขยับตอน soft delete ไม่งั้นคนที่เพิ่งกดหยุด
-- จะดูเหมือน "อัปเดตเมื่อสักครู่" ทั้งที่ตำแหน่งนั้นเก่าแล้ว
CREATE OR REPLACE FUNCTION set_updated_and_expires()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_sharing THEN
    NEW.updated_at = NOW();
    NEW.expires_at = NOW() + INTERVAL '15 minutes';
  ELSE
    -- คงเวลาของตำแหน่งจริงครั้งสุดท้ายไว้
    IF TG_OP = 'UPDATE' THEN
      NEW.updated_at = OLD.updated_at;
    ELSE
      NEW.updated_at = NOW();
    END IF;
    NEW.expires_at = NOW() + INTERVAL '24 hours';   -- retention
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_expires_at ON public.locations;
DROP TRIGGER IF EXISTS trigger_set_updated_and_expires ON public.locations;
CREATE TRIGGER trigger_set_updated_and_expires
BEFORE INSERT OR UPDATE ON public.locations
FOR EACH ROW
EXECUTE FUNCTION set_updated_and_expires();

COMMIT;

-- delete_expired_locations() ไม่ต้องแก้ — ยังลบตาม expires_at เหมือนเดิม
-- retention ของทั้งสองกรณีจึงอยู่ที่เดียวคือ trigger ด้านบน
-- อยากเก็บนานขึ้น/สั้นลง แก้ INTERVAL '24 hours' ที่เดียวจบ
