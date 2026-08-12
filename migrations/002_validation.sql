-- Migration: server-side validation constraints
--
-- anon key อยู่ใน source ของหน้าเว็บ ใครก็หยิบไปยิง INSERT ตรงเข้า table ได้
-- constraint ชุดนี้บังคับกติกาเดียวกับที่ client ใช้ ลงไปที่ฝั่ง DB
-- เพื่อไม่ให้มีแถวที่บรรจุ HTML, พิกัดนอกโลก หรือข้อความยาวผิดปกติ หลุดเข้ามาได้
--
-- ใช้ NOT VALID ทุกตัว = บังคับเฉพาะแถวใหม่ ไม่ไปล้มเพราะข้อมูลเก่าที่มีอยู่แล้ว
-- รันซ้ำได้ ไม่มีผลข้างเคียง

BEGIN;

-- ===== locations =====
ALTER TABLE public.locations DROP CONSTRAINT IF EXISTS locations_bounds_chk;
ALTER TABLE public.locations ADD CONSTRAINT locations_bounds_chk
    CHECK (lat >= 0 AND lat <= 25 AND lng >= 90 AND lng <= 115) NOT VALID;

ALTER TABLE public.locations DROP CONSTRAINT IF EXISTS locations_room_chk;
ALTER TABLE public.locations ADD CONSTRAINT locations_room_chk
    CHECK (char_length(room) BETWEEN 1 AND 64 AND position('@' in room) = 0) NOT VALID;

ALTER TABLE public.locations DROP CONSTRAINT IF EXISTS locations_display_name_chk;
ALTER TABLE public.locations ADD CONSTRAINT locations_display_name_chk
    CHECK (display_name IS NULL OR char_length(display_name) <= 64) NOT VALID;

-- ===== routes =====
ALTER TABLE public.routes DROP CONSTRAINT IF EXISTS routes_color_chk;
ALTER TABLE public.routes ADD CONSTRAINT routes_color_chk
    CHECK (color ~ '^#[0-9A-Fa-f]{6}$') NOT VALID;

ALTER TABLE public.routes DROP CONSTRAINT IF EXISTS routes_name_chk;
ALTER TABLE public.routes ADD CONSTRAINT routes_name_chk
    CHECK (name IS NULL OR char_length(name) <= 80) NOT VALID;

ALTER TABLE public.routes DROP CONSTRAINT IF EXISTS routes_room_chk;
ALTER TABLE public.routes ADD CONSTRAINT routes_room_chk
    CHECK (char_length(room) BETWEEN 1 AND 64) NOT VALID;

-- เส้นทางต้องเป็น array ของจุด อย่างน้อย 2 จุด และไม่เกิน 1000 จุด
ALTER TABLE public.routes DROP CONSTRAINT IF EXISTS routes_coordinates_chk;
ALTER TABLE public.routes ADD CONSTRAINT routes_coordinates_chk
    CHECK (
        jsonb_typeof(coordinates) = 'array'
        AND jsonb_array_length(coordinates) BETWEEN 2 AND 1000
    ) NOT VALID;

-- ===== pins =====
-- icon สั้นและห้ามมีอักขระ HTML — กัน stored XSS ตั้งแต่ต้นทาง
ALTER TABLE public.pins DROP CONSTRAINT IF EXISTS pins_icon_chk;
ALTER TABLE public.pins ADD CONSTRAINT pins_icon_chk
    CHECK (icon IS NULL OR (char_length(icon) <= 8 AND icon !~ '[<>&"'']')) NOT VALID;

ALTER TABLE public.pins DROP CONSTRAINT IF EXISTS pins_name_chk;
ALTER TABLE public.pins ADD CONSTRAINT pins_name_chk
    CHECK (char_length(name) BETWEEN 1 AND 80) NOT VALID;

ALTER TABLE public.pins DROP CONSTRAINT IF EXISTS pins_bounds_chk;
ALTER TABLE public.pins ADD CONSTRAINT pins_bounds_chk
    CHECK (lat >= 0 AND lat <= 25 AND lng >= 90 AND lng <= 115) NOT VALID;

ALTER TABLE public.pins DROP CONSTRAINT IF EXISTS pins_room_chk;
ALTER TABLE public.pins ADD CONSTRAINT pins_room_chk
    CHECK (char_length(room) BETWEEN 1 AND 64) NOT VALID;

COMMIT;
