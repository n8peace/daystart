import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientCorsHeaders } from "../_shared/cors.ts";

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
          ...clientCorsHeaders(),
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
    const markCompleted = url.searchParams.get('mark_completed') === 'true';

    if (!date) {
      return createErrorResponse('MISSING_PARAMETER', 'Date parameter is required (YYYY-MM-DD)', request_id);
    }

    // Validate date format
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return createErrorResponse('INVALID_DATE_FORMAT', 'Date must be in YYYY-MM-DD format', request_id);
    }

    // Extract user ID from client info (device-specific)
    const clientInfo = req.headers.get('x-client-info');
    if (!clientInfo) {
      return createErrorResponse('MISSING_USER_ID', 'x-client-info header required', request_id);
    }
    const user_id = clientInfo;

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

    // Query job for this user and date
    const { data: job, error: jobError } = await supabase
      .from('jobs')
      .select('job_id, status, audio_file_path, audio_duration, transcript, estimated_ready_time, error_code, error_message, user_completed')
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

    // Mark as completed if requested and job is ready
    if (markCompleted && job.status === 'ready' && !job.user_completed) {
      try {
        const { error: updateError } = await supabase
          .from('jobs')
          .update({
            user_completed: true,
            user_completed_at: new Date().toISOString()
          })
          .eq('job_id', job.job_id)
          .eq('user_id', user_id);

        if (updateError) {
          console.warn('Failed to mark job as completed:', updateError);
          // Don't fail the request, just log the error
        } else {
          console.log(`Marked job ${job.job_id} as completed for user ${user_id}`);
        }
      } catch (error) {
        console.warn('Error marking job as completed:', error);
        // Don't fail the request, just log the error
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