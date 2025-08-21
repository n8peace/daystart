-- Update RLS policies to use auth.uid() instead of JWT claims
-- This migration updates the security model to work with proper Supabase authentication

-- Drop existing RLS policies
DROP POLICY IF EXISTS "Users can access their own jobs" ON jobs;
DROP POLICY IF EXISTS "Users can access their own logs" ON request_logs;

-- Create new RLS policies using auth.uid()
-- Jobs table: Users can only access their own jobs
CREATE POLICY "Users can access their own jobs" ON jobs
  FOR ALL USING (user_id::uuid = auth.uid());

-- Request logs: Users can only access their own logs  
CREATE POLICY "Users can access their own logs" ON request_logs
  FOR ALL USING (user_id::uuid = auth.uid());

-- Service role policies remain unchanged (they need full access for processing)
-- These policies already exist:
-- - "Service role full access" ON jobs
-- - "Service role full access logs" ON request_logs

-- Update the user_id column comments to reflect the new UUID-based approach
COMMENT ON COLUMN jobs.user_id IS 'User UUID from Supabase auth.uid() - identifies authenticated users';
COMMENT ON COLUMN request_logs.user_id IS 'User UUID from Supabase auth.uid() - identifies authenticated users';

-- Note: The user_id column type remains TEXT to maintain compatibility
-- The auth.uid() returns UUID but we cast it to match the existing column type
-- In a future migration, we could change the column type to UUID for better performance
