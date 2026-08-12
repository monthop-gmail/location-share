# Migrations

รัน SQL ใน **Supabase Dashboard → SQL Editor**

---

## Migration 1: updated_at ใช้ server time — Done

```sql
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
```

## Migration 2: เพิ่มตาราง routes — Done

```sql
CREATE TABLE IF NOT EXISTS public.routes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room TEXT NOT NULL DEFAULT 'main',
  name TEXT,
  coordinates JSONB NOT NULL,
  color TEXT DEFAULT '#3388ff',
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read routes" ON public.routes FOR SELECT USING (true);
CREATE POLICY "Anyone can insert routes" ON public.routes FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can delete routes" ON public.routes FOR DELETE USING (true);
```

## Migration 3: เพิ่มตาราง pins (จุดหมาย)

```sql
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

ALTER TABLE public.pins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read pins" ON public.pins FOR SELECT USING (true);
CREATE POLICY "Anyone can insert pins" ON public.pins FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can delete pins" ON public.pins FOR DELETE USING (true);
```

## Migration 4: ยกห้องขึ้นมาเป็นคอลัมน์จริง — **ต้องรัน**

ไฟล์: [`migrate-rooms.sql`](migrate-rooms.sql)

เดิมห้องถูกยัดไว้ใน `user_id` เป็น `user_xxxx@ชื่อห้อง` ทำให้กรองที่ DB ไม่ได้
client จึงต้องดึงทุกแถวของทุกห้องมาแล้วค่อยกรองเอง

> ⚠️ **ต้องรันไฟล์นี้ให้เสร็จก่อน deploy `index.html` เวอร์ชันใหม่**
> เพราะ client ใหม่ upsert ด้วย `onConflict: 'user_id,room'` ซึ่งต้องมี
> unique index `(user_id, room)` อยู่ก่อน

## Migration 5: CHECK constraint ฝั่ง server — **ต้องรัน**

ไฟล์: [`migrate-validation.sql`](migrate-validation.sql)

บังคับกติกาเดียวกับที่ client ใช้ลงไปที่ DB — พิกัดต้องอยู่ในกรอบ,
`icon` ห้ามมีอักขระ HTML, จำกัดความยาวชื่อ, `coordinates` ต้องเป็น array 2–1000 จุด
ใช้ `NOT VALID` ทุกตัว จึงบังคับเฉพาะแถวใหม่และไม่ล้มเพราะข้อมูลเดิม

รันตอนไหนก็ได้ ไม่ผูกกับการ deploy

## Migration 6: ตั้ง cron ลบตำแหน่งหมดอายุ — **ต้องรัน**

ไฟล์: [`migrate-cleanup-cron.sql`](migrate-cleanup-cron.sql)

`delete_expired_locations()` มีมาตั้งแต่แรกแต่ไม่เคยมีอะไรเรียก ตาราง `locations`
จึงโตขึ้นเรื่อยๆ ไฟล์นี้เปิด `pg_cron` แล้วตั้งให้เรียกทุก 5 นาที

ตรวจผลด้วย `SELECT jobname, schedule, active FROM cron.job;`

## Migration 7: ผูกแถวกับเจ้าของ (issue #3) — **ยังไม่ต้องรัน**

ไฟล์: [`migrate-rls-owner.sql`](migrate-rls-owner.sql)

ปิดช่อง "ใครมี anon key ก็ลบข้อมูลคนอื่นได้" แต่ต้องเปิด Anonymous Sign-ins
ใน Dashboard และต้อง deploy client ที่เรียก `signInAnonymously()` พร้อมกัน

อ่าน [SECURITY.md](SECURITY.md) ให้ครบก่อนตัดสินใจ — มีข้อแลกเปลี่ยนที่ต้องรับทราบ

---

## ลำดับการรันทั้งหมด (โปรเจกต์ที่มีข้อมูลอยู่แล้ว)

```
1. migrate-rooms.sql        ← รันก่อน deploy
2. deploy index.html ใหม่
3. migrate-validation.sql   ← รันตอนไหนก็ได้
4. migrate-cleanup-cron.sql ← รันตอนไหนก็ได้
5. migrate-rls-owner.sql    ← เมื่อพร้อม อ่าน SECURITY.md ก่อน
```

Schema ทั้งหมดดู [db_schema.sql](db_schema.sql)
