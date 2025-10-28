import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientCorsHeaders } from "../_shared/cors.ts";

interface CreateJobRequest {
  local_date: string; // YYYY-MM-DD or "TODAY"
  scheduled_at: string; // ISO timestamp or "NOW"
  preferred_name?: string;
  include_weather: boolean;
  include_news: boolean;
  include_sports: boolean;
  selected_sports?: string[];
  include_stocks: boolean;
  stock_symbols: string[];
  include_calendar: boolean;
  include_quotes: boolean;
  quote_preference: string;
  voice_option: string;
  daystart_length: number;
  timezone: string;
  process_not_before?: string; // ISO timestamp (optional)
  // Optional contextual data
  location_data?: {
    city?: string;
    state?: string;
    country?: string;
    // Removed coordinates for privacy compliance
  };
  weather_data?: any;
  calendar_events?: any[];
  // Explicitly allow re-queuing and updating an existing ready/processing job
  force_update?: boolean;
  // Flag to indicate this is a welcome/onboarding job
  is_welcome?: boolean;
  // Flag to indicate this is a social media DayStart
  social_daystart?: boolean;
}

interface CreateJobResponse {
  success: boolean;
  job_id?: string;
  status?: 'queued' | 'processing' | 'ready' | 'failed';
  estimated_ready_time?: string;
  error_code?: string;
  error_message?: string;
  request_id: string;
  is_welcome?: boolean;
}

function sanitizeName(name: string | undefined): string | undefined {
  if (!name || name.trim() === '') return undefined;
  
  // Remove all non-pronounceable unicode, emojis, and special symbols
  // Keep: Basic Latin, common Latin extended, spaces, hyphens, apostrophes
  const sanitized = name
    // Remove emoji and special Unicode blocks while preserving common accented characters
    .replace(/[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F000}-\u{1F02F}]|[\u{1F0A0}-\u{1F0FF}]|[\u{1F100}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{1F900}-\u{1F9FF}]/gu, '')
    // Remove other special Unicode ranges (various symbols, shapes, etc)
    .replace(/[\u{10000}-\u{10FFFF}]/gu, '')
    // Remove special characters but keep basic punctuation and accented Latin
    .replace(/[^\u0020-\u007E\u00A0-\u00FF\u0100-\u017F\u0180-\u024F]/g, '')
    // Remove multiple spaces
    .replace(/\s+/g, ' ')
    // Trim first, then limit length
    .trim();
  
  // If nothing remains after sanitization, return undefined
  if (sanitized.length === 0) return undefined;
  
  // Apply length limit after all cleaning
  return sanitized.slice(0, 50);
}

