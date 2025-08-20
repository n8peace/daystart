-- Migration: Add support for direct job processing
-- Description: Allow process-jobs Edge Function to process a specific job immediately
-- This enables instant processing of welcome DayStart jobs after onboarding

BEGIN;

-- Create function to lease a specific job by ID
CREATE OR REPLACE FUNCTION lease_specific_job(
  job_id UUID, 
  worker_id UUID, 
  lease_duration_minutes INTEGER DEFAULT 15
)
RETURNS UUID AS $$
DECLARE
  leased_job_id UUID;
BEGIN
  UPDATE jobs 
  SET 
    worker_id = lease_specific_job.worker_id,
    lease_until = NOW() + (lease_duration_minutes || ' minutes')::INTERVAL,
    status = 'processing',
    attempt_count = attempt_count + 1,
    updated_at = NOW()
  WHERE jobs.job_id = lease_specific_job.job_id
    AND (jobs.status = 'queued' OR (jobs.status = 'failed' AND jobs.attempt_count < 3))
    AND (jobs.lease_until IS NULL OR jobs.lease_until < NOW())
    AND jobs.attempt_count < 3
    AND (jobs.process_not_before IS NULL OR jobs.process_not_before <= NOW())
  RETURNING jobs.job_id INTO leased_job_id;
  
  RETURN leased_job_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION lease_specific_job IS 'Lease a specific job by ID for processing. Returns the job ID if successfully leased, NULL otherwise.';

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION lease_specific_job TO service_role;

COMMIT;