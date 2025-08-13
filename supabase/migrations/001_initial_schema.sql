-- DayStart Initial Database Schema
-- Anonymous-first architecture supporting streaming audio with job queue processing

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Jobs table: Core job queue for DayStart generation
CREATE TABLE jobs (
  job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL, -- Anonymous user identifier from iOS
  local_date DATE NOT NULL, -- User's local date (YYYY-MM-DD)
  scheduled_at TIMESTAMPTZ NOT NULL, -- When DayStart should play
  
  -- Job processing
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'ready', 'failed')),
  priority INTEGER DEFAULT 50, -- 100: Welcome/First, 75: Same-day urgent, 50: Regular, 25: Background
  attempt_count INTEGER DEFAULT 0,
  worker_id UUID, -- Which worker is processing
  lease_until TIMESTAMPTZ, -- FOR UPDATE SKIP LOCKED leasing
  
  -- User preferences (captured at job creation)
  preferred_name TEXT,
  include_weather BOOLEAN DEFAULT TRUE,
  include_news BOOLEAN DEFAULT TRUE,
  include_sports BOOLEAN DEFAULT FALSE,
  include_stocks BOOLEAN DEFAULT FALSE,
  stock_symbols TEXT[] DEFAULT ARRAY[]::TEXT[],
  include_calendar BOOLEAN DEFAULT FALSE,
  include_quotes BOOLEAN DEFAULT TRUE,
  quote_preference TEXT DEFAULT 'motivational',
  voice_option TEXT DEFAULT 'voice1',
  daystart_length INTEGER DEFAULT 180, -- seconds
  timezone TEXT NOT NULL, -- IANA timezone
  
  -- Optional contextual data
  location_data JSONB, -- { "city": "San Francisco", "state": "CA", "country": "US" }
  weather_data JSONB, -- Current weather from WeatherKit
  calendar_events JSONB, -- Upcoming events
  
  -- Results
  script_content TEXT,
  audio_file_path TEXT, -- Path in storage bucket
  audio_duration INTEGER, -- seconds
  transcript TEXT,
  estimated_ready_time TIMESTAMPTZ,
  
  -- Error handling
  error_code TEXT,
  error_message TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  
  -- Ensure one job per user per date
  UNIQUE(user_id, local_date)
);

-- Indexes for performance
CREATE INDEX jobs_status_priority_idx ON jobs(status, priority DESC, created_at ASC) WHERE status IN ('queued', 'processing');
CREATE INDEX jobs_user_date_idx ON jobs(user_id, local_date DESC);
CREATE INDEX jobs_cleanup_idx ON jobs(created_at) WHERE status IN ('ready', 'failed');
CREATE INDEX jobs_lease_idx ON jobs(lease_until) WHERE lease_until IS NOT NULL;

-- DayStart history table (for completed DayStarts)
CREATE TABLE daystart_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  job_id UUID REFERENCES jobs(job_id) ON DELETE SET NULL,
  
  -- DayStart data
  date DATE NOT NULL,
  scheduled_time TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  
  -- Content snapshot
  transcript TEXT NOT NULL,
  audio_duration INTEGER NOT NULL, -- seconds
  audio_file_path TEXT, -- Path in storage
  
  -- Playback tracking
  play_count INTEGER DEFAULT 0,
  last_played_at TIMESTAMPTZ,
  is_deleted BOOLEAN DEFAULT FALSE,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, date)
);

-- Indexes for history
CREATE INDEX daystart_history_user_date_idx ON daystart_history(user_id, date DESC);
CREATE INDEX daystart_history_cleanup_idx ON daystart_history(created_at) WHERE is_deleted = FALSE;

-- Request logs for debugging and rate limiting
CREATE TABLE request_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID DEFAULT gen_random_uuid(),
  user_id TEXT,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  status_code INTEGER,
  response_time_ms INTEGER,
  error_code TEXT,
  user_agent TEXT,
  ip_address INET,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for rate limiting and debugging
