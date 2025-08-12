-- Remove system_config_log table
-- This table was created in migration 005 but is not needed for the application
-- Date: 2025-08-12

-- Drop the system_config_log table if it exists
DROP TABLE IF EXISTS system_config_log;

-- Note: This removes the audit log table that was tracking configuration changes.
-- The cron schedule change is still documented in migration 005 comments.