serve(async (req: Request): Promise<Response> => {
  const request_id = crypto.randomUUID();
  const start_time = Date.now();
  
  try {
    // CORS headers
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 200,
        headers: {
          ...clientCorsHeaders(),
        },
      });
    }

    if (req.method !== 'POST') {
      return createErrorResponse('METHOD_NOT_ALLOWED', 'Only POST method allowed', request_id, 405);
    }

    // Initialize Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse request body
    let body: CreateJobRequest;
    try {
      body = await req.json();
    } catch (error) {
      console.error('JSON parse error:', error);
      return createErrorResponse('INVALID_JSON', 'Invalid JSON in request body', request_id);
    }

    // Handle special date values before validation
    if (body.local_date === "TODAY") {
      // Convert to YYYY-MM-DD in the requested timezone
      const today = new Date().toLocaleDateString('en-CA', { 
        timeZone: body.timezone 
      });
      body.local_date = today;
      console.log(`Converted TODAY to ${today} in timezone ${body.timezone}`);
    }

    // Handle special scheduled_at values
    if (body.scheduled_at === "NOW") {
      const now = new Date();
      body.scheduled_at = now.toISOString();
      // Set process_not_before to NOW for immediate processing
      body.process_not_before = now.toISOString();
      console.log(`Converted NOW to ${body.scheduled_at} with immediate processing`);
    }

    // Validate required fields
    const validation = validateRequest(body);
    if (!validation.valid) {
      return createErrorResponse('VALIDATION_ERROR', validation.error!, request_id);
    }

    // Extract user ID from client info (receipt-based auth)
    const clientInfo = req.headers.get('x-client-info');
    if (!clientInfo) {
      return createErrorResponse('MISSING_USER_ID', 'x-client-info header required', request_id);
    }
    const user_id = clientInfo;

    // Auto-detect social DayStart from x-client-info
    const socialPatterns = ['DAILY_GENERIC', 'SOCIAL_TIKTOK', 'SOCIAL_YOUTUBE', 'SOCIAL_INSTAGRAM'];
    if (!body.social_daystart && socialPatterns.some(pattern => clientInfo.includes(pattern))) {
      body.social_daystart = true;
      console.log(`Auto-detected social DayStart from x-client-info: ${clientInfo}`);
    }

    // Track purchase user for analytics (non-critical, fail-safe)
    const authType = req.headers.get('x-auth-type');
    try {
      if (authType === 'purchase') {
        await supabase.rpc('track_purchase_user', {
          p_receipt_id: user_id,
          p_is_test: user_id.startsWith('tx_')
        });
      }
    } catch (error) {
      console.warn('User tracking failed (non-critical):', error);
    }

    // Calculate estimated ready time (1-2 minutes from now with 1-minute cron schedule)
    const estimated_ready_time = new Date(Date.now() + (1.5 * 60 * 1000)).toISOString();

    // Check existing job to avoid status regression
    const { data: existingJob } = await supabase
      .from('jobs')
      .select('job_id, status, estimated_ready_time, is_welcome')
      .eq('user_id', user_id)
      .eq('local_date', body.local_date)
      .single();

    const forceUpdate = !!(body as any).force_update;
    
    // Special case: If incoming request is a welcome job but existing job is not,
    // always update to make it a welcome job
    const shouldUpgradeToWelcome = body.is_welcome === true && existingJob?.is_welcome === false;

    if (existingJob) {
      // If the new request is a welcome job but the existing one isn't, always upgrade
      if (shouldUpgradeToWelcome) {
        // Update the existing job to be a welcome job, regardless of status
        const { data: updatedJob, error: updateErr } = await supabase
          .from('jobs')
          .update({
            is_welcome: true,
            social_daystart: body.social_daystart || false,
            priority: 100,
            updated_at: new Date().toISOString()
          })
          .eq('job_id', existingJob.job_id)
          .select('job_id, status, estimated_ready_time, is_welcome')
          .single();

        if (updateErr) {
          console.error('Database error (welcome upgrade):', updateErr);
          return createErrorResponse('DATABASE_ERROR', 'Failed to upgrade to welcome job', request_id);
        }

        await logRequest(supabase, {
          request_id,
          user_id,
          endpoint: '/create_job',
          method: 'POST',
          status_code: 200,
          response_time_ms: Date.now() - start_time,
          user_agent: req.headers.get('user-agent'),
          ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
        });

        const response: CreateJobResponse = {
          success: true,
          job_id: updatedJob.job_id,
          status: updatedJob.status,
          estimated_ready_time: updatedJob.estimated_ready_time,
          is_welcome: updatedJob.is_welcome,
          request_id
        };

        return new Response(JSON.stringify(response), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      }
      
      // Handle processing/ready status jobs
      if (existingJob.status === 'processing' || existingJob.status === 'ready') {
        if (forceUpdate) {
        // Re-queue existing job with updated settings and clear generated fields
        let process_not_before: string | undefined = undefined;
        try {
          const sched = new Date(body.scheduled_at);
          const defaultNotBefore = new Date(sched.getTime() - 45 * 60 * 1000).toISOString();
          process_not_before = body.process_not_before || defaultNotBefore;
        } catch (_) {}

        const { data: updatedJob, error: updateErr } = await supabase
          .from('jobs')
          .update({
            scheduled_at: body.scheduled_at,
            process_not_before,
            preferred_name: sanitizeName(body.preferred_name),
            include_weather: body.include_weather,
            include_news: body.include_news,
            include_sports: body.include_sports,
            selected_sports: body.selected_sports || ['MLB', 'NHL', 'NBA', 'NFL', 'NCAAF'],
            include_stocks: body.include_stocks,
            stock_symbols: body.stock_symbols,
            include_calendar: body.include_calendar,
            include_quotes: body.include_quotes,
            quote_preference: body.quote_preference,
            voice_option: body.voice_option,
            daystart_length: body.is_welcome ? 60 : body.daystart_length,
            timezone: body.timezone,
            location_data: body.location_data,
            weather_data: body.weather_data,
            calendar_events: body.calendar_events,
            social_daystart: body.social_daystart || false,
            tts_provider: 'openai',
            // Clear generated results and costs
            script_content: null,
            audio_file_path: null,
            audio_duration: null,
            transcript: null,
            script_cost: null,
            tts_cost: null,
            total_cost: null,
            completed_at: null,
            worker_id: null,
            lease_until: null,
            estimated_ready_time,
            status: 'queued',
            priority: body.is_welcome ? 100 : calculatePriority(body.local_date, body.scheduled_at),
            is_welcome: body.is_welcome || existingJob.is_welcome || false,
            updated_at: new Date().toISOString()
          })
          .eq('job_id', existingJob.job_id)
          .select('job_id, status, estimated_ready_time, is_welcome')
          .single();

        if (updateErr) {
          console.error('Database error (force_update):', updateErr);
          return createErrorResponse('DATABASE_ERROR', 'Failed to update job', request_id);
        }

        await logRequest(supabase, {
          request_id,
          user_id,
          endpoint: '/create_job',
          method: 'POST',
          status_code: 200,
          response_time_ms: Date.now() - start_time,
          user_agent: req.headers.get('user-agent'),
          ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
        });

        const response: CreateJobResponse = {
          success: true,
          job_id: updatedJob.job_id,
          status: updatedJob.status,
          estimated_ready_time: updatedJob.estimated_ready_time,
          is_welcome: updatedJob.is_welcome,
          request_id
        };

        return new Response(JSON.stringify(response), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
        }

        // Do not regress status; return existing details
        await logRequest(supabase, {
          request_id,
          user_id,
          endpoint: '/create_job',
          method: 'POST',
          status_code: 200,
          response_time_ms: Date.now() - start_time,
          user_agent: req.headers.get('user-agent'),
          ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
        });

        const response: CreateJobResponse = {
          success: true,
          job_id: existingJob.job_id,
          status: existingJob.status,
          estimated_ready_time: existingJob.estimated_ready_time,
          is_welcome: existingJob.is_welcome,
          request_id
        };

        return new Response(JSON.stringify(response), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      }
    }

    // Compute process_not_before (default to scheduled_at - 45m if not provided)
    let process_not_before: string | undefined = undefined;
    try {
      const sched = new Date(body.scheduled_at);
      const defaultNotBefore = new Date(sched.getTime() - 45 * 60 * 1000).toISOString();
      process_not_before = body.process_not_before || defaultNotBefore;
    } catch (_) {}

    // Insert or update job (upsert for idempotency)
    const { data: job, error: jobError } = await supabase
      .from('jobs')
      .upsert({
        user_id,
        local_date: body.local_date,
        scheduled_at: body.scheduled_at,
        process_not_before,
        preferred_name: sanitizeName(body.preferred_name),
        include_weather: body.include_weather,
        include_news: body.include_news,
        include_sports: body.include_sports,
        selected_sports: body.selected_sports || ['MLB', 'NHL', 'NBA', 'NFL', 'NCAAF'],
        include_stocks: body.include_stocks,
        stock_symbols: body.stock_symbols,
        include_calendar: body.include_calendar,
        include_quotes: body.include_quotes,
        quote_preference: body.quote_preference,
        voice_option: body.voice_option,
        daystart_length: body.is_welcome ? 60 : body.daystart_length,
        timezone: body.timezone,
        location_data: body.location_data,
        weather_data: body.weather_data,
        calendar_events: body.calendar_events,
        social_daystart: body.social_daystart || false,
        tts_provider: 'openai',
        estimated_ready_time,
        status: 'queued',
        priority: body.is_welcome ? 100 : calculatePriority(body.local_date, body.scheduled_at),
        is_welcome: body.is_welcome || false,
        updated_at: new Date().toISOString()
      }, {
        onConflict: 'user_id,local_date',
        ignoreDuplicates: false
      })
      .select('job_id, status, estimated_ready_time')
      .single();

    if (jobError) {
      console.error('Database error:', jobError);
      return createErrorResponse('DATABASE_ERROR', 'Failed to create job', request_id);
    }

    // Log request for rate limiting and analytics
    await logRequest(supabase, {
      request_id,
      user_id,
      endpoint: '/create_job',
      method: 'POST',
      status_code: 200,
      response_time_ms: Date.now() - start_time,
      user_agent: req.headers.get('user-agent'),
      ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
    });

    const response: CreateJobResponse = {
      success: true,
      job_id: job.job_id,
      status: job.status,
      estimated_ready_time: job.estimated_ready_time,
      is_welcome: job.is_welcome,
      request_id
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });

  } catch (error) {
    console.error('Unexpected error:', error);
    return createErrorResponse('INTERNAL_ERROR', 'Internal server error', request_id);
  }
});

