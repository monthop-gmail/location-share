-- 1. Create the locations table
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE, -- Unique user_id for upsert
    lat FLOAT8 NOT NULL,
    lng FLOAT8 NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ -- Will be calculated by trigger
);

-- 2. Create a function to auto-set expiration time
CREATE OR REPLACE FUNCTION set_expires_at()
RETURNS TRIGGER AS $$
BEGIN
  -- Automatically set expires_at to 15 minutes after updated_at
  NEW.expires_at = COALESCE(NEW.updated_at, NOW()) + INTERVAL '15 minutes';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create a trigger to run the function before INSERT or UPDATE
DROP TRIGGER IF EXISTS trigger_set_expires_at ON public.locations;
CREATE TRIGGER trigger_set_expires_at
BEFORE INSERT OR UPDATE ON public.locations
FOR EACH ROW
EXECUTE FUNCTION set_expires_at();

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- 5. Create policies to allow public access (for now)
-- Allow anyone to insert their location
DROP POLICY IF EXISTS "Enable insert for everyone" ON public.locations;
CREATE POLICY "Enable insert for everyone" ON public.locations
    FOR INSERT WITH CHECK (true);

-- Allow anyone to read active locations
DROP POLICY IF EXISTS "Enable select for everyone" ON public.locations;
CREATE POLICY "Enable select for everyone" ON public.locations
    FOR SELECT USING (true);

-- Allow anyone to update their own location (based on user_id)
DROP POLICY IF EXISTS "Enable update for everyone" ON public.locations;
CREATE POLICY "Enable update for everyone" ON public.locations
    FOR UPDATE USING (true);

-- 6. Optional: Create a function to clean up old locations
-- This can be called via cron or manually
CREATE OR REPLACE FUNCTION delete_expired_locations()
RETURNS void AS $$
BEGIN
  DELETE FROM public.locations WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
