-- Migration 024: Add 'cancelled' status for jobs
-- This allows jobs to be cancelled due to schedule changes and later reactivated

-- Drop the existing CHECK constraint on status
ALTER TABLE jobs 
DROP CONSTRAINT IF EXISTS jobs_status_check;

-- Add new CHECK constraint that includes 'cancelled' status
ALTER TABLE jobs 
ADD CONSTRAINT jobs_status_check 
CHECK (status IN ('queued', 'processing', 'ready', 'failed', 'cancelled'));

-- Add comment for documentation
COMMENT ON CONSTRAINT jobs_status_check ON jobs IS 'Job status: queued=pending, processing=active, ready=completed, failed=error, cancelled=user-cancelled';

-- Create index on status and error_code for efficient cancelled job lookups
CREATE INDEX IF NOT EXISTS idx_jobs_status_error_code ON jobs(status, error_code) 
WHERE status = 'cancelled';

-- Add comment explaining the migration
COMMENT ON TABLE jobs IS 'Job processing queue with support for user cancellation and reactivation';