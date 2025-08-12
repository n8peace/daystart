-- Update process_jobs cron schedule from every 5 minutes to every 1 minute
-- This reduces the maximum wait time for welcome DayStarts from 5 minutes to 1 minute
--
-- IMPORTANT: This migration documents the schedule change requirement.
-- The actual cron job runs on an external service (e.g., cron-job.org) and must be updated manually.
--
-- Previous schedule: */5 * * * * (every 5 minutes)
-- New schedule: */1 * * * * (every 1 minute)
--
-- To apply this change:
-- 1. Log into your external cron service (cron-job.org or similar)
-- 2. Find the job that calls: https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_jobs
-- 3. Update the schedule from "*/5 * * * *" to "*/1 * * * *"
-- 4. Save the changes
--
-- Note: Running the job every minute will increase the number of invocations by 5x.
-- Monitor your Supabase Edge Function usage to ensure you stay within your plan limits.

-- Create a migration record to track this configuration change
CREATE TABLE IF NOT EXISTS system_config_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  config_key TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  change_description TEXT,
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  applied_by TEXT DEFAULT current_user
);

-- Log the cron schedule change
INSERT INTO system_config_log (config_key, old_value, new_value, change_description)
VALUES (
  'process_jobs_cron_schedule',
  '*/5 * * * *',
  '*/1 * * * *',
  'Updated process_jobs cron schedule to run every 1 minute instead of every 5 minutes to reduce maximum wait time for welcome DayStarts'
);

-- Add a comment to the jobs table documenting the expected processing frequency
COMMENT ON TABLE jobs IS 
  'Core job queue for DayStart audio generation. Anonymous users identified by user_id string. Jobs are processed every 1 minute by the process_jobs edge function triggered via external cron service.';