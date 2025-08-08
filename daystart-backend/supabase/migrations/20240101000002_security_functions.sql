-- Security Functions for DayStart Backend
-- Created: 2024-01-01
-- Helper functions for secure operations in Edge Functions

-- Function to validate user owns a job (for Edge Function use)
CREATE OR REPLACE FUNCTION user_owns_job(job_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if user owns the job
  RETURN EXISTS (
    SELECT 1 FROM jobs 
    WHERE job_id = job_uuid 
    AND user_id = user_uuid
  );
END;
$$;

-- Function to safely log with user privacy
CREATE OR REPLACE FUNCTION safe_log(
  p_job_id UUID,
  p_event TEXT,
  p_level TEXT DEFAULT 'info',
  p_message TEXT DEFAULT NULL,
  p_meta JSONB DEFAULT NULL,
  p_error_details JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  log_id UUID;
BEGIN
  -- Validate log level
  IF p_level NOT IN ('debug', 'info', 'warn', 'error') THEN
    RAISE EXCEPTION 'Invalid log level: %', p_level;
  END IF;

  -- Insert log entry
  INSERT INTO logs (job_id, event, level, message, meta, error_details)
  VALUES (p_job_id, p_event, p_level, p_message, p_meta, p_error_details)
  RETURNING id INTO log_id;
  
  RETURN log_id;
END;
$$;

-- Function to create job with proper validation
CREATE OR REPLACE FUNCTION create_user_job(
  p_user_id UUID,
  p_local_date DATE,
  p_scheduled_at TIMESTAMPTZ,
  p_window_start TIMESTAMPTZ,
  p_window_end TIMESTAMPTZ,
  p_preferred_name TEXT,
  p_location_data JSONB,
  p_weather_data JSONB,
  p_encouragement_preference TEXT,
  p_stock_symbols TEXT[],
  p_include_news BOOLEAN,
  p_include_sports BOOLEAN,
  p_desired_voice TEXT,
  p_desired_length INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  job_uuid UUID;
BEGIN
  -- Validate user exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;

  -- Validate inputs
  IF p_desired_length < 2 OR p_desired_length > 10 THEN
    RAISE EXCEPTION 'Invalid desired_length: must be between 2-10 minutes';
  END IF;

  IF p_scheduled_at <= NOW() THEN
    RAISE EXCEPTION 'scheduled_at must be in the future';
  END IF;

  IF p_window_start >= p_scheduled_at THEN
    RAISE EXCEPTION 'window_start must be before scheduled_at';
  END IF;

  -- Insert or update job (upsert pattern)
  INSERT INTO jobs (
    user_id, local_date, scheduled_at, window_start, window_end,
    preferred_name, location_data, weather_data, encouragement_preference,
    stock_symbols, include_news, include_sports, desired_voice, desired_length,
    status, created_at, updated_at
  ) VALUES (
    p_user_id, p_local_date, p_scheduled_at, p_window_start, p_window_end,
    p_preferred_name, p_location_data, p_weather_data, p_encouragement_preference,
    p_stock_symbols, p_include_news, p_include_sports, p_desired_voice, p_desired_length,
    'queued', NOW(), NOW()
  )
  ON CONFLICT (user_id, local_date) 
  DO UPDATE SET
    scheduled_at = EXCLUDED.scheduled_at,
    window_start = EXCLUDED.window_start,
    window_end = EXCLUDED.window_end,
    preferred_name = EXCLUDED.preferred_name,
    location_data = EXCLUDED.location_data,
    weather_data = EXCLUDED.weather_data,
    encouragement_preference = EXCLUDED.encouragement_preference,
    stock_symbols = EXCLUDED.stock_symbols,
    include_news = EXCLUDED.include_news,
    include_sports = EXCLUDED.include_sports,
    desired_voice = EXCLUDED.desired_voice,
    desired_length = EXCLUDED.desired_length,
    status = 'queued',
    attempt_count = 0,
    worker_id = NULL,
    lease_until = NULL,
    script = NULL,
    script_ready_at = NULL,
    audio_path = NULL,
    audio_ready_at = NULL,
    downloaded_at = NULL,
    failure_reason = NULL,
    updated_at = NOW()
  RETURNING job_id INTO job_uuid;

  -- Log job creation
  PERFORM safe_log(
    job_uuid,
    'job_created',
    'info',
    'Job created for user',
    jsonb_build_object(
      'user_id_hash', hash_user_id(p_user_id),
      'local_date', p_local_date,
      'scheduled_at', p_scheduled_at,
      'desired_length', p_desired_length
    )
  );

  RETURN job_uuid;
END;
$$;

-- Function to lease jobs for workers (FOR UPDATE SKIP LOCKED pattern)
CREATE OR REPLACE FUNCTION lease_jobs_for_processing(
  p_status TEXT,
  p_worker_id UUID,
  p_lease_duration_minutes INTEGER DEFAULT 30,
  p_limit INTEGER DEFAULT 50
)
RETURNS SETOF jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate status
  IF p_status NOT IN ('queued', 'script_ready') THEN
    RAISE EXCEPTION 'Invalid status for leasing: %', p_status;
  END IF;

  -- Return and lease jobs
  RETURN QUERY
  UPDATE jobs 
  SET 
    worker_id = p_worker_id,
    lease_until = NOW() + (p_lease_duration_minutes || ' minutes')::INTERVAL,
    status = CASE 
      WHEN p_status = 'queued' THEN 'script_processing'
      WHEN p_status = 'script_ready' THEN 'audio_processing'
      ELSE status
    END,
    updated_at = NOW()
  WHERE job_id IN (
    SELECT j.job_id
    FROM jobs j
    WHERE j.status = p_status
      AND j.scheduled_at <= NOW() + INTERVAL '6 hours' -- Only process jobs for next 6 hours
      AND (j.lease_until IS NULL OR j.lease_until < NOW()) -- Not currently leased
    ORDER BY j.scheduled_at ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;

-- Function to complete a job step
CREATE OR REPLACE FUNCTION complete_job_step(
  p_job_id UUID,
  p_worker_id UUID,
  p_new_status TEXT,
  p_script TEXT DEFAULT NULL,
  p_audio_path TEXT DEFAULT NULL,
  p_failure_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_job jobs%ROWTYPE;
BEGIN
  -- Get current job and verify worker ownership
  SELECT * INTO current_job
  FROM jobs 
  WHERE job_id = p_job_id 
  AND worker_id = p_worker_id
  AND lease_until > NOW(); -- Ensure lease is still valid

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found or lease expired for worker %', p_worker_id;
  END IF;

  -- Validate status transition
  IF p_new_status NOT IN ('script_ready', 'ready', 'failed', 'failed_missed') THEN
    RAISE EXCEPTION 'Invalid target status: %', p_new_status;
  END IF;

  -- Update job based on new status
  UPDATE jobs 
  SET 
    status = p_new_status,
    script = COALESCE(p_script, script),
    script_ready_at = CASE WHEN p_new_status = 'script_ready' THEN NOW() ELSE script_ready_at END,
    audio_path = COALESCE(p_audio_path, audio_path),
    audio_ready_at = CASE WHEN p_new_status = 'ready' THEN NOW() ELSE audio_ready_at END,
    failure_reason = p_failure_reason,
    worker_id = NULL, -- Release the lease
    lease_until = NULL,
    updated_at = NOW()
  WHERE job_id = p_job_id;

  -- Log the completion
  PERFORM safe_log(
    p_job_id,
    'job_step_completed',
    CASE WHEN p_new_status LIKE 'failed%' THEN 'error' ELSE 'info' END,
    CASE 
      WHEN p_new_status = 'script_ready' THEN 'Script generation completed'
      WHEN p_new_status = 'ready' THEN 'Audio generation completed'
      WHEN p_new_status LIKE 'failed%' THEN 'Job step failed: ' || COALESCE(p_failure_reason, 'Unknown error')
    END,
    jsonb_build_object(
      'worker_id', p_worker_id,
      'new_status', p_new_status,
      'has_script', p_script IS NOT NULL,
      'has_audio_path', p_audio_path IS NOT NULL
    )
  );

  RETURN TRUE;
END;
$$;

-- Grant permissions to service role only
GRANT EXECUTE ON FUNCTION user_owns_job(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION safe_log(UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION create_user_job(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB, JSONB, TEXT, TEXT[], BOOLEAN, BOOLEAN, TEXT, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION lease_jobs_for_processing(TEXT, UUID, INTEGER, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION complete_job_step(UUID, UUID, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- Revoke from other roles
REVOKE EXECUTE ON FUNCTION user_owns_job(UUID, UUID) FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION safe_log(UUID, TEXT, TEXT, TEXT, JSONB, JSONB) FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION create_user_job(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB, JSONB, TEXT, TEXT[], BOOLEAN, BOOLEAN, TEXT, INTEGER) FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION lease_jobs_for_processing(TEXT, UUID, INTEGER, INTEGER) FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION complete_job_step(UUID, UUID, TEXT, TEXT, TEXT, TEXT) FROM authenticated, anon;