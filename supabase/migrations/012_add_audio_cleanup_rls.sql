-- Add Row Level Security to audio_cleanup_log table
-- Following the same pattern as other system tables like request_logs

-- Enable RLS on audio_cleanup_log table
ALTER TABLE audio_cleanup_log ENABLE ROW LEVEL SECURITY;

-- Service role can access everything (for cleanup operations)
CREATE POLICY "Service role full access audio cleanup" ON audio_cleanup_log
  FOR ALL TO service_role USING (true);

-- Add comment explaining the RLS policy
COMMENT ON POLICY "Service role full access audio cleanup" ON audio_cleanup_log IS 
  'Service role has full access to audio cleanup logs for system operations';
