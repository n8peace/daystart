-- Add sports preferences support
-- Add selected_sports column to jobs table for granular sports filtering

-- Add selected_sports column with backward-compatible default
-- Default includes all major sports for existing functionality
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS selected_sports TEXT[] DEFAULT ARRAY['MLB', 'NHL', 'NBA', 'NFL', 'NCAAF'];

-- Add comment for documentation
COMMENT ON COLUMN jobs.selected_sports IS 'Array of selected sports leagues for content filtering. Default includes all major sports for backward compatibility.';

-- Update the jobs table comment to reflect the new column
COMMENT ON TABLE jobs IS 'Core job queue for DayStart generation with user preferences captured at creation time, including sports filtering preferences';