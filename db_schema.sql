-- Create the locations table
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL, -- using text to support LINE user ID later
    lat FLOAT8 NOT NULL,
    lng FLOAT8 NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ GENERATED ALWAYS AS (updated_at + INTERVAL '15 minutes') STORED
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- Create a policy that allows anyone to insert their location
CREATE POLICY "Enable insert for everyone" ON public.locations
    FOR INSERT WITH CHECK (true);

-- Create a policy that allows anyone to read active locations
CREATE POLICY "Enable select for everyone" ON public.locations
    FOR SELECT USING (true);

-- Create a policy that allows users to update their own location (based on user_id)
-- Note: In a real app with auth, we would check auth.uid()
CREATE POLICY "Enable update for everyone" ON public.locations
    FOR UPDATE USING (true);

-- Function to clean up old locations (can be called via cron or manually)
CREATE OR REPLACE FUNCTION delete_expired_locations()
RETURNS void AS $$
BEGIN
  DELETE FROM public.locations WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
