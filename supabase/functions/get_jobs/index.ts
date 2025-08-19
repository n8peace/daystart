import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

interface GetJobsResponse {
  success: boolean;
  jobs?: JobSummary[];
  error_code?: string;
  error_message?: string;
  request_id: string;
}

interface JobSummary {
  job_id: string;
  local_date: string;
  scheduled_at?: string;
  status: string;
}

serve(async (req: Request): Promise<Response> => {
  const request_id = crypto.randomUUID();
  const start_time = Date.now();

  try {
    // CORS headers
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 200,
        headers: corsHeaders(),
      });
    }

    if (req.method !== 'GET') {
      return createErrorResponse('METHOD_NOT_ALLOWED', 'Only GET method allowed', request_id, 405);
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Extract user ID from client info (device-specific)
    const clientInfo = req.headers.get('x-client-info');
    if (!clientInfo) {
      return createErrorResponse('MISSING_USER_ID', 'x-client-info header required', request_id);
    }

    // Parse query parameters
    const url = new URL(req.url);
    const startDate = url.searchParams.get('start_date');
    const endDate = url.searchParams.get('end_date');

    if (!startDate || !endDate) {
      return createErrorResponse('VALIDATION_ERROR', 'start_date and end_date query parameters are required', request_id);
    }

    // Validate date format (YYYY-MM-DD)
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(startDate) || !dateRegex.test(endDate)) {
      return createErrorResponse('VALIDATION_ERROR', 'Dates must be in YYYY-MM-DD format', request_id);
    }

    console.log(`📋 Getting jobs for user ${clientInfo} from ${startDate} to ${endDate}`);

    // Query jobs in date range
    const { data: jobs, error: queryError } = await supabase
      .from('jobs')
      .select('job_id, local_date, scheduled_at, status')
      .eq('user_id', clientInfo)
      .gte('local_date', startDate)
      .lte('local_date', endDate)
      .order('local_date', { ascending: true });

    if (queryError) {
      console.error('Database query error:', queryError);
      return createErrorResponse('DATABASE_ERROR', 'Failed to retrieve jobs', request_id);
    }

    const jobSummaries: JobSummary[] = (jobs || []).map(job => ({
      job_id: job.job_id,
      local_date: job.local_date,
      scheduled_at: job.scheduled_at,
      status: job.status
    }));

    console.log(`✅ Found ${jobSummaries.length} jobs in date range`);

    // Log request for analytics
    await logRequest(supabase, {
      request_id,
      user_id: clientInfo,
      endpoint: '/get_jobs',
      method: 'GET',
      status_code: 200,
      response_time_ms: Date.now() - start_time,
      user_agent: req.headers.get('user-agent'),
      ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
    });

    const response: GetJobsResponse = {
      success: true,
      jobs: jobSummaries,
      request_id
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: corsHeaders(),
    });

  } catch (error) {
    console.error('Unexpected error:', error);
    return createErrorResponse('INTERNAL_ERROR', 'Internal server error', request_id);
  }
});

function createErrorResponse(errorCode: string, message: string, requestId: string, status: number = 400): Response {
  const response: GetJobsResponse = {
    success: false,
    error_code: errorCode,
    error_message: message,
    request_id: requestId
  };

  return new Response(JSON.stringify(response), {
    status: 200, // Always return 200 for consistency
    headers: corsHeaders(),
  });
}

function corsHeaders() {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

async function logRequest(supabase: any, logData: any) {
  try {
    await supabase.from('request_logs').insert([logData]);
  } catch (error) {
    console.warn('Failed to log request:', error);
    // Don't fail the main request if logging fails
  }
}