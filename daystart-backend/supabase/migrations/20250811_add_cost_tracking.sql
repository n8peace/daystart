-- Add cost tracking columns to jobs table
ALTER TABLE jobs
ADD COLUMN script_cost DECIMAL(10, 5) DEFAULT 0.00000,
ADD COLUMN tts_cost DECIMAL(10, 5) DEFAULT 0.00000,
ADD COLUMN total_cost DECIMAL(10, 5) DEFAULT 0.00000;

-- Add indexes for cost analysis queries
CREATE INDEX idx_jobs_total_cost ON jobs(total_cost);
CREATE INDEX idx_jobs_created_at_total_cost ON jobs(created_at, total_cost);

-- Add comment explaining the columns
COMMENT ON COLUMN jobs.script_cost IS 'Cost in USD for OpenAI script generation (GPT-4o-mini)';
COMMENT ON COLUMN jobs.tts_cost IS 'Cost in USD for ElevenLabs text-to-speech generation';
COMMENT ON COLUMN jobs.total_cost IS 'Total cost in USD (script_cost + tts_cost)';