-- Migration 033: Add public data fields to shares table
-- Date: 2025-10-21
-- Purpose: Store public job data directly in shares table to avoid exposing sensitive jobs table to anon users

-- Add public data fields from jobs table to public_daystart_shares
ALTER TABLE public_daystart_shares 
ADD COLUMN audio_file_path TEXT,
ADD COLUMN audio_duration INTEGER,
ADD COLUMN local_date TEXT,
ADD COLUMN daystart_length INTEGER,
ADD COLUMN preferred_name TEXT;

-- Add comments for the new fields
COMMENT ON COLUMN public_daystart_shares.audio_file_path IS 'Storage path for the audio file (copied from jobs table at share creation)';
COMMENT ON COLUMN public_daystart_shares.audio_duration IS 'Duration of the audio in seconds (copied from jobs table)';
COMMENT ON COLUMN public_daystart_shares.local_date IS 'Local date string for the briefing (copied from jobs table)';
COMMENT ON COLUMN public_daystart_shares.daystart_length IS 'Length of the briefing in seconds (copied from jobs table)';
COMMENT ON COLUMN public_daystart_shares.preferred_name IS 'User preferred name for personalization (copied from jobs table)';

-- Update the RLS policy comment to reflect new structure
COMMENT ON POLICY "Public read for valid shares" ON public_daystart_shares IS 
'Allows anonymous and authenticated users to read share data for valid, non-expired shares. All necessary data is stored locally in this table.';