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
    selected_sports?: string[];
    selected_news_categories?: string[];
    include_stocks?: boolean;
    stock_symbols?: string[];
    include_calendar?: boolean;
    include_quotes?: boolean;
    quote_preference?: string;
    voice_option?: string;
    daystart_length?: number;
    timezone?: string;
    schedule_time?: string; // NEW: Time in HH:MM format (e.g., "07:30") for calculating scheduled_at
  };
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

    let body: UpdateJobsRequest;
    try {
      body = await req.json();
    } catch (_) {
      return errorResponse('INVALID_JSON', 'Invalid JSON body', request_id);
    }

    // Debug logging for news categories
    console.log('📰 DEBUG: Received settings:', JSON.stringify(body.settings, null, 2));
    if (body.settings?.selected_news_categories) {
      console.log('📰 DEBUG: selected_news_categories received:', body.settings.selected_news_categories);
    } else {
      console.log('📰 DEBUG: selected_news_categories NOT found in request');
    }

    const statuses = Array.isArray(body.statuses) && body.statuses.length > 0
      ? body.statuses
      : (['queued', 'failed'] as const);

    const now = new Date();
    const yyyy = now.getFullYear();
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const todayStr = `${yyyy}-${mm}-${dd}`;

    let updated: any[] = [];

    // If we need to update scheduled_at based on schedule_time, we need to update each job individually
    const needsScheduleUpdate = body.settings?.schedule_time !== undefined && body.settings?.timezone !== undefined;

    if (needsScheduleUpdate && Array.isArray(body.dates) && body.dates.length > 0) {
      // Update each job individually to calculate correct scheduled_at for each date
      for (const localDate of body.dates) {
        const updatePayload = buildUpdatePayload(body, localDate);

        const { data: jobUpdated, error } = await supabase
          .from('jobs')
          .update(updatePayload)
          .eq('user_id', user_id)
          .eq('local_date', localDate)
          .in('status', statuses as any)
          .select('job_id, local_date, status');

        if (error) {
          console.error(`Update job error for date ${localDate}:`, error);
          return errorResponse('DATABASE_ERROR', `Failed to update job for date ${localDate}`, request_id);
        }

        if (jobUpdated) {
          updated.push(...jobUpdated);
        }
      }
    } else {
      // Use bulk update for other cases (no schedule_time change)
      const updatePayload = buildUpdatePayload(body);

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

      const { data: bulkUpdated, error } = await query.select('job_id, local_date, status');
      if (error) {
        console.error('Update jobs error:', error);
        return errorResponse('DATABASE_ERROR', 'Failed to update jobs', request_id);
      }
      updated = bulkUpdated || [];
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

function buildUpdatePayload(body: UpdateJobsRequest, localDate?: string): Record<string, any> {
  const payload: Record<string, any> = { updated_at: new Date().toISOString() };
  const s = body.settings || {};
  if (s.preferred_name !== undefined) payload.preferred_name = s.preferred_name;
  if (s.include_weather !== undefined) payload.include_weather = s.include_weather;
  if (s.include_news !== undefined) payload.include_news = s.include_news;
  if (s.include_sports !== undefined) payload.include_sports = s.include_sports;
  if (s.selected_sports !== undefined) payload.selected_sports = s.selected_sports;
  if (s.selected_news_categories !== undefined) {
    payload.selected_news_categories = s.selected_news_categories;
    console.log('📰 DEBUG: Adding selected_news_categories to payload:', s.selected_news_categories);
  } else {
    console.log('📰 DEBUG: selected_news_categories is undefined, not adding to payload');
  }
  if (s.include_stocks !== undefined) payload.include_stocks = s.include_stocks;
  if (s.stock_symbols !== undefined) payload.stock_symbols = s.stock_symbols;
  if (s.include_calendar !== undefined) payload.include_calendar = s.include_calendar;
  if (s.include_quotes !== undefined) payload.include_quotes = s.include_quotes;
  if (s.quote_preference !== undefined) payload.quote_preference = s.quote_preference;
  if (s.voice_option !== undefined) payload.voice_option = s.voice_option;
  if (s.daystart_length !== undefined) payload.daystart_length = s.daystart_length;
  if (s.timezone !== undefined) payload.timezone = s.timezone;

  // NEW: Calculate scheduled_at for each job individually based on its local_date
  if (s.schedule_time !== undefined && s.timezone !== undefined && localDate !== undefined) {
    payload.scheduled_at = calculateScheduledAt(localDate, s.schedule_time, s.timezone);
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

  console.log('📰 DEBUG: Final update payload:', JSON.stringify(payload, null, 2));
  return payload;
}

// NEW: Calculate scheduled_at timestamp for a specific date
function calculateScheduledAt(localDate: string, scheduleTime: string, timezone: string): string {
  // Create a date string that represents the desired local time
  const localDateTimeString = `${localDate}T${scheduleTime}:00`;
  
  // Create a date assuming it's UTC first
  const baseDate = new Date(localDateTimeString);
  
  // Use Intl.DateTimeFormat to find the UTC time that gives us the desired local time
  const formatter = new Intl.DateTimeFormat('sv-SE', { // ISO format
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
  
  // Get what time the base date shows in the target timezone
  const formattedInTimezone = formatter.format(baseDate).replace(' ', 'T');
  
  // Calculate the difference between what we want and what we got
  const wantedTime = new Date(localDateTimeString);
  const actualTime = new Date(formattedInTimezone);
  const timeDiff = wantedTime.getTime() - actualTime.getTime();
  
  // Adjust the base date by the difference
  const correctedUtc = new Date(baseDate.getTime() + timeDiff);
  
  return correctedUtc.toISOString();
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


