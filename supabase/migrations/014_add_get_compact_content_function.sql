-- Aggregate compact content across sources for easy retrieval
CREATE OR REPLACE FUNCTION get_compact_content(
  requested_types TEXT[] DEFAULT ARRAY['news','stocks','sports']
)
RETURNS JSONB AS $$
DECLARE
  result JSONB := '{}';
  req_type TEXT;
  aggregated JSONB;
BEGIN
  FOREACH req_type IN ARRAY requested_types LOOP
    IF req_type = 'news' THEN
      SELECT json_agg(item) INTO aggregated
      FROM (
        SELECT (json_array_elements(data->'compact'->'news')) AS item
        FROM content_cache
        WHERE content_type = 'news' AND expires_at > NOW()
        ORDER BY created_at DESC
        LIMIT 200
      ) s;
      IF aggregated IS NOT NULL THEN
        result := result || jsonb_build_object('news', aggregated);
      END IF;
    ELSIF req_type = 'sports' THEN
      SELECT json_agg(item) INTO aggregated
      FROM (
        SELECT (json_array_elements(data->'compact'->'sports')) AS item
        FROM content_cache
        WHERE content_type = 'sports' AND expires_at > NOW()
        ORDER BY created_at DESC
        LIMIT 200
      ) s;
      IF aggregated IS NOT NULL THEN
        result := result || jsonb_build_object('sports', aggregated);
      END IF;
    ELSIF req_type = 'stocks' THEN
      SELECT json_agg(item) INTO aggregated
      FROM (
        SELECT (json_array_elements(data->'compact'->'stocks')) AS item
        FROM content_cache
        WHERE content_type = 'stocks' AND expires_at > NOW()
        ORDER BY created_at DESC
        LIMIT 200
      ) s;
      IF aggregated IS NOT NULL THEN
        result := result || jsonb_build_object('stocks', aggregated);
      END IF;
    END IF;
  END LOOP;

  RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_compact_content IS 'Returns aggregated compact arrays for requested types from latest non-expired cache entries.';


