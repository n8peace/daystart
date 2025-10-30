-- Add content fetch logging to track API failures and cache fallbacks
-- This enables visibility into content freshness and API reliability
-- Date: 2025-01-20

-- Create table to log all content fetch attempts
CREATE TABLE content_fetch_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL,
  content_type TEXT NOT NULL CHECK (content_type IN ('news', 'sports', 'stocks')),
  fetch_status TEXT NOT NULL CHECK (fetch_status IN ('success', 'failed_used_cache', 'failed_no_cache')),
  error_message TEXT,
  cached_data_age_hours NUMERIC,
  items_fetched INTEGER,
  api_response_time_ms INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient healthcheck queries
CREATE INDEX idx_content_fetch_log_recent ON content_fetch_log(created_at DESC);
CREATE INDEX idx_content_fetch_log_source ON content_fetch_log(source, created_at DESC);
CREATE INDEX idx_content_fetch_log_status ON content_fetch_log(fetch_status, created_at DESC);

-- Grant appropriate permissions
GRANT INSERT ON content_fetch_log TO service_role;
GRANT SELECT ON content_fetch_log TO service_role;

-- Add comment for documentation
COMMENT ON TABLE content_fetch_log IS 
  'Tracks all content fetch attempts from external APIs. Used to monitor API reliability, cache fallback usage, and content freshness for healthcheck reporting.';

COMMENT ON COLUMN content_fetch_log.fetch_status IS 
  'success: Fresh content fetched, failed_used_cache: API failed but had cached backup, failed_no_cache: API failed with no cache available';

COMMENT ON COLUMN content_fetch_log.cached_data_age_hours IS 
  'When using cached fallback, how old was the cached data in hours';

-- Create function to get content freshness summary for healthcheck
CREATE OR REPLACE FUNCTION get_content_freshness_summary()
RETURNS TABLE(
  source TEXT,
  content_type TEXT,
  last_success TIMESTAMPTZ,
  hours_since_success NUMERIC,
  fallback_count_24h INTEGER,
  failure_count_24h INTEGER,
  max_cache_age_used NUMERIC,
  current_cache_age NUMERIC,
  status TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH recent_fetches AS (
    SELECT 
      fl.source,
      fl.content_type,
      MAX(CASE WHEN fl.fetch_status = 'success' THEN fl.created_at END) as last_success_time,
      COUNT(*) FILTER (WHERE fl.fetch_status = 'failed_used_cache' AND fl.created_at > NOW() - INTERVAL '24 hours') as fallback_count,
      COUNT(*) FILTER (WHERE fl.fetch_status = 'failed_no_cache' AND fl.created_at > NOW() - INTERVAL '24 hours') as failure_count,
      MAX(CASE WHEN fl.fetch_status = 'failed_used_cache' THEN fl.cached_data_age_hours END) as max_cache_age
    FROM content_fetch_log fl
    WHERE fl.created_at > NOW() - INTERVAL '48 hours'
    GROUP BY fl.source, fl.content_type
  ),
  current_cache AS (
    SELECT 
      cc.source,
      cc.content_type,
      EXTRACT(EPOCH FROM (NOW() - cc.created_at)) / 3600 as cache_age_hours
    FROM content_cache cc
    WHERE cc.expires_at > NOW()
  )
  SELECT 
    rf.source,
    rf.content_type,
    rf.last_success_time,
    ROUND(EXTRACT(EPOCH FROM (NOW() - rf.last_success_time)) / 3600, 2) as hours_since_success,
    COALESCE(rf.fallback_count, 0) as fallback_count_24h,
    COALESCE(rf.failure_count, 0) as failure_count_24h,
    rf.max_cache_age,
    ROUND(cc.cache_age_hours, 2) as current_cache_age,
    CASE 
      WHEN rf.last_success_time > NOW() - INTERVAL '1 hour' THEN 'fresh'
      WHEN rf.last_success_time > NOW() - INTERVAL '6 hours' THEN 'recent'
      WHEN rf.last_success_time > NOW() - INTERVAL '24 hours' THEN 'stale'
      WHEN rf.last_success_time IS NULL AND cc.cache_age_hours IS NOT NULL THEN 'cache_only'
      ELSE 'critical'
    END as status
  FROM recent_fetches rf
  LEFT JOIN current_cache cc ON rf.source = cc.source AND rf.content_type = cc.content_type
  ORDER BY 
    CASE status 
      WHEN 'critical' THEN 1
      WHEN 'cache_only' THEN 2
      WHEN 'stale' THEN 3
      WHEN 'recent' THEN 4
      WHEN 'fresh' THEN 5
    END,
    rf.source;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_content_freshness_summary() TO service_role;