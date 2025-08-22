import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

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
  force_requeue?: boolean;
}

interface UpdateJobsResponse {
  success: boolean;
  updated_count?: number;
  affected_jobs?: Array<{ job_id: string; local_date: string; status: string }>;
  error_code?: string;
  error_message?: string;
  request_id: string;
}

serve(async (req: Request): Promise<Response> => {
  const request_id = crypto.randomUUID();

  try {
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 200, headers: corsHeaders() });
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

    const response: UpdateJobsResponse = {
      success: true,
      updated_count: updated?.length ?? 0,
      affected_jobs: (updated || []).map(r => ({ job_id: r.job_id, local_date: r.local_date, status: r.status })),
      request_id
    };

    return new Response(JSON.stringify(response), { status: 200, headers: corsHeaders() });
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
  return new Response(JSON.stringify(resp), { status: 200, headers: corsHeaders() });
}

function corsHeaders() {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, content-type'
  };
}


