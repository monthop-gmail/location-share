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

---

Schema ทั้งหมดดู [db_schema.sql](db_schema.sql)
