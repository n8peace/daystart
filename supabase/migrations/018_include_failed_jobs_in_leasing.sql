-- Update lease_next_job function to include failed jobs that haven't reached max attempts
BEGIN;

CREATE OR REPLACE FUNCTION lease_next_job(worker_id UUID, lease_duration_minutes INTEGER DEFAULT 15)
RETURNS UUID AS $$
DECLARE
  v_job_id UUID;
BEGIN
  UPDATE jobs 
  SET 
    worker_id = lease_next_job.worker_id,
    lease_until = NOW() + (lease_duration_minutes || ' minutes')::INTERVAL,
    status = 'processing',
    attempt_count = attempt_count + 1,
    updated_at = NOW()
  WHERE job_id = (
    SELECT j.job_id 
    FROM jobs j
    WHERE (j.status = 'queued' OR (j.status = 'failed' AND j.attempt_count < 3))
      AND (j.lease_until IS NULL OR j.lease_until < NOW())
      AND j.attempt_count < 3
      AND NOW() >= COALESCE(j.process_not_before, j.scheduled_at - INTERVAL '45 minutes')
    ORDER BY j.priority DESC, j.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING jobs.job_id INTO v_job_id;
  
  RETURN v_job_id;
END;
$$ LANGUAGE plpgsql;

COMMIT;