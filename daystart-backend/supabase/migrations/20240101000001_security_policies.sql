-- Enhanced Security Policies for DayStart Backend
-- Created: 2024-01-01
-- This migration adds comprehensive RLS policies with proper security

-- Drop existing policies to recreate with proper security
DROP POLICY IF EXISTS "Users can manage their own schedule" ON user_schedule;
DROP POLICY IF EXISTS "Users can view their own jobs" ON jobs;
DROP POLICY IF EXISTS "Users can view their quote history" ON quote_history;
DROP POLICY IF EXISTS "Service role full access jobs" ON jobs;
DROP POLICY IF EXISTS "Service role full access content" ON content_blocks;
DROP POLICY IF EXISTS "Service role full access logs" ON logs;
DROP POLICY IF EXISTS "Service role full access quotes" ON quote_history;
DROP POLICY IF EXISTS "Service role full access schedule" ON user_schedule;
DROP POLICY IF EXISTS "Service role can manage audio files" ON storage.objects;

-- USER_SCHEDULE TABLE POLICIES
-- Users can only access their own schedule
CREATE POLICY "Users can view own schedule" ON user_schedule
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own schedule" ON user_schedule
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own schedule" ON user_schedule
  FOR UPDATE USING (auth.uid() = user_id) 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own schedule" ON user_schedule
  FOR DELETE USING (auth.uid() = user_id);

-- Service role can manage all schedules (for backend operations)
CREATE POLICY "Service role can manage all schedules" ON user_schedule
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- JOBS TABLE POLICIES
-- Users can only view their own jobs
CREATE POLICY "Users can view own jobs" ON jobs
  FOR SELECT USING (auth.uid() = user_id);

-- Users CANNOT directly insert/update/delete jobs - only via Edge Functions
CREATE POLICY "Users cannot modify jobs directly" ON jobs
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY "Users cannot update jobs directly" ON jobs
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

CREATE POLICY "Users cannot delete jobs directly" ON jobs
  FOR DELETE TO authenticated USING (false);

-- Service role has full access for job processing
CREATE POLICY "Service role full access jobs" ON jobs
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- CONTENT_BLOCKS TABLE POLICIES
-- Users cannot access content_blocks directly - only via Edge Functions
CREATE POLICY "Users cannot access content blocks" ON content_blocks
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- Service role can manage content blocks
CREATE POLICY "Service role full access content" ON content_blocks
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- QUOTE_HISTORY TABLE POLICIES  
-- Users can view their own quote history (read-only)
CREATE POLICY "Users can view own quote history" ON quote_history
  FOR SELECT USING (auth.uid() = user_id);

-- Users cannot modify quote history directly
CREATE POLICY "Users cannot modify quote history" ON quote_history
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY "Users cannot update quote history" ON quote_history
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

CREATE POLICY "Users cannot delete quote history" ON quote_history
  FOR DELETE TO authenticated USING (false);

-- Service role can manage quote history
CREATE POLICY "Service role full access quotes" ON quote_history
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- LOGS TABLE POLICIES
-- Users cannot access logs at all - system use only
CREATE POLICY "Users cannot access logs" ON logs
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- Service role can manage logs
CREATE POLICY "Service role full access logs" ON logs
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- STORAGE POLICIES
-- Users cannot directly access storage objects
CREATE POLICY "Users cannot access storage directly" ON storage.objects
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- Service role can manage all storage objects
CREATE POLICY "Service role can manage audio files" ON storage.objects
  FOR ALL TO service_role USING (bucket_id = 'audio-files') 
  WITH CHECK (bucket_id = 'audio-files');

-- Additional security: Prevent anon access to all tables
-- (RLS is enabled but we want to be explicit)
CREATE POLICY "Anon users denied" ON user_schedule
  FOR ALL TO anon USING (false) WITH CHECK (false);

CREATE POLICY "Anon users denied jobs" ON jobs
  FOR ALL TO anon USING (false) WITH CHECK (false);

CREATE POLICY "Anon users denied content" ON content_blocks
  FOR ALL TO anon USING (false) WITH CHECK (false);

CREATE POLICY "Anon users denied quotes" ON quote_history
  FOR ALL TO anon USING (false) WITH CHECK (false);

CREATE POLICY "Anon users denied logs" ON logs
  FOR ALL TO anon USING (false) WITH CHECK (false);

-- Storage security for anon users
CREATE POLICY "Anon users denied storage" ON storage.objects
  FOR ALL TO anon USING (false) WITH CHECK (false);

-- Additional bucket-level security
-- Make sure audio-files bucket is private and has proper policies
UPDATE storage.buckets 
SET public = false, 
    file_size_limit = 52428800, -- 50MB limit
    allowed_mime_types = ARRAY['audio/aac', 'audio/mp4', 'audio/mpeg']
WHERE id = 'audio-files';

-- Function to securely hash user IDs for logging
CREATE OR REPLACE FUNCTION hash_user_id(user_uuid UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Create consistent hash of user ID for privacy-safe logging
  RETURN encode(digest(user_uuid::text, 'sha256'), 'hex');
END;
$$;

-- Grant usage to service role only
GRANT EXECUTE ON FUNCTION hash_user_id(UUID) TO service_role;
REVOKE EXECUTE ON FUNCTION hash_user_id(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hash_user_id(UUID) FROM anon;