-- Migration: 022_receipt_based_auth.sql
-- Description: Update system to use StoreKit receipt IDs as user identifiers instead of JWT auth
-- Date: 2024-01-08

-- Note: This migration primarily affects Edge Functions, not database schema
-- The actual changes need to be made in your Supabase Edge Functions code

-- 1. Optional: Create a table to track purchase users if you want to maintain referential integrity
CREATE TABLE IF NOT EXISTS purchase_users (
    receipt_id TEXT PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_test BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- 2. Add index for performance
CREATE INDEX IF NOT EXISTS idx_purchase_users_created_at ON purchase_users(created_at);
CREATE INDEX IF NOT EXISTS idx_purchase_users_is_test ON purchase_users(is_test);

-- 3. Enable RLS
ALTER TABLE purchase_users ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS policies (users can only see their own data)
CREATE POLICY "Users can view own purchase record" ON purchase_users
    FOR SELECT USING (receipt_id = current_setting('request.headers', true)::json->>'x-client-info');

CREATE POLICY "Users can update own last_seen" ON purchase_users
    FOR UPDATE USING (receipt_id = current_setting('request.headers', true)::json->>'x-client-info');

-- 5. Optional: Remove foreign key constraints on jobs table if they reference auth.users
-- Uncomment if you have such constraints:
-- ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_user_id_fkey;

-- 6. Optional: Add a migration helper function to track receipt IDs
CREATE OR REPLACE FUNCTION track_purchase_user(p_receipt_id TEXT, p_is_test BOOLEAN DEFAULT FALSE)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO purchase_users (receipt_id, is_test, last_seen)
    VALUES (p_receipt_id, p_is_test, NOW())
    ON CONFLICT (receipt_id) 
    DO UPDATE SET last_seen = NOW();
END;
$$;

-- 7. Grant execute permission to authenticated and anon roles
GRANT EXECUTE ON FUNCTION track_purchase_user TO anon, authenticated;

-- 8. Comment for documentation
COMMENT ON TABLE purchase_users IS 'Tracks StoreKit receipt IDs used as user identifiers in the purchase-based auth system';
COMMENT ON FUNCTION track_purchase_user IS 'Helper function to track receipt ID usage, called by Edge Functions';

-- Migration Notes:
-- After applying this migration, update all Edge Functions to:
-- 1. Extract user ID from x-client-info header instead of JWT
-- 2. Check x-auth-type header for 'purchase' or 'anonymous'
-- 3. Accept test receipts starting with 'tx_' in development
-- 4. Call track_purchase_user() when processing requests to maintain user tracking