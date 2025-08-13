-- Fix get_fresh_content function SQL syntax error
-- The function was referencing 'get_fresh_content.content_type' which doesn't exist
-- This migration fixes the ambiguous column reference by using a different loop variable name
-- Date: 2025-08-12

-- Drop and recreate the function with fixed SQL
CREATE OR REPLACE FUNCTION get_fresh_content(
  requested_types TEXT[] DEFAULT ARRAY['news', 'stocks', 'sports']
)
RETURNS JSONB AS $$
DECLARE
  result JSONB := '{}';
  req_type TEXT;  -- Changed from 'content_type' to avoid ambiguity
  fresh_content JSONB;
BEGIN
  -- Get freshest available content for each requested type
  FOREACH req_type IN ARRAY requested_types
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
      WHERE content_cache.content_type = req_type  -- Fixed: was 'get_fresh_content.content_type'
        AND expires_at > NOW()
      ORDER BY source, created_at DESC
    ) latest_by_source;
    
    IF fresh_content IS NOT NULL THEN
      result := result || jsonb_build_object(req_type, fresh_content);
    END IF;
  END LOOP;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Re-add the comment for documentation
COMMENT ON FUNCTION get_fresh_content IS 
  'Returns freshest available content for requested types, supports up to 12-hour old data. Fixed in migration 008 to resolve SQL syntax error.';