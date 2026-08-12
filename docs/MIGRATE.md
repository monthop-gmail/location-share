# Migrations

## ไฟล์ใน `migrations/` รันอัตโนมัติ

GitHub Actions รัน `migrations/*.sql` ทั้งหมดตามลำดับชื่อไฟล์ **ก่อน** deploy ทุกครั้ง
ที่ push เข้า `main` (job `migrate` ใน `.github/workflows/deploy.yml` และ job `deploy`
ผูก `needs: migrate` ไว้) จึงไม่มีทางที่ code ใหม่จะขึ้นไปเจอ schema เก่า

ทุกไฟล์เขียนให้รันซ้ำได้ เพราะมันถูกรันซ้ำจริงทุก push
`tests/migrations.sh` พิสูจน์เรื่องนี้ใน CI โดยรันสองรอบกับ Postgres เปล่า

**ต้องตั้ง secret `SUPABASE_DB_URL` ก่อน** ไม่งั้น deploy จะล้มทั้งหมด (ตั้งใจให้ล้ม):
Supabase Dashboard → Project Settings → Database → Connection string → URI
(ใช้ session pooler พอร์ต 5432) แล้วใส่ที่ Settings → Secrets and variables → Actions

## ไฟล์ใน `docs/` รันเอง

ไฟล์ที่ต้องตัดสินใจหรือต้องไปกดอะไรใน Dashboard ก่อน จะไม่อยู่ใน `migrations/`
ต้องรันเองใน **Supabase Dashboard → SQL Editor**

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

## Migration 4: ยกห้องขึ้นมาเป็นคอลัมน์จริง — อัตโนมัติ

ไฟล์: [`migrations/001_rooms.sql`](../migrations/001_rooms.sql)

เดิมห้องถูกยัดไว้ใน `user_id` เป็น `user_xxxx@ชื่อห้อง` ทำให้กรองที่ DB ไม่ได้
client จึงต้องดึงทุกแถวของทุกห้องมาแล้วค่อยกรองเอง

client ใหม่ upsert ด้วย `onConflict: 'user_id,room'` จึงต้องมี unique index
`(user_id, room)` อยู่ก่อน — job `migrate` รับประกันลำดับนี้ให้แล้ว

ลำดับภายในไฟล์ก็สำคัญ: ต้อง `DROP CONSTRAINT locations_user_id_key` **ก่อน** backfill
ไม่งั้นคนที่อยู่ทั้งห้อง main และห้องอื่นจะชน unique ตอนถูกตัด `@` ออก
(`tests/migrations.sh` จับเคสนี้ไว้แล้ว)

## Migration 5: CHECK constraint ฝั่ง server — อัตโนมัติ

ไฟล์: [`migrations/002_validation.sql`](../migrations/002_validation.sql)

บังคับกติกาเดียวกับที่ client ใช้ลงไปที่ DB — พิกัดต้องอยู่ในกรอบ,
`icon` ห้ามมีอักขระ HTML, จำกัดความยาวชื่อ, `coordinates` ต้องเป็น array 2–1000 จุด
ใช้ `NOT VALID` ทุกตัว จึงบังคับเฉพาะแถวใหม่และไม่ล้มเพราะข้อมูลเดิม

## Migration 6: ตั้ง cron ลบตำแหน่งหมดอายุ — อัตโนมัติ

ไฟล์: [`migrations/003_cleanup_cron.sql`](../migrations/003_cleanup_cron.sql)

`delete_expired_locations()` มีมาตั้งแต่แรกแต่ไม่เคยมีอะไรเรียก ตาราง `locations`
จึงโตขึ้นเรื่อยๆ ไฟล์นี้เปิด `pg_cron` แล้วตั้งให้เรียกทุก 5 นาที

การตั้ง schedule ห่อไว้ใน `DO` block ที่จับ exception ถ้าโปรเจกต์ไหนเปิด `pg_cron`
ไม่ได้ จะเตือนแล้วผ่านไป ไม่ทำให้ deploy ทั้งชุดล้ม

ตรวจผลด้วย `SELECT jobname, schedule, active FROM cron.job;`

## Migration 7: ผูกแถวกับเจ้าของ (issue #3) — **รันเอง**

ไฟล์: [`migrate-rls-owner.sql`](migrate-rls-owner.sql) — จงใจไม่อยู่ใน `migrations/`

ปิดช่อง "ใครมี anon key ก็ลบข้อมูลคนอื่นได้" แต่ต้องเปิด Anonymous Sign-ins
ใน Dashboard และต้อง deploy client ที่เรียก `signInAnonymously()` พร้อมกัน
ถ้ามันรันอัตโนมัติตอนที่ยังไม่ได้เปิด provider แอปจะเขียนข้อมูลไม่ได้เลย

อ่าน [SECURITY.md](SECURITY.md) ให้ครบก่อนตัดสินใจ — มีข้อแลกเปลี่ยนที่ต้องรับทราบ

---

## สรุปการทำงาน

```
push เข้า main
   └─ job: migrate   รัน migrations/*.sql ตามลำดับชื่อไฟล์
        └─ job: deploy   (needs: migrate)  wrangler pages deploy
```

รันเองเมื่อพร้อม: `docs/migrate-rls-owner.sql`

Schema ทั้งหมดดู [db_schema.sql](db_schema.sql)
