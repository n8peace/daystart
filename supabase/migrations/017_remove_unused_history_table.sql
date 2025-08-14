-- Remove unused daystart_history table
-- The iOS app stores history locally, not in Supabase
-- This table was never used in production

-- Drop policies first
DROP POLICY IF EXISTS "Users can access their own history" ON daystart_history;
DROP POLICY IF EXISTS "Service role full access history" ON daystart_history;

-- Remove references in cleanup_old_data function
CREATE OR REPLACE FUNCTION cleanup_old_data(days_to_keep INTEGER DEFAULT 30)
RETURNS TABLE(jobs_deleted INTEGER) AS $$
DECLARE
  cutoff_date TIMESTAMPTZ := NOW() - (days_to_keep || ' days')::INTERVAL;
  jobs_count INTEGER;
BEGIN
  -- Delete old completed/failed jobs
  DELETE FROM jobs 
  WHERE created_at < cutoff_date 
    AND status IN ('ready', 'failed');
  GET DIAGNOSTICS jobs_count = ROW_COUNT;
  
  -- Return only jobs count (removed history_deleted)
  RETURN QUERY SELECT jobs_count;
END;
$$ LANGUAGE plpgsql;

-- Drop the table and its indexes (CASCADE will drop the indexes)
DROP TABLE IF EXISTS daystart_history CASCADE;

-- Update the comment on cleanup_old_data to reflect the change
COMMENT ON FUNCTION cleanup_old_data(INTEGER) IS 
  'Cleanup old jobs after specified days. History is managed locally on iOS devices.';