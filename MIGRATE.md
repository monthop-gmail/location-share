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
