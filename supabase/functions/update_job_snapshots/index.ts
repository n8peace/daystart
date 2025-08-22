import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientCorsHeaders } from "../_shared/cors.ts";

interface UpdateJobSnapshotsRequest {
  job_ids: string[];
  location_data?: {
    city?: string;
    state?: string;
    country?: string;
    latitude?: number;
    longitude?: number;
  };
  weather_data?: {
    temperatureF?: number;
    condition?: string;
    symbol?: string;
    updated_at?: string;
  };
  calendar_events?: string[];
}

interface UpdateJobSnapshotsResponse {
  success: boolean;
  updated_count?: number;
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
        headers: clientCorsHeaders(),
      });
    }

    if (req.method !== 'POST') {
      return createErrorResponse('METHOD_NOT_ALLOWED', 'Only POST method allowed', request_id, 405);
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse request body
    let body: UpdateJobSnapshotsRequest;
    try {
      body = await req.json();
    } catch (error) {
      console.error('JSON parse error:', error);
      return createErrorResponse('INVALID_JSON', 'Invalid JSON in request body', request_id);
    }

    // Validate required fields
    if (!body.job_ids || !Array.isArray(body.job_ids) || body.job_ids.length === 0) {
      return createErrorResponse('VALIDATION_ERROR', 'job_ids array is required and cannot be empty', request_id);
    }

    // Extract user ID from client info (device-specific)
    const clientInfo = req.headers.get('x-client-info');
    if (!clientInfo) {
      return createErrorResponse('MISSING_USER_ID', 'x-client-info header required', request_id);
    }

    console.log(`📋 Updating snapshots for ${body.job_ids.length} jobs for user ${clientInfo}`);

    // Build update payload with only snapshot data
    const updatePayload: Record<string, any> = {
      updated_at: new Date().toISOString()
    };

    if (body.location_data !== undefined) {
      updatePayload.location_data = body.location_data;
    }

    if (body.weather_data !== undefined) {
      updatePayload.weather_data = body.weather_data;
    }

    if (body.calendar_events !== undefined) {
      updatePayload.calendar_events = body.calendar_events;
    }

    console.log(`📝 Update payload:`, JSON.stringify(updatePayload, null, 2));

    // Update jobs with new snapshot data
    const { data: updated, error: updateError } = await supabase
      .from('jobs')
      .update(updatePayload)
      .eq('user_id', clientInfo)
      .in('job_id', body.job_ids)
      .select('job_id, local_date, status');

    if (updateError) {
      console.error('Database update error:', updateError);
      return createErrorResponse('DATABASE_ERROR', 'Failed to update job snapshots', request_id);
    }

    const updatedCount = updated?.length ?? 0;
    console.log(`✅ Updated ${updatedCount} job snapshots`);

    // Log request for analytics
    await logRequest(supabase, {
      request_id,
      user_id: clientInfo,
      endpoint: '/update_job_snapshots',
      method: 'POST',
      status_code: 200,
      response_time_ms: Date.now() - start_time,
      user_agent: req.headers.get('user-agent'),
      ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
    });

    const response: UpdateJobSnapshotsResponse = {
      success: true,
      updated_count: updatedCount,
      request_id
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: clientCorsHeaders(),
    });

  } catch (error) {
    console.error('Unexpected error:', error);
    return createErrorResponse('INTERNAL_ERROR', 'Internal server error', request_id);
  }
});

function createErrorResponse(errorCode: string, message: string, requestId: string, status: number = 400): Response {
  const response: UpdateJobSnapshotsResponse = {
    success: false,
    error_code: errorCode,
    error_message: message,
    request_id: requestId
  };

  return new Response(JSON.stringify(response), {
    status: 200, // Always return 200 for consistency
    headers: clientCorsHeaders(),
  });
}

// Removed duplicate corsHeaders function - now using shared clientCorsHeaders()

async function logRequest(supabase: any, logData: any) {
  try {
    await supabase.from('request_logs').insert([logData]);
  } catch (error) {
    console.warn('Failed to log request:', error);
    // Don't fail the main request if logging fails
  }
}