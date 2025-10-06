-- Add social_daystart column to support social media DayStart generation
-- This allows special DayStart jobs to include intro/outro for social media posting
BEGIN;

-- Add social_daystart column with default FALSE for backwards compatibility
ALTER TABLE jobs ADD COLUMN social_daystart BOOLEAN DEFAULT FALSE;

-- Add index for efficient querying of social jobs
CREATE INDEX jobs_social_daystart_idx ON jobs(social_daystart) WHERE social_daystart = TRUE;

-- Add comment documenting the feature
COMMENT ON COLUMN jobs.social_daystart IS 'When TRUE, adds intro/outro content for social media distribution (e.g., TikTok daily posts)';

COMMIT;