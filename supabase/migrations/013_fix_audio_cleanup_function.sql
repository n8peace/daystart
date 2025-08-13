-- Fix the get_audio_files_to_cleanup function to use correct column name
-- The jobs table uses 'job_id' not 'id' as the primary key

-- Drop and recreate the function with the correct column reference
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
    j.job_id as job_id,  -- Changed from j.id to j.job_id
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

-- Also fix the mark_audio_files_deleted function to use correct column name
CREATE OR REPLACE FUNCTION mark_audio_files_deleted(job_ids UUID[])
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE jobs
  SET 
    audio_file_path = NULL,
    updated_at = NOW()
  WHERE job_id = ANY(job_ids);  -- Changed from id to job_id
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Add comment about the fix
COMMENT ON FUNCTION get_audio_files_to_cleanup IS 'Returns list of audio files older than specified days that should be deleted from storage. Fixed to use correct job_id column name.';
COMMENT ON FUNCTION mark_audio_files_deleted IS 'Updates job records to clear audio_file_path after successful storage deletion. Fixed to use correct job_id column name.';