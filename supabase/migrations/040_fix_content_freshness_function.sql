-- Fix get_content_freshness_summary function to handle NULL values properly
-- This resolves "structure of query does not match function result type" error
-- Date: 2025-10-30

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
  ),
  summary AS (
    SELECT 
      rf.source,
      rf.content_type,
      rf.last_success_time,
      CASE 
        WHEN rf.last_success_time IS NOT NULL THEN 
          ROUND(EXTRACT(EPOCH FROM (NOW() - rf.last_success_time)) / 3600, 2)
        ELSE NULL
      END as hours_since_success,
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
  )
  SELECT 
    s.source,
    s.content_type,
    s.last_success_time,
    s.hours_since_success,
    s.fallback_count_24h,
    s.failure_count_24h,
    s.max_cache_age,
    s.current_cache_age,
    s.status
  FROM summary s
  ORDER BY 
    CASE s.status 
      WHEN 'critical' THEN 1
      WHEN 'cache_only' THEN 2
      WHEN 'stale' THEN 3
      WHEN 'recent' THEN 4
      WHEN 'fresh' THEN 5
    END,
    s.source;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_content_freshness_summary() TO service_role;