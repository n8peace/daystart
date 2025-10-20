-- Migration: 032_add_share_functionality.sql
-- Add share functionality for public DayStart links
-- This is a completely new feature that doesn't modify existing tables

CREATE TABLE public_daystart_shares (
  share_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES jobs(job_id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  share_token TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  view_count INTEGER DEFAULT 0,
  last_accessed_at TIMESTAMPTZ,
  
  -- Analytics fields
  share_source TEXT, -- 'completion_screen', 'audio_player', 'manual'
  share_metadata JSONB DEFAULT '{}'::jsonb,
  clicked_cta BOOLEAN DEFAULT FALSE,
  converted_to_user BOOLEAN DEFAULT FALSE,
  
  -- Rate limiting
  shares_per_job INTEGER DEFAULT 1 -- Track multiple shares of same job
);

-- Indexes for performance
CREATE UNIQUE INDEX shares_token_idx ON public_daystart_shares(share_token);
CREATE INDEX shares_expiry_idx ON public_daystart_shares(expires_at);
CREATE INDEX shares_user_idx ON public_daystart_shares(user_id);
CREATE INDEX shares_job_idx ON public_daystart_shares(job_id);

-- Enable RLS
ALTER TABLE public_daystart_shares ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Public read for valid shares (anonymous access)
CREATE POLICY "Public read for valid shares" ON public_daystart_shares
  FOR SELECT TO anon, authenticated
  USING (expires_at > NOW());

-- Users can see their own shares
CREATE POLICY "Users can view own shares" ON public_daystart_shares
  FOR SELECT TO anon, authenticated
  USING (user_id = current_setting('request.headers', true)::json->>'x-client-info');

-- Service role full access
CREATE POLICY "Service role full access shares" ON public_daystart_shares
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- Add helpful comments
COMMENT ON TABLE public_daystart_shares IS 'Stores shareable links for DayStart audio briefings with expiration and analytics';
COMMENT ON COLUMN public_daystart_shares.share_token IS 'URL-safe unique token used in share URLs';
COMMENT ON COLUMN public_daystart_shares.expires_at IS 'When the share link expires (typically 48 hours)';
COMMENT ON COLUMN public_daystart_shares.share_source IS 'Where the share was initiated from in the app';
COMMENT ON COLUMN public_daystart_shares.shares_per_job IS 'Number of shares created for this job (rate limiting)';