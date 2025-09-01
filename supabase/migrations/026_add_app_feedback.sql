-- Migration: 026_add_app_feedback
-- Adds app_feedback table for in-app user feedback with receipt-based RLS

CREATE TABLE IF NOT EXISTS app_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL DEFAULT (current_setting('request.headers', true)::json->>'x-client-info'),
  category TEXT NOT NULL CHECK (category IN ('audio_issue','content_quality','scheduling','other')),
  message TEXT,
  include_diagnostics BOOLEAN DEFAULT FALSE,
  history_id UUID, -- Local reference only, no foreign key constraint
  app_version TEXT,
  build TEXT,
  device_model TEXT,
  os_version TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS app_feedback_user_created_idx ON app_feedback(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS app_feedback_created_idx ON app_feedback(created_at);

ALTER TABLE app_feedback ENABLE ROW LEVEL SECURITY;

-- Allow inserts for users; user_id enforced by default and check
CREATE POLICY IF NOT EXISTS "Users can insert own feedback" ON app_feedback
  FOR INSERT
  WITH CHECK (user_id = current_setting('request.headers', true)::json->>'x-client-info');

-- Service role full access
CREATE POLICY IF NOT EXISTS "Service role full access feedback" ON app_feedback
  FOR ALL TO service_role USING (true);


