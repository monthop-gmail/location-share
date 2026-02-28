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
