-- Add is_welcome column to jobs table for welcome/onboarding DayStarts
ALTER TABLE jobs ADD COLUMN is_welcome BOOLEAN DEFAULT FALSE;

-- Document the column
COMMENT ON COLUMN jobs.is_welcome IS 'True for welcome/onboarding DayStarts that need special script content';