-- Migration 027: Document priority 100 for welcome/onboarding jobs
-- This migration adds documentation for the priority field convention
-- No schema changes, only comments for clarity

-- Update the comment on the priority column to document that 100 is reserved for welcome jobs
COMMENT ON COLUMN public.jobs.priority IS 'Job priority: 100=Welcome/Onboarding (never cancelled by schedule), 75=Same-day urgent, 50=Regular, 25=Background';

-- Add a check constraint to ensure priority is within valid range (optional but good practice)
ALTER TABLE public.jobs 
DROP CONSTRAINT IF EXISTS jobs_priority_check;

ALTER TABLE public.jobs 
ADD CONSTRAINT jobs_priority_check 
CHECK (priority >= 0 AND priority <= 100);

-- Create an index on priority to optimize queries that filter by priority
-- This will help with the new logic that excludes priority 100 jobs from schedule cancellation
CREATE INDEX IF NOT EXISTS idx_jobs_priority ON public.jobs(priority);

-- Create a partial index for welcome jobs for quick lookup
CREATE INDEX IF NOT EXISTS idx_jobs_welcome ON public.jobs(user_id, local_date) 
WHERE priority = 100;

-- Document the new behavior in a comment on the jobs table
COMMENT ON TABLE public.jobs IS 'Job queue for DayStart generation. Priority 100 jobs are welcome/onboarding jobs that bypass schedule validation.';