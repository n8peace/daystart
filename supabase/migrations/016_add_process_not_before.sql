-- Add process_not_before to gate processing until pre-window
BEGIN;

-- 1) Add column
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS process_not_before TIMESTAMPTZ;

-- 2) Backfill existing rows to scheduled_at - 2 hours when null
UPDATE jobs
SET process_not_before = COALESCE(process_not_before, scheduled_at - INTERVAL '2 hours')
WHERE process_not_before IS NULL;

-- 3) Create helpful index for leasing eligibility
CREATE INDEX IF NOT EXISTS jobs_eligibility_idx
  ON jobs(status, process_not_before, priority DESC)
  WHERE status = 'queued';

-- 4) Update leasing function to respect process_not_before
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
    WHERE j.status = 'queued' 
      AND (j.lease_until IS NULL OR j.lease_until < NOW())
      AND j.attempt_count < 3
      AND NOW() >= COALESCE(j.process_not_before, j.scheduled_at - INTERVAL '2 hours')
    ORDER BY j.priority DESC, j.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING jobs.job_id INTO v_job_id;
  
  RETURN v_job_id;
END;
$$ LANGUAGE plpgsql;

COMMIT;


