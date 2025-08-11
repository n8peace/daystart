-- Content cache system for fresh news, stocks, and sports data
-- Supports 12-hour content windows with graceful fallback

-- Content cache table
CREATE TABLE content_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL CHECK (content_type IN ('news', 'stocks', 'sports')),
  source TEXT NOT NULL, -- 'newsapi', 'gnews', 'yahoo_finance', 'espn', 'thesportdb'
  data JSONB NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '12 hours'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient content retrieval
CREATE INDEX content_cache_type_date_idx ON content_cache(content_type, created_at DESC);
CREATE INDEX content_cache_expires_idx ON content_cache(expires_at) WHERE expires_at > NOW();
CREATE INDEX content_cache_cleanup_idx ON content_cache(created_at) WHERE expires_at < NOW();

-- RLS policies for content cache
ALTER TABLE content_cache ENABLE ROW LEVEL SECURITY;

-- Service role can manage all content (for workers)
CREATE POLICY "Service role full access content" ON content_cache
  FOR ALL TO service_role USING (true);

-- Function to get fresh content for script generation
CREATE OR REPLACE FUNCTION get_fresh_content(
  requested_types TEXT[] DEFAULT ARRAY['news', 'stocks', 'sports']
)
RETURNS JSONB AS $$
DECLARE
  result JSONB := '{}';
  content_type TEXT;
  fresh_content JSONB;
BEGIN
  -- Get freshest available content for each requested type
  FOREACH content_type IN ARRAY requested_types
  LOOP
    SELECT json_agg(
      json_build_object(
        'source', source,
        'data', data,
        'fetched_at', created_at,
        'age_hours', EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600
      )
    ) INTO fresh_content
    FROM (
      SELECT DISTINCT ON (source) source, data, created_at
      FROM content_cache 
      WHERE content_cache.content_type = get_fresh_content.content_type
        AND expires_at > NOW()
      ORDER BY source, created_at DESC
    ) latest_by_source;
    
    IF fresh_content IS NOT NULL THEN
      result := result || jsonb_build_object(content_type, fresh_content);
    END IF;
  END LOOP;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to cache content with automatic deduplication
CREATE OR REPLACE FUNCTION cache_content(
  p_content_type TEXT,
  p_source TEXT,
  p_data JSONB,
  p_expires_hours INTEGER DEFAULT 12
)
RETURNS UUID AS $$
DECLARE
  cache_id UUID;
BEGIN
  -- Insert new content
  INSERT INTO content_cache (content_type, source, data, expires_at)
  VALUES (
    p_content_type,
    p_source,
    p_data,
    NOW() + (p_expires_hours || ' hours')::INTERVAL
  )
  RETURNING id INTO cache_id;
  
  RETURN cache_id;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup expired content
CREATE OR REPLACE FUNCTION cleanup_expired_content()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM content_cache 
  WHERE expires_at < NOW();
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get content statistics
CREATE OR REPLACE FUNCTION get_content_stats()
RETURNS TABLE(
  content_type TEXT,
  source TEXT,
  count INTEGER,
  latest_fetch TIMESTAMPTZ,
  oldest_fetch TIMESTAMPTZ,
  avg_age_hours NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cc.content_type,
    cc.source,
    COUNT(*)::INTEGER as count,
    MAX(cc.created_at) as latest_fetch,
    MIN(cc.created_at) as oldest_fetch,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - cc.created_at)) / 3600), 2) as avg_age_hours
  FROM content_cache cc
  WHERE cc.expires_at > NOW()
  GROUP BY cc.content_type, cc.source
  ORDER BY cc.content_type, cc.source;
END;
$$ LANGUAGE plpgsql;

-- Updated at trigger for content cache
CREATE TRIGGER update_content_cache_updated_at 
  BEFORE UPDATE ON content_cache
  FOR EACH ROW 
  EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE content_cache IS 
  'Hourly cached content from news, stocks, and sports APIs. 12-hour expiry with graceful fallback.';

COMMENT ON FUNCTION get_fresh_content IS 
  'Returns freshest available content for requested types, supports up to 12-hour old data.';

COMMENT ON FUNCTION cache_content IS 
  'Stores content from external APIs with configurable expiry time.';

COMMENT ON FUNCTION cleanup_expired_content IS 
  'Removes expired content entries, called by maintenance tasks.';