-- Add user completion tracking to measure DayStarts that have been 80%+ listened to
-- This is backwards compatible - adds new columns with defaults that don't affect existing functionality
BEGIN;

-- Add user_completed column with default false
ALTER TABLE jobs ADD COLUMN user_completed BOOLEAN DEFAULT FALSE;

-- Add completion timestamp for analytics
ALTER TABLE jobs ADD COLUMN user_completed_at TIMESTAMPTZ;

-- Index for efficient querying of completions
CREATE INDEX jobs_user_completed_idx ON jobs(user_id, user_completed_at DESC) 
WHERE user_completed = TRUE;

-- Add comments
COMMENT ON COLUMN jobs.user_completed IS 'Tracks if user listened to 80%+ of the DayStart audio';
COMMENT ON COLUMN jobs.user_completed_at IS 'Timestamp when user completed listening (80%+ threshold)';

COMMIT;