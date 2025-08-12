-- Fix content_cache RLS to allow authenticator role read access
-- This fixes the "relation does not exist" error when get_fresh_content is called via PostgREST
-- Date: 2025-08-12

-- Add read-only policy for authenticator role
-- The authenticator role is used by PostgREST when executing RPC functions
CREATE POLICY "Authenticator can read content cache" ON content_cache
  FOR SELECT 
  TO authenticator 
  USING (true);

-- Note: The existing "Service role full access content" policy remains unchanged
-- This gives service_role full access (SELECT, INSERT, UPDATE, DELETE)
-- while authenticator only gets SELECT access

COMMENT ON POLICY "Authenticator can read content cache" ON content_cache IS 
  'Allows PostgREST (authenticator role) to read cached content when executing RPC functions like get_fresh_content';