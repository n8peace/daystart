-- Add support for AI-curated content in the content cache system
-- This migration adds the new 'top_ten_ai_curated' source type
-- Date: 2025-01-15

-- Update the content_cache table source column comment to include new source
COMMENT ON COLUMN content_cache.source IS 
  'Content source identifier: newsapi_general, newsapi_business, newsapi_targeted, gnews_comprehensive, top_ten_ai_curated, yahoo_finance, espn, thesportdb';

-- Create function to get top 10 AI-curated stories specifically
CREATE OR REPLACE FUNCTION get_top_ten_stories()
RETURNS JSONB AS $$
DECLARE
  top_ten_content JSONB;
BEGIN
  -- Get the most recent top 10 AI-curated content
  SELECT data INTO top_ten_content
  FROM content_cache 
  WHERE content_type = 'news' 
    AND source = 'top_ten_ai_curated'
    AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;
  
  -- Return the stories array if available, otherwise empty array
  IF top_ten_content IS NOT NULL THEN
    RETURN COALESCE(top_ten_content->'stories', '[]'::jsonb);
  ELSE
    RETURN '[]'::jsonb;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Create function to get content statistics including AI processing metrics
CREATE OR REPLACE FUNCTION get_enhanced_content_stats()
RETURNS TABLE(
  content_type TEXT,
  source TEXT,
  count INTEGER,
  latest_fetch TIMESTAMPTZ,
  oldest_fetch TIMESTAMPTZ,
  avg_age_hours NUMERIC,
  has_ai_processing BOOLEAN,
  ai_articles_processed INTEGER,
  ai_quality_score NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cc.content_type,
    cc.source,
    COUNT(*)::INTEGER as count,
    MAX(cc.created_at) as latest_fetch,
    MIN(cc.created_at) as oldest_fetch,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - cc.created_at)) / 3600), 2) as avg_age_hours,
    CASE 
      WHEN cc.source = 'top_ten_ai_curated' THEN true
      WHEN cc.data->'generation_metadata' IS NOT NULL THEN true
      ELSE false
    END as has_ai_processing,
    COALESCE((cc.data->'generation_metadata'->>'articles_processed')::INTEGER, 0) as ai_articles_processed,
    CASE 
      WHEN cc.source = 'top_ten_ai_curated' THEN 10.0  -- Top 10 is highest quality
      WHEN cc.data->'compact'->'news' IS NOT NULL THEN 8.0  -- Has AI summaries
      ELSE 6.0  -- Basic content
    END as ai_quality_score
  FROM content_cache cc
  WHERE cc.expires_at > NOW()
  GROUP BY cc.content_type, cc.source, cc.data
  ORDER BY cc.content_type, ai_quality_score DESC, cc.source;
END;
$$ LANGUAGE plpgsql;

-- Update the get_fresh_content function to prioritize AI-curated content
CREATE OR REPLACE FUNCTION get_fresh_content_enhanced(
  requested_types TEXT[] DEFAULT ARRAY['news', 'stocks', 'sports'],
  prefer_ai_curated BOOLEAN DEFAULT true
)
RETURNS JSONB AS $$
DECLARE
  result JSONB := '{}';
  req_type TEXT;
  fresh_content JSONB;
  ai_curated_content JSONB;
BEGIN
  -- Get freshest available content for each requested type
  FOREACH req_type IN ARRAY requested_types
  LOOP
    -- For news, check if we should prioritize AI-curated content
    IF req_type = 'news' AND prefer_ai_curated THEN
      -- First try to get AI-curated top 10 stories
      SELECT json_build_object(
        'source', 'top_ten_ai_curated',
        'data', data,
        'fetched_at', created_at,
        'age_hours', EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600,
        'ai_enhanced', true
      ) INTO ai_curated_content
      FROM content_cache 
      WHERE content_type = 'news' 
        AND source = 'top_ten_ai_curated'
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1;
      
      IF ai_curated_content IS NOT NULL THEN
        -- Use AI-curated content as the primary news source
        result := result || jsonb_build_object(req_type, json_build_array(ai_curated_content));
        CONTINUE;
      END IF;
    END IF;
    
    -- Fallback to regular content fetching
    SELECT json_agg(
      json_build_object(
        'source', source,
        'data', data,
        'fetched_at', created_at,
        'age_hours', EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600,
        'ai_enhanced', CASE WHEN data->'generation_metadata' IS NOT NULL THEN true ELSE false END
      )
    ) INTO fresh_content
    FROM (
      SELECT DISTINCT ON (source) source, data, created_at
      FROM content_cache 
      WHERE content_cache.content_type = req_type
        AND expires_at > NOW()
        AND source != 'top_ten_ai_curated'  -- Exclude AI-curated from regular results
      ORDER BY source, created_at DESC
    ) latest_by_source;
    
    IF fresh_content IS NOT NULL THEN
      result := result || jsonb_build_object(req_type, fresh_content);
    END IF;
  END LOOP;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Add comments for documentation
COMMENT ON FUNCTION get_top_ten_stories IS 
  'Returns the most recent AI-curated top 10 news stories. Used for high-quality content delivery.';

COMMENT ON FUNCTION get_enhanced_content_stats IS 
  'Returns content statistics including AI processing metrics and quality scores.';

COMMENT ON FUNCTION get_fresh_content_enhanced IS 
  'Enhanced version of get_fresh_content that prioritizes AI-curated content when available.';

-- Create index for efficient AI-curated content retrieval
CREATE INDEX IF NOT EXISTS content_cache_ai_curated_idx ON content_cache(content_type, source, created_at DESC) 
  WHERE source = 'top_ten_ai_curated';

-- Create index for content with AI metadata
CREATE INDEX IF NOT EXISTS content_cache_ai_metadata_idx ON content_cache(content_type, created_at DESC) 
  WHERE (data->'generation_metadata') IS NOT NULL;
