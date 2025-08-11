import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

interface GetAudioStatusResponse {
  success: boolean;
  status: 'ready' | 'processing' | 'not_found' | 'failed';
  job_id?: string;
  audio_url?: string;
  estimated_ready_time?: string;
  duration?: number;
  transcript?: string;
  error_code?: string;
  error_message?: string;
  request_id: string;
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
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        },
      });
    }

    if (req.method !== 'GET') {
      return createErrorResponse('METHOD_NOT_ALLOWED', 'Only GET method allowed', request_id);
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Extract parameters from URL
    const url = new URL(req.url);
    const date = url.searchParams.get('date');

    if (!date) {
      return createErrorResponse('MISSING_PARAMETER', 'Date parameter is required (YYYY-MM-DD)', request_id);
    }

    // Validate date format
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return createErrorResponse('INVALID_DATE_FORMAT', 'Date must be in YYYY-MM-DD format', request_id);
    }

    // Extract user ID from Authorization header or client info
    const authHeader = req.headers.get('authorization');
    let user_id: string;
    
    if (authHeader?.startsWith('Bearer ')) {
      // For future authenticated users
      const jwt = authHeader.substring(7);
      // TODO: Decode JWT and extract user_id
      user_id = 'authenticated_user'; // Placeholder
    } else {
      // Anonymous user - use device identifier
      const clientInfo = req.headers.get('x-client-info');
      if (!clientInfo) {
        return createErrorResponse('MISSING_USER_ID', 'x-client-info header required for anonymous users', request_id);
      }
      user_id = clientInfo;
    }

    // Query job for this user and date
    const { data: job, error: jobError } = await supabase
      .from('jobs')
      .select('job_id, status, audio_file_path, audio_duration, transcript, estimated_ready_time, error_code, error_message')
      .eq('user_id', user_id)
      .eq('local_date', date)
      .single();

    if (jobError || !job) {
      // Log the request
      await logRequest(supabase, {
        request_id,
        user_id,
        endpoint: '/get_audio_status',
        method: 'GET',
        status_code: 200,
        response_time_ms: Date.now() - start_time,
        user_agent: req.headers.get('user-agent'),
        ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
      });

      const response: GetAudioStatusResponse = {
        success: true,
        status: 'not_found',
        request_id
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // Generate signed URL if audio is ready
    let audio_url: string | undefined;
    if (job.status === 'ready' && job.audio_file_path) {
      try {
        const { data: signedUrlData } = await supabase.storage
          .from('daystart-audio')
          .createSignedUrl(job.audio_file_path, 30 * 60); // 30 minute expiry

        audio_url = signedUrlData?.signedUrl;
        
        if (!audio_url) {
          console.warn(`Failed to generate signed URL for ${job.audio_file_path}`);
        }
      } catch (error) {
        console.error('Signed URL generation error:', error);
      }
    }

    // Map database status to API status
    const apiStatus = mapJobStatusToApiStatus(job.status);

    // Log request for analytics
    await logRequest(supabase, {
      request_id,
      user_id,
      endpoint: '/get_audio_status',
      method: 'GET',
      status_code: 200,
      response_time_ms: Date.now() - start_time,
      user_agent: req.headers.get('user-agent'),
      ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
    });

    const response: GetAudioStatusResponse = {
      success: true,
      status: apiStatus,
      job_id: job.job_id,
      audio_url,
      estimated_ready_time: job.estimated_ready_time,
      duration: job.audio_duration,
      transcript: job.transcript,
      error_code: job.error_code,
      error_message: job.error_message,
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

function mapJobStatusToApiStatus(dbStatus: string): 'ready' | 'processing' | 'not_found' | 'failed' {
  switch (dbStatus) {
    case 'ready':
      return 'ready';
    case 'queued':
    case 'processing':
      return 'processing';
    case 'failed':
      return 'failed';
    default:
      return 'not_found';
  }
}

function createErrorResponse(errorCode: string, message: string, requestId: string): Response {
  const response: GetAudioStatusResponse = {
    success: false,
    status: 'failed',
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