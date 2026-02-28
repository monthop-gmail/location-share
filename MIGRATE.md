# Migration: updated_at ใช้ server time แทน client clock

## ปัญหา

ตอนนี้ `updated_at` ส่งจาก client (`new Date()`) ซึ่งขึ้นกับนาฬิกาของ user
ถ้านาฬิกาผิด → `isToday()` ทำงานผิด → เพื่อนหายจากรายชื่อ

## วิธีแก้

รัน SQL นี้ใน **Supabase Dashboard → SQL Editor**:

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

## สิ่งที่เปลี่ยน

- Trigger เดิม `set_expires_at` → แทนด้วย `set_updated_and_expires`
- `updated_at` จะถูก set เป็น `NOW()` ทุกครั้งที่ INSERT/UPDATE (ไม่ใช้ค่าจาก client)
- `expires_at` ก็ใช้ `NOW() + 15 min` เหมือนเดิม
- หลังรัน SQL แล้ว → client code จะลบ `updated_at: new Date()` ออกจาก upsert

---

# Migration: เพิ่มตาราง routes (วาดเส้นทาง)

## วิธีแก้

รัน SQL นี้ใน **Supabase Dashboard → SQL Editor**:

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

CREATE POLICY "Anyone can read routes" ON public.routes
    FOR SELECT USING (true);

CREATE POLICY "Anyone can insert routes" ON public.routes
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can delete routes" ON public.routes
    FOR DELETE USING (true);
```

## สิ่งที่เปลี่ยน

- ตาราง `routes` ใหม่สำหรับเก็บเส้นทางที่วาดบนแผนที่
- `coordinates` เป็น JSONB array ของ `[[lat, lng], ...]`
- แยกตาม `room` — แต่ละห้องเห็นเฉพาะเส้นทางของห้องตัวเอง
- RLS: ทุกคนอ่าน/เพิ่ม/ลบได้
