-- Recreate cleanup_old_data function with new signature to support audio file cleanup
-- This migration recreates the function that was dropped in migration 010
-- The new version includes audio_paths_cleared in the return type

-- Create the enhanced cleanup_old_data function with audio file support
CREATE OR REPLACE FUNCTION cleanup_old_data(days_to_keep INTEGER DEFAULT 30)
RETURNS TABLE(jobs_deleted INTEGER, history_deleted INTEGER, audio_paths_cleared INTEGER) AS $$
DECLARE
  cutoff_date TIMESTAMPTZ := NOW() - (days_to_keep || ' days')::INTERVAL;
  jobs_count INTEGER;
  history_count INTEGER;
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
  
  -- Mark old history as deleted (keep for analytics)
  UPDATE daystart_history 
  SET is_deleted = TRUE 
  WHERE created_at < cutoff_date 
    AND is_deleted = FALSE;
  GET DIAGNOSTICS history_count = ROW_COUNT;
  
  RETURN QUERY SELECT jobs_count, history_count, audio_count;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to the same roles as other cleanup functions
GRANT EXECUTE ON FUNCTION cleanup_old_data TO service_role;

-- Add comment explaining the enhanced functionality
COMMENT ON FUNCTION cleanup_old_data IS 'Cleans up old data including jobs, history, and audio file paths. Enhanced in migration 011 to track audio paths cleared.';
