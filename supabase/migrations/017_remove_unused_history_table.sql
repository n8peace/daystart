-- Remove unused daystart_history table
-- The iOS app stores history locally, not in Supabase
-- This table was never used in production

-- Drop policies first
DROP POLICY IF EXISTS "Users can access their own history" ON daystart_history;
DROP POLICY IF EXISTS "Service role full access history" ON daystart_history;

-- Drop the existing cleanup_old_data function to change its return type
-- This is necessary because PostgreSQL doesn't allow changing return types with CREATE OR REPLACE
DROP FUNCTION IF EXISTS cleanup_old_data(INTEGER);

-- Recreate cleanup_old_data function without history references
CREATE OR REPLACE FUNCTION cleanup_old_data(days_to_keep INTEGER DEFAULT 30)
RETURNS TABLE(jobs_deleted INTEGER, audio_paths_cleared INTEGER) AS $$
DECLARE
  cutoff_date TIMESTAMPTZ := NOW() - (days_to_keep || ' days')::INTERVAL;
  jobs_count INTEGER;
  audio_count INTEGER;
BEGIN
  -- Clear audio file paths from old jobs (but don't delete the job records yet)
  UPDATE jobs 
  SET audio_file_path = NULL
  WHERE created_at < cutoff_date 
    AND audio_file_path IS NOT NULL
    AND status IN ('ready', 'failed');
  GET DIAGNOSTICS audio_count = ROW_COUNT;
  
  -- Delete old completed/failed jobs
  DELETE FROM jobs 
  WHERE created_at < cutoff_date 
    AND status IN ('ready', 'failed');
  GET DIAGNOSTICS jobs_count = ROW_COUNT;
  
  -- Return jobs count and audio paths cleared (removed history_deleted)
  RETURN QUERY SELECT jobs_count, audio_count;
END;
$$ LANGUAGE plpgsql;

-- Drop the table and its indexes (CASCADE will drop the indexes)
DROP TABLE IF EXISTS daystart_history CASCADE;

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION cleanup_old_data TO service_role;

-- Update the comment on cleanup_old_data to reflect the change
COMMENT ON FUNCTION cleanup_old_data(INTEGER) IS 
  'Cleanup old jobs after specified days. History is managed locally on iOS devices.';