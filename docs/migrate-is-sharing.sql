-- Migration 4: Add is_sharing column for soft delete (issue #11)
-- Stop sharing = UPDATE is_sharing=false (instead of DELETE)

ALTER TABLE public.locations ADD COLUMN IF NOT EXISTS is_sharing BOOLEAN DEFAULT true;
