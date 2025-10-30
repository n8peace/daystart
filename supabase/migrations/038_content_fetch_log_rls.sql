-- Add Row Level Security to content_fetch_log table
-- This table contains operational data about API fetches, not user data
-- Date: 2025-01-20

-- Enable RLS on the table
ALTER TABLE content_fetch_log ENABLE ROW LEVEL SECURITY;

-- Service role can insert new log entries (used by refresh_content function)
CREATE POLICY "service_role_insert_content_fetch_log" ON content_fetch_log
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Service role can read all logs (used by healthcheck and monitoring)
CREATE POLICY "service_role_select_content_fetch_log" ON content_fetch_log
  FOR SELECT
  TO service_role
  USING (true);

-- Anon users cannot access this table at all
-- (No policies for anon role = no access)

-- Add comment explaining the security model
COMMENT ON TABLE content_fetch_log IS 
  'Tracks all content fetch attempts from external APIs. Used to monitor API reliability, cache fallback usage, and content freshness for healthcheck reporting. RLS enabled - only accessible by service_role for system monitoring.';

-- Also secure the summary function to service_role only
REVOKE ALL ON FUNCTION get_content_freshness_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_content_freshness_summary() TO service_role;

-- Add cleanup policy to prevent unbounded growth
-- Keep only last 7 days of logs
CREATE OR REPLACE FUNCTION cleanup_old_content_fetch_logs()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM content_fetch_log
  WHERE created_at < NOW() - INTERVAL '7 days';
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service role only
GRANT EXECUTE ON FUNCTION cleanup_old_content_fetch_logs() TO service_role;

-- Add index for efficient cleanup
CREATE INDEX IF NOT EXISTS idx_content_fetch_log_cleanup 
  ON content_fetch_log(created_at) 
  WHERE created_at < NOW() - INTERVAL '7 days';

COMMENT ON FUNCTION cleanup_old_content_fetch_logs IS 
  'Removes content fetch logs older than 7 days to prevent unbounded table growth. Should be called periodically by a scheduled job.';