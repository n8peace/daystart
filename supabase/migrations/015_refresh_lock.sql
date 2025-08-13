-- Advisory lock helpers to prevent overlapping refresh_content executions
-- Uses a fixed lock key; adjust if needed to avoid collision with other app locks

CREATE OR REPLACE FUNCTION try_refresh_lock()
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  SELECT pg_try_advisory_lock(881234567);
$$;

CREATE OR REPLACE FUNCTION release_refresh_lock()
RETURNS VOID
LANGUAGE sql
AS $$
  SELECT pg_advisory_unlock(881234567);
$$;

COMMENT ON FUNCTION try_refresh_lock IS 'Attempt to acquire global advisory lock for refresh_content; returns true if acquired.';
COMMENT ON FUNCTION release_refresh_lock IS 'Release global advisory lock for refresh_content.';


