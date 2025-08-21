-- Fix RLS policies for receipt-based authentication
-- This migration corrects the auth model to use x-client-info (receipt IDs) instead of JWT auth

-- Drop the UUID-based RLS policies that won't work with receipt auth
DROP POLICY IF EXISTS "Users can access their own jobs" ON jobs;
DROP POLICY IF EXISTS "Users can access their own logs" ON request_logs;

-- Create receipt-based RLS policies
-- These use the x-client-info header value passed through service role functions
CREATE POLICY "Users can access their own jobs" ON jobs
  FOR ALL USING (user_id = current_setting('request.headers', true)::json->>'x-client-info');

CREATE POLICY "Users can access their own logs" ON request_logs
  FOR ALL USING (user_id = current_setting('request.headers', true)::json->>'x-client-info');

-- Update column comments to reflect receipt-based auth
COMMENT ON COLUMN jobs.user_id IS 'Receipt ID from iOS purchase - identifies users by StoreKit transaction receipt';
COMMENT ON COLUMN request_logs.user_id IS 'Receipt ID from iOS purchase - identifies users by StoreKit transaction receipt';

-- Grant necessary permissions for service role to set request.headers
-- This is needed for the RLS policies to work with service role functions
GRANT USAGE ON SCHEMA public TO service_role;

-- Note: Service role policies remain unchanged and provide full access for backend processing
-- The Edge Functions use service role and manually filter by user_id from x-client-info header