-- Initial schema for DayStart backend
-- Created: 2024-01-01

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- User schedule table
CREATE TABLE user_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  repeat_days INTEGER[] NOT NULL, -- Array of weekday numbers [1-7]
  wake_time_local TIME NOT NULL,
  timezone TEXT NOT NULL, -- IANA timezone (e.g., 'America/New_York')
  last_scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Main job queue table
CREATE TABLE jobs (
  job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  local_date DATE NOT NULL, -- User's local date
  scheduled_at TIMESTAMPTZ NOT NULL, -- When DayStart should play
  window_start TIMESTAMPTZ NOT NULL, -- When job can start processing (2hrs before)
  window_end TIMESTAMPTZ NOT NULL, -- Latest acceptable completion time
  
  -- Job processing
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'script_processing', 'script_ready', 'audio_processing', 'ready', 'failed', 'failed_missed')),
  attempt_count INTEGER DEFAULT 0,
  worker_id UUID, -- Which worker is processing
  lease_until TIMESTAMPTZ, -- FOR UPDATE SKIP LOCKED leasing
  
  -- User preferences (captured at job creation)
  preferred_name TEXT,
  location_data JSONB, -- { "city": "San Francisco", "state": "CA", "country": "US", "zip": "94102" }
  weather_data JSONB, -- Current and forecast from WeatherKit
  encouragement_preference TEXT,
  stock_symbols TEXT[],
  include_news BOOLEAN DEFAULT true,
  include_sports BOOLEAN DEFAULT true,
  desired_voice TEXT NOT NULL,
  desired_length INTEGER NOT NULL, -- minutes
  
  -- Generated content
  script TEXT,
  script_ready_at TIMESTAMPTZ,
  audio_path TEXT, -- Path in Supabase Storage
  audio_ready_at TIMESTAMPTZ,
  
  -- Tracking
  downloaded_at TIMESTAMPTZ, -- When app confirmed successful download
  failure_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, local_date) -- One job per user per local day
);

-- Content blocks for shared news/sports/stocks
CREATE TABLE content_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL CHECK (content_type IN ('news', 'sports', 'stocks')),
  region TEXT, -- For news/sports: 'US-CA-SF', 'US-NY', 'US', 'INTL'
  league TEXT, -- For sports: 'NFL', 'NBA', 'MLB', etc.
  
  -- Raw content from APIs
  raw_payload JSONB NOT NULL,
  
  -- Processed for GPT-4o
  processed_content JSONB, -- Summarized/formatted for script generation
  
  importance_score INTEGER DEFAULT 5, -- 1-10, for breaking news priority
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '12 hours')
);

-- Quote deduplication tracking
CREATE TABLE quote_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  quote_hash TEXT NOT NULL, -- SHA256 of quote content
  quote_content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Comprehensive logging
CREATE TABLE logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES jobs(job_id) ON DELETE CASCADE,
  event TEXT NOT NULL, -- 'job_created', 'script_started', 'api_call', 'error', etc.
  level TEXT NOT NULL DEFAULT 'info' CHECK (level IN ('debug', 'info', 'warn', 'error')),
  
  -- Structured metadata
  meta JSONB, -- { "function": "worker_generate_script", "api": "openai", "latency_ms": 1500, "user_id_hash": "abc123" }
  
  message TEXT,
  error_details JSONB, -- Stack trace, error codes, etc.
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Performance indexes
CREATE INDEX jobs_worker_queue_idx ON jobs(status, scheduled_at) WHERE status IN ('queued', 'script_ready');
CREATE INDEX jobs_user_date_idx ON jobs(user_id, local_date);
CREATE INDEX jobs_cleanup_idx ON jobs(audio_ready_at) WHERE audio_path IS NOT NULL;

CREATE INDEX content_blocks_lookup_idx ON content_blocks(content_type, region, created_at DESC);
CREATE INDEX content_blocks_sports_idx ON content_blocks(content_type, league, created_at DESC) WHERE content_type = 'sports';
CREATE INDEX content_blocks_cleanup_idx ON content_blocks(expires_at);

CREATE INDEX quote_history_user_recent_idx ON quote_history(user_id, created_at DESC);

CREATE INDEX logs_job_idx ON logs(job_id, created_at DESC);
CREATE INDEX logs_level_time_idx ON logs(level, created_at DESC) WHERE level IN ('warn', 'error');
CREATE INDEX logs_event_idx ON logs(event, created_at DESC);

-- Enable Row Level Security
ALTER TABLE user_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user access
CREATE POLICY "Users can manage their own schedule" ON user_schedule
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own jobs" ON jobs
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view their quote history" ON quote_history
  FOR ALL USING (auth.uid() = user_id);

-- Service role policies (for workers)
CREATE POLICY "Service role full access jobs" ON jobs
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access content" ON content_blocks
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access logs" ON logs
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access quotes" ON quote_history
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access schedule" ON user_schedule
  FOR ALL TO service_role USING (true);

-- Create storage bucket for audio files
INSERT INTO storage.buckets (id, name, public) 
VALUES ('audio-files', 'audio-files', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
CREATE POLICY "Service role can manage audio files" ON storage.objects
  FOR ALL TO service_role USING (bucket_id = 'audio-files');