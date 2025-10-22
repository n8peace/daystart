-- Add functions to detect and clean up orphaned audio files in storage
-- These are files that exist in storage but have no corresponding job record

-- Function to detect orphaned audio files by comparing storage contents with job records
CREATE OR REPLACE FUNCTION get_orphaned_audio_files(
    user_id_prefix TEXT DEFAULT NULL,
    date_folder TEXT DEFAULT NULL,
    limit_count INTEGER DEFAULT 1000
)
RETURNS TABLE(
    file_path TEXT,
    user_id TEXT,
    date TEXT,
    file_name TEXT,
    estimated_job_id UUID
) AS $$
BEGIN
    -- This function is designed to be called from the edge function
    -- which will pass in the actual storage file list
    -- Returns empty set by default since we can't access storage from SQL
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Function to check if a file path has a corresponding job record
CREATE OR REPLACE FUNCTION check_audio_file_has_job(file_path TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    job_exists BOOLEAN;
BEGIN
    -- Check if a job exists with this audio_file_path
    SELECT EXISTS(
        SELECT 1 
        FROM jobs 
        WHERE audio_file_path = file_path
    ) INTO job_exists;
    
    RETURN job_exists;
END;
$$ LANGUAGE plpgsql;

-- Function to batch check multiple file paths for job records
CREATE OR REPLACE FUNCTION check_audio_files_have_jobs(file_paths TEXT[])
RETURNS TABLE(
    file_path TEXT,
    has_job BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        path as file_path,
        EXISTS(
            SELECT 1 
            FROM jobs j
            WHERE j.audio_file_path = path
        ) as has_job
    FROM unnest(file_paths) as path;
END;
$$ LANGUAGE plpgsql;

-- Enhanced cleanup stats to include orphan information
CREATE OR REPLACE FUNCTION get_audio_cleanup_stats_enhanced()
RETURNS JSON AS $$
DECLARE
    stats JSON;
BEGIN
    SELECT json_build_object(
        'total_jobs_with_audio', COUNT(*) FILTER (WHERE audio_file_path IS NOT NULL),
        'jobs_ready_with_audio', COUNT(*) FILTER (WHERE status = 'ready' AND audio_file_path IS NOT NULL),
        'oldest_audio_date', MIN(created_at) FILTER (WHERE audio_file_path IS NOT NULL),
        'newest_audio_date', MAX(created_at) FILTER (WHERE audio_file_path IS NOT NULL),
        'files_older_than_10_days', COUNT(*) FILTER (WHERE audio_file_path IS NOT NULL AND created_at < NOW() - INTERVAL '10 days'),
        'last_cleanup_run', (
            SELECT json_build_object(
                'started_at', started_at,
                'completed_at', completed_at,
                'files_deleted', files_deleted,
                'files_failed', files_failed,
                'orphans_deleted', (error_details->>'orphans_deleted')::INTEGER
            )
            FROM audio_cleanup_log
            WHERE completed_at IS NOT NULL
            ORDER BY started_at DESC
            LIMIT 1
        ),
        'test_jobs_count', COUNT(*) FILTER (WHERE user_id LIKE 'test-deploy-%' OR user_id LIKE 'test-manual-%')
    )
    FROM jobs
    INTO stats;
    
    RETURN stats;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT EXECUTE ON FUNCTION check_audio_file_has_job TO service_role;
GRANT EXECUTE ON FUNCTION check_audio_files_have_jobs TO service_role;
GRANT EXECUTE ON FUNCTION get_audio_cleanup_stats_enhanced TO service_role, authenticated;

-- Add comments
COMMENT ON FUNCTION check_audio_file_has_job IS 'Checks if a single audio file path has a corresponding job record';
COMMENT ON FUNCTION check_audio_files_have_jobs IS 'Batch checks multiple audio file paths for corresponding job records';
COMMENT ON FUNCTION get_audio_cleanup_stats_enhanced IS 'Enhanced cleanup statistics including orphan file information';