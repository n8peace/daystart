-- Add temperature_unit column to jobs table
-- Allows users to specify Celsius or Fahrenheit preference for their briefings
-- Backwards compatible: defaults to 'F' (Fahrenheit) for existing jobs

ALTER TABLE jobs
ADD COLUMN IF NOT EXISTS temperature_unit TEXT DEFAULT 'F' CHECK (temperature_unit IN ('F', 'C'));

-- Add index for potential future analytics
CREATE INDEX IF NOT EXISTS idx_jobs_temperature_unit ON jobs(temperature_unit);

COMMENT ON COLUMN jobs.temperature_unit IS 'Temperature unit preference: F (Fahrenheit) or C (Celsius). Used for script generation to ensure temperatures are spoken in user''s preferred unit.';
