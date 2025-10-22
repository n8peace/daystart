-- Fix the check_audio_files_have_jobs function to properly handle unnest
-- The previous version had a PostgreSQL error: "set-returning functions are not allowed in WHERE"

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

-- Add comment about the fix
COMMENT ON FUNCTION check_audio_files_have_jobs IS 'Batch checks multiple audio file paths for corresponding job records. Fixed to properly handle unnest in FROM clause.';