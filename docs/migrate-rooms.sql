-- Migration: room isolation at the database level
--
-- ก่อนหน้านี้ห้องถูกยัดไว้ในคอลัมน์ user_id เป็นรูปแบบ "user_xxxx@ชื่อห้อง"
-- ทำให้ client ต้อง SELECT ทุกแถวของทุกห้องมาแล้วค่อยกรองเอง
-- migration นี้ยกห้องขึ้นมาเป็นคอลัมน์จริงเพื่อให้กรองที่ DB ได้
--
-- ⚠️ ต้องรันไฟล์นี้ให้เสร็จ "ก่อน" deploy index.html เวอร์ชันใหม่
-- รันซ้ำได้ ไม่มีผลข้างเคียง

BEGIN;

-- 1. เพิ่มคอลัมน์ room
ALTER TABLE public.locations
    ADD COLUMN IF NOT EXISTS room TEXT NOT NULL DEFAULT 'main';

-- 2. Backfill: แยก "user_xxxx@ทริปเชียงใหม่" เป็น user_id + room
--    (แถวที่ไม่มี @ คือห้อง main อยู่แล้ว จึงไม่ต้องแตะ)
UPDATE public.locations
SET room    = split_part(user_id, '@', 2),
    user_id = split_part(user_id, '@', 1)
WHERE position('@' in user_id) > 0;

-- 3. ย้าย uniqueness จาก user_id ไปเป็น (user_id, room)
--    คนคนเดียวอยู่ได้หลายห้องพร้อมกัน แต่ห้องละแถวเดียว
ALTER TABLE public.locations DROP CONSTRAINT IF EXISTS locations_user_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS locations_user_id_room_key
    ON public.locations (user_id, room);

-- 4. Index รองรับ query แบบต่อห้องที่ client ยิงมาใหม่
CREATE INDEX IF NOT EXISTS locations_room_updated_idx
    ON public.locations (room, updated_at DESC);
CREATE INDEX IF NOT EXISTS routes_room_idx ON public.routes (room);
CREATE INDEX IF NOT EXISTS pins_room_idx   ON public.pins (room);

COMMIT;
