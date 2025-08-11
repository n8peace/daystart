-- Fix SQL ambiguity in lease_next_job function
-- This resolves "column reference job_id is ambiguous" error

CREATE OR REPLACE FUNCTION lease_next_job(worker_id UUID, lease_duration_minutes INTEGER DEFAULT 15)
RETURNS UUID AS $$
DECLARE
  leased_job_id UUID;
BEGIN
  UPDATE jobs 
  SET 
    worker_id = lease_next_job.worker_id,
    lease_until = NOW() + (lease_duration_minutes || ' minutes')::INTERVAL,
    status = 'processing',
    attempt_count = attempt_count + 1,
    updated_at = NOW()
  WHERE jobs.job_id = (
    SELECT j.job_id 
    FROM jobs j
    WHERE j.status = 'queued' 
      AND (j.lease_until IS NULL OR j.lease_until < NOW())
      AND j.attempt_count < 3
    ORDER BY j.priority DESC, j.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING jobs.job_id INTO leased_job_id;
  
  RETURN leased_job_id;
END;
$$ LANGUAGE plpgsql;

-- Test the function works after migration
-- This comment documents that the function should now work without ambiguity errors
COMMENT ON FUNCTION lease_next_job IS 'Fixed column ambiguity - explicitly references jobs.job_id in WHERE and RETURNING clauses';