-- 1. Create the locations table
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE, -- Unique user_id for upsert
    lat FLOAT8 NOT NULL,
    lng FLOAT8 NOT NULL,
    display_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ, -- Will be calculated by trigger
    is_sharing BOOLEAN DEFAULT true -- false = soft delete (stopped sharing)
);

-- 2. Create a function to auto-set updated_at and expires_at
-- This ensures updated_at always uses server time (not client clock)
CREATE OR REPLACE FUNCTION set_updated_and_expires()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  NEW.expires_at = NOW() + INTERVAL '15 minutes';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create a trigger to run the function before INSERT or UPDATE
DROP TRIGGER IF EXISTS trigger_set_expires_at ON public.locations;
DROP TRIGGER IF EXISTS trigger_set_updated_and_expires ON public.locations;
CREATE TRIGGER trigger_set_updated_and_expires
BEFORE INSERT OR UPDATE ON public.locations
FOR EACH ROW
EXECUTE FUNCTION set_updated_and_expires();

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- 5. Create policies to allow public access (for now)
DROP POLICY IF EXISTS "Enable insert for everyone" ON public.locations;
CREATE POLICY "Enable insert for everyone" ON public.locations
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Enable select for everyone" ON public.locations;
CREATE POLICY "Enable select for everyone" ON public.locations
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable update for everyone" ON public.locations;
CREATE POLICY "Enable update for everyone" ON public.locations
    FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Enable delete for everyone" ON public.locations;
CREATE POLICY "Enable delete for everyone" ON public.locations
    FOR DELETE USING (true);

-- 6. Optional: Create a function to clean up old locations
-- This can be called via cron or manually
CREATE OR REPLACE FUNCTION delete_expired_locations()
RETURNS void AS $$
BEGIN
  DELETE FROM public.locations WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- 7. Routes table (for drawn polylines)
CREATE TABLE IF NOT EXISTS public.routes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    room TEXT NOT NULL DEFAULT 'main',
    name TEXT,
    coordinates JSONB NOT NULL,   -- [[lat,lng], [lat,lng], ...]
    color TEXT DEFAULT '#3388ff',
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read routes" ON public.routes;
CREATE POLICY "Anyone can read routes" ON public.routes
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can insert routes" ON public.routes;
CREATE POLICY "Anyone can insert routes" ON public.routes
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone can delete routes" ON public.routes;
CREATE POLICY "Anyone can delete routes" ON public.routes
    FOR DELETE USING (true);

-- 8. Pins table (destination markers)
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

DROP POLICY IF EXISTS "Anyone can read pins" ON public.pins;
CREATE POLICY "Anyone can read pins" ON public.pins
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can insert pins" ON public.pins;
CREATE POLICY "Anyone can insert pins" ON public.pins
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone can delete pins" ON public.pins;
CREATE POLICY "Anyone can delete pins" ON public.pins
    FOR DELETE USING (true);
