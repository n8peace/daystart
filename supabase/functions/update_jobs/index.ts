import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientCorsHeaders } from "../_shared/cors.ts";

interface UpdateJobsRequest {
  dates?: string[];
  date_range?: { start_local_date: string; end_local_date: string };
  statuses?: Array<'queued' | 'failed' | 'processing' | 'ready'>;
  settings?: {
    preferred_name?: string;
    include_weather?: boolean;
    include_news?: boolean;
    include_sports?: boolean;
    include_stocks?: boolean;
    stock_symbols?: string[];
    include_calendar?: boolean;
    include_quotes?: boolean;
    quote_preference?: string;
    voice_option?: string;
    daystart_length?: number;
    timezone?: string;
  };
  scheduled_time?: string; // NEW: ISO8601 string for updating scheduled_at field
  force_requeue?: boolean;
  cancel_for_removed_dates?: string[]; // NEW: dates to cancel jobs for due to schedule changes
  reactivate_for_added_dates?: string[]; // NEW: dates to reactivate cancelled jobs for
}

interface UpdateJobsResponse {
  success: boolean;
  updated_count?: number;
  cancelled_count?: number; // NEW: number of jobs cancelled
  reactivated_count?: number; // NEW: number of jobs reactivated
  affected_jobs?: Array<{ job_id: string; local_date: string; status: string }>;
  cancelled_jobs?: Array<{ job_id: string; local_date: string; status: string }>; // NEW: cancelled jobs list
  reactivated_jobs?: Array<{ job_id: string; local_date: string; status: string }>; // NEW: reactivated jobs list
  error_code?: string;
  error_message?: string;
  request_id: string;
}

serve(async (req: Request): Promise<Response> => {
  const request_id = crypto.randomUUID();

  try {
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 200, headers: clientCorsHeaders() });
    }
    if (req.method !== 'POST') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only POST method allowed', request_id);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const user_id = req.headers.get('x-client-info');
    if (!user_id) {
      return errorResponse('MISSING_USER_ID', 'x-client-info header required', request_id);
    }

    let body: UpdateJobsRequest;
    try {
      body = await req.json();
    } catch (_) {
      return errorResponse('INVALID_JSON', 'Invalid JSON body', request_id);
    }

    const statuses = Array.isArray(body.statuses) && body.statuses.length > 0
      ? body.statuses
      : (['queued', 'failed'] as const);

    const now = new Date();
    const yyyy = now.getFullYear();
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const todayStr = `${yyyy}-${mm}-${dd}`;

    const updatePayload: Record<string, any> = buildUpdatePayload(body);

    let query = supabase
      .from('jobs')
      .update(updatePayload)
      .eq('user_id', user_id)
      .in('status', statuses as any);

    if (Array.isArray(body.dates) && body.dates.length > 0) {
      query = query.in('local_date', body.dates);
    } else if (body.date_range) {
      query = query
        .gte('local_date', body.date_range.start_local_date)
        .lte('local_date', body.date_range.end_local_date);
    } else {
      query = query.gte('local_date', todayStr);
    }

    const { data: updated, error } = await query.select('job_id, local_date, status');
    if (error) {
      console.error('Update jobs error:', error);
      return errorResponse('DATABASE_ERROR', 'Failed to update jobs', request_id);
    }

    // Handle job cancellation for removed schedule dates
    let cancelled: any[] = [];
    if (Array.isArray(body.cancel_for_removed_dates) && body.cancel_for_removed_dates.length > 0) {
      const cancelPayload = {
        status: 'cancelled',
        error_code: 'SCHEDULE_CHANGED',
        error_message: 'Job cancelled due to schedule change',
        updated_at: new Date().toISOString()
      };

      const { data: cancelledJobs, error: cancelError } = await supabase
        .from('jobs')
        .update(cancelPayload)
        .eq('user_id', user_id)
        .in('local_date', body.cancel_for_removed_dates)
        .in('status', ['queued', 'failed']) // Only cancel pending jobs (not processing/ready)
        .neq('priority', 100) // Don't cancel welcome jobs (priority 100)
        .select('job_id, local_date, status');

      if (cancelError) {
        console.error('Cancel jobs error:', cancelError);
        return errorResponse('DATABASE_ERROR', 'Failed to cancel jobs', request_id);
      }
      
      cancelled = cancelledJobs || [];
      console.log(`Cancelled ${cancelled.length} jobs for removed dates: ${body.cancel_for_removed_dates.join(', ')}`);
    }

    // Handle job reactivation for newly added schedule dates
    let reactivated: any[] = [];
    if (Array.isArray(body.reactivate_for_added_dates) && body.reactivate_for_added_dates.length > 0) {
      const reactivatePayload = {
        status: 'queued',
        error_code: null,
        error_message: null,
        updated_at: new Date().toISOString()
      };

      const { data: reactivatedJobs, error: reactivateError } = await supabase
        .from('jobs')
        .update(reactivatePayload)
        .eq('user_id', user_id)
        .in('local_date', body.reactivate_for_added_dates)
        .eq('status', 'cancelled')
        .eq('error_code', 'SCHEDULE_CHANGED') // Only reactivate schedule-cancelled jobs
        .select('job_id, local_date, status');

      if (reactivateError) {
        console.error('Reactivate jobs error:', reactivateError);
        return errorResponse('DATABASE_ERROR', 'Failed to reactivate jobs', request_id);
      }
      
      reactivated = reactivatedJobs || [];
      console.log(`Reactivated ${reactivated.length} jobs for added dates: ${body.reactivate_for_added_dates.join(', ')}`);
    }

    const response: UpdateJobsResponse = {
      success: true,
      updated_count: updated?.length ?? 0,
      cancelled_count: cancelled.length,
      reactivated_count: reactivated.length,
      affected_jobs: (updated || []).map(r => ({ job_id: r.job_id, local_date: r.local_date, status: r.status })),
      cancelled_jobs: cancelled.map(r => ({ job_id: r.job_id, local_date: r.local_date, status: r.status })),
      reactivated_jobs: reactivated.map(r => ({ job_id: r.job_id, local_date: r.local_date, status: r.status })),
      request_id
    };

    return new Response(JSON.stringify(response), { status: 200, headers: clientCorsHeaders() });
  } catch (e) {
    console.error('Unexpected error:', e);
    return errorResponse('INTERNAL_ERROR', 'Internal server error', request_id);
  }
});

