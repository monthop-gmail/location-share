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
