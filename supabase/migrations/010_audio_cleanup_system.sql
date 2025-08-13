-- Audio cleanup system for removing old audio files from storage
-- This migration creates functions and tables to track and clean up audio files older than X days

-- Create cleanup log table to track cleanup operations
CREATE TABLE IF NOT EXISTS audio_cleanup_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  files_found INTEGER DEFAULT 0,
  files_deleted INTEGER DEFAULT 0,
  files_failed INTEGER DEFAULT 0,
  error_details JSONB,
  cleanup_type TEXT DEFAULT 'scheduled', -- 'scheduled', 'manual'
  initiated_by TEXT,
  runtime_seconds NUMERIC,
  CONSTRAINT valid_cleanup_type CHECK (cleanup_type IN ('scheduled', 'manual'))
);

-- Index for querying recent cleanup operations
CREATE INDEX idx_audio_cleanup_log_started_at ON audio_cleanup_log(started_at DESC);

-- Function to get list of audio files that should be deleted
CREATE OR REPLACE FUNCTION get_audio_files_to_cleanup(days_to_keep INTEGER DEFAULT 10)
RETURNS TABLE(
  job_id UUID,
  user_id TEXT,
  audio_file_path TEXT,
  created_at TIMESTAMPTZ,
  days_old INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    j.id as job_id,
    j.user_id,
    j.audio_file_path,
    j.created_at,
    EXTRACT(DAY FROM NOW() - j.created_at)::INTEGER as days_old
  FROM jobs j
  WHERE 
    j.audio_file_path IS NOT NULL
    AND j.audio_file_path != ''
    AND j.created_at < NOW() - (days_to_keep || ' days')::INTERVAL
    AND j.status = 'ready'
  ORDER BY j.created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- Function to mark audio files as deleted in the database
CREATE OR REPLACE FUNCTION mark_audio_files_deleted(job_ids UUID[])
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE jobs
  SET 
    audio_file_path = NULL,
    updated_at = NOW()
  WHERE id = ANY(job_ids);
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get cleanup statistics
CREATE OR REPLACE FUNCTION get_audio_cleanup_stats()
RETURNS TABLE(
  total_audio_files BIGINT,
  files_older_than_10_days BIGINT,
  files_older_than_30_days BIGINT,
  total_storage_paths BIGINT,
  last_cleanup_date TIMESTAMPTZ,
  last_cleanup_deleted INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(CASE WHEN j.audio_file_path IS NOT NULL THEN 1 END) as total_audio_files,
    COUNT(CASE WHEN j.audio_file_path IS NOT NULL AND j.created_at < NOW() - INTERVAL '10 days' THEN 1 END) as files_older_than_10_days,
    COUNT(CASE WHEN j.audio_file_path IS NOT NULL AND j.created_at < NOW() - INTERVAL '30 days' THEN 1 END) as files_older_than_30_days,
    COUNT(DISTINCT j.audio_file_path) as total_storage_paths,
    MAX(acl.completed_at) as last_cleanup_date,
    (SELECT files_deleted FROM audio_cleanup_log WHERE completed_at IS NOT NULL ORDER BY completed_at DESC LIMIT 1) as last_cleanup_deleted
  FROM jobs j
  LEFT JOIN audio_cleanup_log acl ON acl.completed_at IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to check if cleanup should run (prevents running too frequently)
CREATE OR REPLACE FUNCTION should_run_audio_cleanup()
RETURNS BOOLEAN AS $$
DECLARE
  last_run TIMESTAMPTZ;
  min_hours_between_runs INTEGER := 20; -- Minimum 20 hours between runs
BEGIN
  SELECT MAX(started_at) INTO last_run
  FROM audio_cleanup_log
  WHERE completed_at IS NOT NULL;
  
  -- If never run, allow it
  IF last_run IS NULL THEN
    RETURN TRUE;
  END IF;
  
  -- Check if enough time has passed
  RETURN (NOW() - last_run) > (min_hours_between_runs || ' hours')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- Update the existing cleanup_old_data function to also handle audio files
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

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE ON audio_cleanup_log TO service_role;
GRANT EXECUTE ON FUNCTION get_audio_files_to_cleanup TO service_role;
GRANT EXECUTE ON FUNCTION mark_audio_files_deleted TO service_role;
GRANT EXECUTE ON FUNCTION get_audio_cleanup_stats TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION should_run_audio_cleanup TO service_role;

-- Add helpful comments
COMMENT ON TABLE audio_cleanup_log IS 'Tracks audio file cleanup operations for monitoring and debugging';
COMMENT ON FUNCTION get_audio_files_to_cleanup IS 'Returns list of audio files older than specified days that should be deleted from storage';
COMMENT ON FUNCTION mark_audio_files_deleted IS 'Updates job records to clear audio_file_path after successful storage deletion';
COMMENT ON FUNCTION get_audio_cleanup_stats IS 'Returns statistics about audio files and cleanup operations';
COMMENT ON FUNCTION should_run_audio_cleanup IS 'Checks if enough time has passed since last cleanup to prevent too frequent runs';