CREATE INDEX request_logs_user_endpoint_idx ON request_logs(user_id, endpoint, created_at);
CREATE INDEX request_logs_request_id_idx ON request_logs(request_id);

-- Row Level Security (RLS)
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE daystart_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE request_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Anonymous access based on user_id
CREATE POLICY "Users can access their own jobs" ON jobs
  FOR ALL USING (user_id = current_setting('request.jwt.claims', true)::json->>'user_id');

CREATE POLICY "Users can access their own history" ON daystart_history  
  FOR ALL USING (user_id = current_setting('request.jwt.claims', true)::json->>'user_id');

-- Service role can access everything (for workers)
CREATE POLICY "Service role full access" ON jobs
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access history" ON daystart_history
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access logs" ON request_logs
  FOR ALL TO service_role USING (true);

-- Functions for job processing

-- Function to lease next available job (FOR UPDATE SKIP LOCKED)
CREATE OR REPLACE FUNCTION lease_next_job(worker_id UUID, lease_duration_minutes INTEGER DEFAULT 15)
RETURNS UUID AS $$
DECLARE
  job_id UUID;
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
    ORDER BY j.priority DESC, j.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING jobs.job_id INTO job_id;
  
  RETURN job_id;
END;
$$ LANGUAGE plpgsql;

-- Function to release expired leases
CREATE OR REPLACE FUNCTION release_expired_leases()
RETURNS INTEGER AS $$
DECLARE
  released_count INTEGER;
BEGIN
  UPDATE jobs 
  SET 
    worker_id = NULL,
    lease_until = NULL,
    status = CASE 
      WHEN attempt_count >= 3 THEN 'failed'
      ELSE 'queued'
    END,
    updated_at = NOW()
  WHERE lease_until < NOW() 
    AND status = 'processing';
  
  GET DIAGNOSTICS released_count = ROW_COUNT;
  RETURN released_count;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup old jobs and history
CREATE OR REPLACE FUNCTION cleanup_old_data(days_to_keep INTEGER DEFAULT 30)
RETURNS TABLE(jobs_deleted INTEGER, history_deleted INTEGER) AS $$
DECLARE
  cutoff_date TIMESTAMPTZ := NOW() - (days_to_keep || ' days')::INTERVAL;
  jobs_count INTEGER;
  history_count INTEGER;
BEGIN
  -- Delete old completed/failed jobs
  DELETE FROM jobs 
  WHERE created_at < cutoff_date 
    AND status IN ('ready', 'failed');
  GET DIAGNOSTICS jobs_count = ROW_COUNT;
  
  -- Mark old history as deleted (keep for analytics)
  UPDATE daystart_history 
  SET is_deleted = TRUE 
  WHERE created_at < cutoff_date 
    AND is_deleted = FALSE;
  GET DIAGNOSTICS history_count = ROW_COUNT;
  
  RETURN QUERY SELECT jobs_count, history_count;
END;
$$ LANGUAGE plpgsql;

-- Updated at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_jobs_updated_at BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Initial data and configuration

-- Sample job priorities for reference
COMMENT ON COLUMN jobs.priority IS 
  '100: Welcome/First DayStart, 75: Same-day urgent, 50: Regular, 25: Background processing';

COMMENT ON COLUMN jobs.status IS 
  'queued: Waiting to be processed, processing: Worker is generating content, ready: Audio available, failed: Error occurred';

COMMENT ON TABLE jobs IS 
  'Core job queue for DayStart audio generation. Anonymous users identified by user_id string.';

COMMENT ON TABLE daystart_history IS 
  'Completed DayStart sessions for replay and analytics. Links to original job for content.';

-- Storage bucket policies will be configured separately
COMMENT ON COLUMN jobs.audio_file_path IS 
  'Path in Supabase storage bucket (private). Access via signed URLs only.';