function buildUpdatePayload(body: UpdateJobsRequest): Record<string, any> {
  const payload: Record<string, any> = { updated_at: new Date().toISOString() };
  const s = body.settings || {};
  if (s.preferred_name !== undefined) payload.preferred_name = s.preferred_name;
  if (s.include_weather !== undefined) payload.include_weather = s.include_weather;
  if (s.include_news !== undefined) payload.include_news = s.include_news;
  if (s.include_sports !== undefined) payload.include_sports = s.include_sports;
  if (s.include_stocks !== undefined) payload.include_stocks = s.include_stocks;
  if (s.stock_symbols !== undefined) payload.stock_symbols = s.stock_symbols;
  if (s.include_calendar !== undefined) payload.include_calendar = s.include_calendar;
  if (s.include_quotes !== undefined) payload.include_quotes = s.include_quotes;
  if (s.quote_preference !== undefined) payload.quote_preference = s.quote_preference;
  if (s.voice_option !== undefined) payload.voice_option = s.voice_option;
  if (s.daystart_length !== undefined) payload.daystart_length = s.daystart_length;
  if (s.timezone !== undefined) payload.timezone = s.timezone;

  // NEW: Handle scheduled_at updates
  if (body.scheduled_time !== undefined) {
    payload.scheduled_at = body.scheduled_time;
  }

  if (body.force_requeue) {
    payload.status = 'queued';
    payload.script_content = null;
    payload.audio_file_path = null;
    payload.audio_duration = null;
    payload.transcript = null;
    payload.script_cost = null;
    payload.tts_cost = null;
    payload.total_cost = null;
    payload.completed_at = null;
    payload.worker_id = null;
    payload.lease_until = null;
    payload.estimated_ready_time = new Date(Date.now() + 90_000).toISOString();
  }

  return payload;
}

function errorResponse(code: string, message: string, request_id: string): Response {
  const resp: UpdateJobsResponse = {
    success: false,
    error_code: code,
    error_message: message,
    request_id
  };
  return new Response(JSON.stringify(resp), { status: 200, headers: clientCorsHeaders() });
}

// Removed duplicate clientCorsHeaders function - now using shared version