function validateRequest(body: any): { valid: boolean; error?: string } {
  const required = ['local_date', 'scheduled_at', 'timezone'];
  
  for (const field of required) {
    if (!body[field]) {
      return { valid: false, error: `Missing required field: ${field}` };
    }
  }

  // Validate date format (YYYY-MM-DD)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(body.local_date)) {
    return { valid: false, error: 'local_date must be in YYYY-MM-DD format' };
  }

  // Validate ISO timestamp
  if (isNaN(Date.parse(body.scheduled_at))) {
    return { valid: false, error: 'scheduled_at must be valid ISO timestamp' };
  }

  // Validate stock symbols (match iOS validation)
  if (body.stock_symbols && Array.isArray(body.stock_symbols)) {
    const allowedPattern = /^[A-Z0-9\-\.\$\=\^]{1,16}$/;
    for (const symbol of body.stock_symbols) {
      if (!allowedPattern.test(symbol)) {
        return { valid: false, error: `Invalid stock symbol: ${symbol}` };
      }
    }
  }

  // Validate process_not_before if present
  if (body.process_not_before && isNaN(Date.parse(body.process_not_before))) {
    return { valid: false, error: 'process_not_before must be valid ISO timestamp when provided' };
  }

  return { valid: true };
}

function calculatePriority(localDate: string, scheduledAt: string): number {
  const scheduled = new Date(scheduledAt);
  const now = new Date();
  const hoursUntilScheduled = (scheduled.getTime() - now.getTime()) / (1000 * 60 * 60);

  // Welcome/First DayStart priority: 100
  // Immediate processing (NOW jobs): 100
  // Same-day urgent (< 4 hours): 75
  // Regular (4-24 hours): 50
  // Background (> 24 hours): 25
  
  // Check if this is a "NOW" job (scheduled within 1 minute of current time)
  if (Math.abs(hoursUntilScheduled) < (1/60)) {
    return 100; // Immediate processing
  }
  
  // Handle past-due jobs as urgent
  if (hoursUntilScheduled < 0) {
    return 75; // Past due, high priority
  }
  
  if (hoursUntilScheduled < 4) {
    return 75; // Urgent
  } else if (hoursUntilScheduled < 24) {
    return 50; // Regular
  } else {
    return 25; // Background
  }
}

function createErrorResponse(errorCode: string, message: string, requestId: string, status: number = 400): Response {
  const response: CreateJobResponse = {
    success: false,
    error_code: errorCode,
    error_message: message,
    request_id: requestId
  };

  return new Response(JSON.stringify(response), {
    status: 200, // Always return 200 per GPT-5 review
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

async function logRequest(supabase: any, logData: any) {
  try {
    await supabase.from('request_logs').insert([logData]);
  } catch (error) {
    console.warn('Failed to log request:', error);
    // Don't fail the main request if logging fails
  }
}