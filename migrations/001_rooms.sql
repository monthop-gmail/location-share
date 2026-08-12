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

-- 2. ปลด unique เดิมบน user_id "ก่อน" backfill
--    ลำดับนี้สำคัญ: คนที่อยู่ทั้งห้อง main และห้องอื่นจะมีทั้ง 'user_aaa' และ
--    'user_aaa@ทริป' พอตัด @ ออกทั้งคู่จะชนกันทันทีถ้า constraint ยังอยู่
ALTER TABLE public.locations DROP CONSTRAINT IF EXISTS locations_user_id_key;

-- 3. Backfill: แยก "user_xxxx@ทริปเชียงใหม่" เป็น user_id + room
--    (แถวที่ไม่มี @ คือห้อง main อยู่แล้ว จึงไม่ต้องแตะ)
UPDATE public.locations
SET room    = split_part(user_id, '@', 2),
    user_id = split_part(user_id, '@', 1)
WHERE position('@' in user_id) > 0;

-- 4. กันไว้: ถ้ามีข้อมูลเก่าที่ทำให้ (user_id, room) ซ้ำ ให้เก็บแถวล่าสุดไว้
--    ตำแหน่งเป็นข้อมูลอายุสั้นอยู่แล้ว ทิ้งแถวเก่ากว่าได้ไม่เสียหาย
DELETE FROM public.locations a
USING public.locations b
WHERE a.user_id = b.user_id
  AND a.room    = b.room
  AND (a.updated_at, a.id) < (b.updated_at, b.id);

-- 5. ย้าย uniqueness ไปเป็น (user_id, room)
--    คนคนเดียวอยู่ได้หลายห้องพร้อมกัน แต่ห้องละแถวเดียว
CREATE UNIQUE INDEX IF NOT EXISTS locations_user_id_room_key
    ON public.locations (user_id, room);

-- 6. Index รองรับ query แบบต่อห้องที่ client ยิงมาใหม่
CREATE INDEX IF NOT EXISTS locations_room_updated_idx
    ON public.locations (room, updated_at DESC);
CREATE INDEX IF NOT EXISTS routes_room_idx ON public.routes (room);
CREATE INDEX IF NOT EXISTS pins_room_idx   ON public.pins (room);

COMMIT;
