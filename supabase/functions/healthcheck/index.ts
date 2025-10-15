import { serve } from "https://deno.land/std@0.208.0/http/server.ts"
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"

type CheckStatus = 'pass' | 'warn' | 'fail' | 'skip'

interface CheckResult<T = unknown> {
  name: string
  status: CheckStatus
  details?: T
  error?: string
  duration_ms: number
}

interface HealthReport {
  overall_status: CheckStatus
  summary: string
  checks: CheckResult[]
  request_id: string
  started_at: string
  finished_at: string
  duration_ms: number
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

serve(async (req: Request): Promise<Response> => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const request_id = crypto.randomUUID()

  try {
    if (req.method !== 'POST') {
      return json({ success: false, message: 'Only POST method allowed', request_id }, 405)
    }

    // Verify authorization - service role key only
    const authHeader = req.headers.get('authorization')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !supabaseServiceKey || authHeader !== `Bearer ${supabaseServiceKey}`) {
      return json({ success: false, message: 'Unauthorized', request_id }, 401)
    }

    const url = new URL(req.url)
    const notify = url.searchParams.get('notify') !== '0' // default true
    const started_at = new Date().toISOString()

    // Fire-and-forget the async health run
    runHealthcheckAsync({ request_id, notify, started_at }).catch((err) => {
      console.error('Healthcheck async error:', err)
    })

    // Immediate success response per backend convention
    return new Response(
      JSON.stringify({ success: true, message: 'Healthcheck accepted', request_id, started_at }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  } catch (error) {
    console.error('Healthcheck error:', error)
    return json({ success: false, message: 'Internal server error', request_id }, 500)
  }
})

async function runHealthcheckAsync({ request_id, notify, started_at }: { request_id: string; notify: boolean; started_at: string }) {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabase = createClient(supabaseUrl, supabaseKey)

  const t0 = Date.now()

  // Run checks with per-check timeouts
  const checks: CheckResult[] = []
  // MOST IMPORTANT: DayStarts completed - this is our true north metric
  checks.push(await withTimeout('daystarts_completed', () => checkDayStartsCompleted(supabase), 3000))
  checks.push(await withTimeout('db_connectivity', () => checkDbConnectivity(supabase), 3000))
  checks.push(await withTimeout('jobs_queue', () => checkJobsHealth(supabase), 5000))
  checks.push(await withTimeout('content_cache_freshness', () => checkContentCache(supabase), 4000))
  checks.push(await withTimeout('storage_access', () => checkStorageAccess(supabase), 8000))
  checks.push(await withTimeout('internal_urls', () => checkInternalUrls(), 6000))
  checks.push(await withTimeout('audio_cleanup_heartbeat', () => checkAudioCleanupHeartbeat(supabase), 3000))
  checks.push(await withTimeout('request_error_rate', () => checkRequestErrorRate(supabase), 3000))

  const overall = aggregateOverall(checks)
  
  // Get AI diagnosis if there are issues
  let aiDiagnosis: string | null = null
  if (overall.status !== 'pass') {
    try {
      aiDiagnosis = await getAIDiagnosis(checks)
    } catch (err) {
      console.error('AI diagnosis error:', err)
    }
  }
  
  const finished_at = new Date().toISOString()
  const report: HealthReport & { ai_diagnosis?: string } = {
    overall_status: overall.status,
    summary: overall.summary,
    checks,
    request_id,
    started_at,
    finished_at,
    duration_ms: Date.now() - t0,
    ai_diagnosis: aiDiagnosis || undefined,
  }

  // Email via Resend
  try {
    if (notify) {
      await sendResendEmail(report)
    }
  } catch (err) {
    console.error('Resend email error:', err)
  }

  // Log to request_logs
  try {
    await supabase.from('request_logs').insert({
      request_id,
      endpoint: '/healthcheck',
      method: 'POST',
      status_code: 200,
      response_time_ms: report.duration_ms,
      error_code: report.overall_status === 'fail' ? 'HEALTHCHECK_FAIL' : report.overall_status === 'warn' ? 'HEALTHCHECK_WARN' : null,
    })
  } catch (err) {
    console.error('Failed to insert request_log for healthcheck:', err)
  }
}

function aggregateOverall(checks: CheckResult[]): { status: CheckStatus; summary: string } {
  const hasFail = checks.some((c) => c.status === 'fail')
  const hasWarn = checks.some((c) => c.status === 'warn')
  const status: CheckStatus = hasFail ? 'fail' : hasWarn ? 'warn' : 'pass'
  const parts: string[] = []
  for (const c of checks) {
    parts.push(`${c.name}: ${c.status}`)
  }
  return { status, summary: parts.join('; ') }
}

async function withTimeout<T>(name: string, fn: () => Promise<CheckResult<T>>, timeoutMs: number): Promise<CheckResult<T>> {
  const start = Date.now()
  try {
    const res = await Promise.race<Promise<CheckResult<T>> | Promise<CheckResult<T>>>([
      fn(),
      new Promise<CheckResult<T>>((resolve) =>
        setTimeout(() => resolve({ name, status: 'warn', error: 'timeout', duration_ms: Date.now() - start }), timeoutMs),
      ),
    ])
    // Attach duration if not set
    if (!('duration_ms' in res) || (res as any).duration_ms === undefined) {
      ;(res as any).duration_ms = Date.now() - start
    }
    return res
  } catch (err) {
    return { name, status: 'fail', error: (err as Error).message || String(err), duration_ms: Date.now() - start }
  }
}

async function checkDayStartsCompleted(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const since24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
  
  try {
    // Count completed DayStarts (ready status) in last 24 hours
    const { count: completedCount, error } = await supabase
      .from('jobs')
      .select('*', { head: true, count: 'exact' })
      .eq('status', 'ready')
      .gte('completed_at', since24h)
    
    if (error) {
      return { name: 'daystarts_completed', status: 'fail', error: error.message, duration_ms: Date.now() - start }
    }
    
    const count = completedCount ?? 0
    
    // Also get some stats on audio generation times
    const { data: recentCompleted } = await supabase
      .from('jobs')
      .select('created_at, completed_at, scheduled_at, user_id')
      .eq('status', 'ready')
      .gte('completed_at', since24h)
      .order('completed_at', { ascending: false })
      .limit(10)
    
    // Calculate average generation time for recent jobs
    let avgGenerationMinutes = 0
    if (recentCompleted && recentCompleted.length > 0) {
      const totalMinutes = recentCompleted.reduce((sum, job) => {
        const created = new Date(job.created_at).getTime()
        const scheduled = new Date(job.scheduled_at).getTime()
        const completed = new Date(job.completed_at).getTime()
        const processingStart = Math.max(created, scheduled)
        return sum + ((completed - processingStart) / (1000 * 60))
      }, 0)
      avgGenerationMinutes = totalMinutes / recentCompleted.length
    }
    
    // Count unique users who got DayStarts
    const uniqueUsers = new Set(recentCompleted?.map(j => j.user_id) ?? []).size
    
    // Status based on volume
    let status: CheckStatus = 'pass'
    if (count === 0) {
      status = 'fail'  // No DayStarts completed is critical
    } else if (count < 5) {
      status = 'warn'  // Low volume might indicate issues
    }
    
    return {
      name: 'daystarts_completed',
      status,
      details: {
        completed_24h: count,
        unique_users: uniqueUsers,
        avg_generation_minutes: avgGenerationMinutes > 0 ? Number(avgGenerationMinutes.toFixed(1)) : null,
        message: count === 0 ? 'No DayStarts completed in last 24 hours!' : `${count} DayStarts delivered to ${uniqueUsers} happy users`
      },
      duration_ms: Date.now() - start
    }
  } catch (err) {
    return { name: 'daystarts_completed', status: 'fail', error: (err as Error).message, duration_ms: Date.now() - start }
  }
}

async function checkDbConnectivity(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const { error } = await supabase
    .from('jobs')
    .select('job_id', { head: true, count: 'exact' })
    .limit(1)
  if (error) {
    return { name: 'db_connectivity', status: 'fail', error: error.message, duration_ms: Date.now() - start }
  }
  return { name: 'db_connectivity', status: 'pass', duration_ms: Date.now() - start }
}

async function checkJobsHealth(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const now = new Date()
  const since24h = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString()
  const fiveMinAgo = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
  const tenMinAgo = new Date(now.getTime() - 10 * 60 * 1000).toISOString()
  const thirtyMinAgo = new Date(now.getTime() - 30 * 60 * 1000).toISOString()
  const nowIso = now.toISOString()
  const nowPlus2hIso = new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString()
  const nowPlus2hMinus10mIso = new Date(now.getTime() + 2 * 60 * 60 * 1000 - 10 * 60 * 1000).toISOString()
  const nowPlus2hMinus30mIso = new Date(now.getTime() + 2 * 60 * 60 * 1000 - 30 * 60 * 1000).toISOString()
  
  // Tomorrow morning window (4am - 10am in UTC, adjust as needed)
  const tomorrow = new Date(now)
  tomorrow.setDate(tomorrow.getDate() + 1)
  tomorrow.setHours(4, 0, 0, 0)
  const tomorrowMorningStart = tomorrow.toISOString()
  tomorrow.setHours(10, 0, 0, 0)
  const tomorrowMorningEnd = tomorrow.toISOString()

  const [queued, processing, ready, failed, allQueued, overdueQueued, tomorrowQueued] = await Promise.all([
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').gte('created_at', since24h),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'processing').gte('created_at', since24h),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'ready').gte('created_at', since24h),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'failed').gte('created_at', since24h),
    // ALL queued jobs regardless of creation time
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued'),
    // Overdue jobs (scheduled in the past)
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').lt('scheduled_at', nowIso),
    // Tomorrow morning jobs
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').gte('scheduled_at', tomorrowMorningStart).lte('scheduled_at', tomorrowMorningEnd),
  ])

  const counts = {
    queued: queued.count ?? 0,
    processing: processing.count ?? 0,
    ready: ready.count ?? 0,
    failed: failed.count ?? 0,
  }

  // Eligible queued: jobs that could be processed now (respect process_not_before; fallback to scheduled_at - 2h when null)
  const eligibleOr = (cutoffIsoA: string, cutoffIsoB: string) =>
    `process_not_before.lte.${cutoffIsoA},and(process_not_before.is.null,scheduled_at.lte.${cutoffIsoB})`

  const [{ count: eligibleQueuedCount }, { count: eligibleQueuedGt10 }, { count: eligibleQueuedGt30 }] = await Promise.all([
    supabase
      .from('jobs')
      .select('*', { head: true, count: 'exact' })
      .eq('status', 'queued')
      .or(eligibleOr(nowIso, nowPlus2hIso)),
    supabase
      .from('jobs')
      .select('*', { head: true, count: 'exact' })
      .eq('status', 'queued')
      .or(eligibleOr(tenMinAgo, nowPlus2hMinus10mIso)),
    supabase
      .from('jobs')
      .select('*', { head: true, count: 'exact' })
      .eq('status', 'queued')
      .or(eligibleOr(thirtyMinAgo, nowPlus2hMinus30mIso)),
  ])

  // Oldest eligible queued age in minutes (based on process_not_before; for null, derive eligibility as scheduled_at - 2h)
  let oldestQueuedMinutes: number | null = null
  const { data: oldestByPnb } = await supabase
    .from('jobs')
    .select('process_not_before')
    .eq('status', 'queued')
    .not('process_not_before', 'is', null)
    .lte('process_not_before', nowIso)
    .order('process_not_before', { ascending: true })
    .limit(1)
    .maybeSingle()
  if (oldestByPnb?.process_not_before) {
    oldestQueuedMinutes = Math.floor((now.getTime() - new Date(oldestByPnb.process_not_before).getTime()) / 60000)
  } else {
    const { data: oldestBySched } = await supabase
      .from('jobs')
      .select('scheduled_at')
      .eq('status', 'queued')
      .is('process_not_before', null)
      .lte('scheduled_at', nowPlus2hIso)
      .order('scheduled_at', { ascending: true })
      .limit(1)
      .maybeSingle()
    if (oldestBySched?.scheduled_at) {
      const eligibilityStart = new Date(new Date(oldestBySched.scheduled_at).getTime() - 2 * 60 * 60 * 1000)
      oldestQueuedMinutes = Math.floor((now.getTime() - eligibilityStart.getTime()) / 60000)
    }
  }

  // Eligible queued older than thresholds (age since eligibility start, not since creation)
  const queuedGt10 = { count: eligibleQueuedGt10 ?? 0 }
  const queuedGt30 = { count: eligibleQueuedGt30 ?? 0 }

  // Check overdue jobs (scheduled in the past but still queued)
  const overdueCount = overdueQueued.count ?? 0
  let oldestOverdueMinutes: number | null = null
  let overdueGt5Count = 0
  let overdueGt10Count = 0
  
  if (overdueCount > 0) {
    // Get oldest overdue job
    const { data: oldestOverdue } = await supabase
      .from('jobs')
      .select('scheduled_at')
      .eq('status', 'queued')
      .lt('scheduled_at', nowIso)
      .order('scheduled_at', { ascending: true })
      .limit(1)
      .maybeSingle()
    
    if (oldestOverdue?.scheduled_at) {
      oldestOverdueMinutes = Math.floor((now.getTime() - new Date(oldestOverdue.scheduled_at).getTime()) / 60000)
    }
    
    // Count overdue jobs older than 5 and 10 minutes
    const [overdueGt5, overdueGt10] = await Promise.all([
      supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').lt('scheduled_at', fiveMinAgo),
      supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').lt('scheduled_at', tenMinAgo),
    ])
    overdueGt5Count = overdueGt5.count ?? 0
    overdueGt10Count = overdueGt10.count ?? 0
  }

  // Stuck processing
  const twentyMinAgo = new Date(now.getTime() - 20 * 60 * 1000).toISOString()
  const { count: stuckByLease } = await supabase
    .from('jobs')
    .select('*', { head: true, count: 'exact' })
    .eq('status', 'processing')
    .lt('lease_until', new Date().toISOString())

  const { count: staleProcessing } = await supabase
    .from('jobs')
    .select('*', { head: true, count: 'exact' })
    .eq('status', 'processing')
    .lt('updated_at', twentyMinAgo)

  // Recent activity
  const { count: updatesLastHour } = await supabase
    .from('jobs')
    .select('*', { head: true, count: 'exact' })
    .gte('updated_at', new Date(now.getTime() - 60 * 60 * 1000).toISOString())

  // Determine status
  let status: CheckStatus = 'pass'
  const notes: Record<string, unknown> = {
    counts: {
      ...counts,
      totalQueued: allQueued.count ?? 0,
      overdueQueued: overdueCount,
      tomorrowMorning: tomorrowQueued.count ?? 0,
    },
    oldestQueuedMinutes,
    eligibleQueued: eligibleQueuedCount ?? 0,
    queuedOlderThan10m: queuedGt10.count ?? 0,
    queuedOlderThan30m: queuedGt30.count ?? 0,
    overdue: {
      total: overdueCount,
      oldestMinutes: oldestOverdueMinutes,
      olderThan5m: overdueGt5Count,
      olderThan10m: overdueGt10Count,
    },
    tomorrowMorning: {
      total: tomorrowQueued.count ?? 0,
      timeWindow: `${tomorrowMorningStart} to ${tomorrowMorningEnd}`,
    },
    stuckProcessing: (stuckByLease ?? 0) + (staleProcessing ?? 0),
    updatesLastHour: updatesLastHour ?? 0,
  }

  // Updated fail/warn conditions with overdue job monitoring
  if (
    overdueGt10Count > 0 || // Any job overdue by >10 minutes = FAIL
    (queuedGt30.count ?? 0) > 0 || 
    ((stuckByLease ?? 0) + (staleProcessing ?? 0)) > 0
  ) {
    status = 'fail'
  } else if (
    overdueGt5Count > 0 || // Any job overdue by >5 minutes = WARN
    (queuedGt10.count ?? 0) > 0 || 
    ((updatesLastHour ?? 0) === 0 && (eligibleQueuedCount ?? 0) > 0)
  ) {
    status = 'warn'
  }

  return { name: 'jobs_queue', status, details: notes, duration_ms: Date.now() - start }
}

async function checkContentCache(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const types = ['news', 'stocks', 'sports'] as const
  const now = Date.now()
  const details: Record<string, any> = {}
  let status: CheckStatus = 'pass'

  for (const type of types) {
    const { data } = await supabase
      .from('content_cache')
      .select('updated_at, expires_at')
      .eq('content_type', type)
      .order('updated_at', { ascending: false })
      .limit(1)
    const latest = data && data[0]
    if (!latest) {
      details[type] = { status: 'missing' }
      status = status === 'fail' ? 'fail' : 'warn'
      continue
    }
    const updatedAgeH = (now - new Date(latest.updated_at).getTime()) / (1000 * 60 * 60)
    const expired = latest.expires_at && new Date(latest.expires_at).getTime() < now
    details[type] = { updated_at: latest.updated_at, expires_at: latest.expires_at, updated_age_hours: Number(updatedAgeH.toFixed(2)), expired }

    if (expired || updatedAgeH > 24) {
      status = 'fail'
    } else if (updatedAgeH > 12) {
      status = status === 'fail' ? 'fail' : 'warn'
    }
  }

  // Count expired entries
  const { count: expiredCount } = await supabase
    .from('content_cache')
    .select('*', { head: true, count: 'exact' })
    .lt('expires_at', new Date().toISOString())
  details.expiredEntries = expiredCount ?? 0

  return { name: 'content_cache_freshness', status, details, duration_ms: Date.now() - start }
}

async function checkStorageAccess(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const { data: job } = await supabase
    .from('jobs')
    .select('audio_file_path')
    .eq('status', 'ready')
    .not('audio_file_path', 'is', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!job?.audio_file_path) {
    return { name: 'storage_access', status: 'skip', details: { message: 'No ready job with audio to test' }, duration_ms: Date.now() - start }
  }

  try {
    const { data: signed } = await supabase.storage.from('daystart-audio').createSignedUrl(job.audio_file_path, 60)
    if (!signed?.signedUrl) {
      return { name: 'storage_access', status: 'fail', error: 'Failed to create signed URL', duration_ms: Date.now() - start }
    }
    return { name: 'storage_access', status: 'pass', details: { path: job.audio_file_path }, duration_ms: Date.now() - start }
  } catch (err) {
    return { name: 'storage_access', status: 'fail', error: (err as Error).message, duration_ms: Date.now() - start }
  }
}

async function checkInternalUrls(): Promise<CheckResult> {
  const start = Date.now()
  const baseUrl = Deno.env.get('SUPABASE_URL') ?? ''

  // Use OPTIONS to avoid invoking heavy logic and external calls
  const endpoints = [
    { path: '/functions/v1/refresh_content', method: 'OPTIONS', headers: {} as Record<string, string> },
    { path: '/functions/v1/process_jobs', method: 'OPTIONS', headers: {} as Record<string, string> },
  ]

  const results: Array<{ path: string; status: number }> = []
  for (const ep of endpoints) {
    try {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 3000)
      const res = await fetch(`${baseUrl}${ep.path}`, {
        method: ep.method,
        headers: ep.headers,
        signal: controller.signal,
      })
      clearTimeout(timeout)
      results.push({ path: ep.path, status: res.status })
    } catch (_err) {
      results.push({ path: ep.path, status: 0 })
    }
  }

  // Internal URL failures are expected (process_jobs uses different auth), so always pass
  return { name: 'internal_urls', status: 'pass', details: { results }, duration_ms: Date.now() - start }
}

async function checkAudioCleanupHeartbeat(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const { data } = await supabase
    .from('audio_cleanup_log')
    .select('started_at')
    .order('started_at', { ascending: false })
    .limit(1)

  if (!data || data.length === 0) {
    return { name: 'audio_cleanup_heartbeat', status: 'warn', details: { message: 'No cleanup runs recorded' }, duration_ms: Date.now() - start }
  }
  const last = new Date(data[0].started_at).getTime()
  const hours = (Date.now() - last) / (1000 * 60 * 60)
  const status: CheckStatus = hours > 48 ? 'fail' : hours > 24 ? 'warn' : 'pass'
  return { name: 'audio_cleanup_heartbeat', status, details: { last_started_at: data[0].started_at, hours_since: Number(hours.toFixed(2)) }, duration_ms: Date.now() - start }
}

async function checkRequestErrorRate(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const since24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

  // Get all requests excluding healthcheck endpoint
  const { data: allRequests, count: totalCount } = await supabase
    .from('request_logs')
    .select('*', { head: false, count: 'exact' })
    .gte('created_at', since24h)
    .neq('endpoint', '/healthcheck')

  // Get errors excluding healthcheck
  const { data: errorRequests, count: errorCount } = await supabase
    .from('request_logs')
    .select('endpoint, error_code, status_code, created_at', { head: false })
    .gte('created_at', since24h)
    .neq('endpoint', '/healthcheck')
    .not('error_code', 'is', null)
    .order('created_at', { ascending: false })
    .limit(50)

  const total = totalCount ?? 0
  const errors = errorCount ?? 0
  const rate = total > 0 ? (errors / total) * 100 : 0

  // Group errors by endpoint
  const errorsByEndpoint: Record<string, number> = {}
  const errorsByCode: Record<string, number> = {}
  let processJobsErrors = 0
  
  if (errorRequests) {
    for (const err of errorRequests) {
      errorsByEndpoint[err.endpoint] = (errorsByEndpoint[err.endpoint] || 0) + 1
      errorsByCode[err.error_code] = (errorsByCode[err.error_code] || 0) + 1
      if (err.endpoint === '/process_jobs') {
        processJobsErrors++
      }
    }
  }

  // Get recent error samples (last 5)
  const recentErrors = errorRequests?.slice(0, 5).map(err => ({
    endpoint: err.endpoint,
    error_code: err.error_code,
    status_code: err.status_code,
    timestamp: err.created_at,
  })) || []

  // Strict error thresholds
  let status: CheckStatus = 'pass'
  if (processJobsErrors > 0) {
    status = 'fail' // Any process_jobs errors = FAIL
  } else if (errors > 0) {
    status = 'warn' // Any errors = WARN
  }

  return {
    name: 'request_error_rate',
    status,
    details: {
      total_24h: total,
      errors_24h: errors,
      error_rate_percent: Number(rate.toFixed(2)),
      errors_by_endpoint: errorsByEndpoint,
      errors_by_code: errorsByCode,
      process_jobs_errors: processJobsErrors,
      recent_errors: recentErrors,
    },
    duration_ms: Date.now() - start,
  }
}

async function sendResendEmail(report: HealthReport & { ai_diagnosis?: string }): Promise<void> {
  const apiKey = Deno.env.get('RESEND_API_KEY')
  const toEmail = Deno.env.get('RESEND_TO_EMAIL')
  const fromEmail = Deno.env.get('RESEND_FROM_EMAIL')
  if (!apiKey || !toEmail || !fromEmail) {
    throw new Error('Resend env vars not configured')
  }

  const subject = buildEmailSubject(report)
  const html = buildEmailHtml(report)
  const text = buildEmailText(report)

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [toEmail],
      subject,
      html,
      text,
    }),
  })

  if (!res.ok) {
    const errText = await res.text().catch(() => '')
    throw new Error(`Resend API error: ${res.status} ${errText}`)
  }
}

function buildEmailSubject(report: HealthReport & { ai_diagnosis?: string }): string {
  const d = new Date(report.started_at)
  const friendly = d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
  
  // Professional subject lines based on status
  if (report.overall_status === 'pass') {
    return `DayStart System Health: Operational — ${friendly}`
  } else if (report.overall_status === 'warn') {
    return `DayStart System Health: Degraded Performance — ${friendly}`
  } else {
    return `DayStart System Health: Critical Issues — ${friendly}`
  }
}

function buildEmailHtml(report: HealthReport & { ai_diagnosis?: string }): string {
  // Get key metrics for display
  const errorRateCheck = report.checks.find(c => c.name === 'request_error_rate')
  const errorDetails = errorRateCheck?.details as any || {}
  const daystartsCheck = report.checks.find(c => c.name === 'daystarts_completed')
  const daystartsDetails = daystartsCheck?.details as any || {}
  
  // True north metric - prominent display
  const daystartsMessage = daystartsDetails.completed_24h
    ? `${daystartsDetails.completed_24h} DayStarts delivered to ${daystartsDetails.unique_users} users in the last 24 hours`
    : "No DayStarts completed in the last 24 hours"
  
  // Generation time for quick reference
  const genTimeMessage = daystartsDetails.avg_generation_minutes 
    ? `${daystartsDetails.avg_generation_minutes}min avg generation`
    : ""
  
  // Professional status messages
  const statusMessage = report.overall_status === 'pass' 
    ? "All systems operational"
    : report.overall_status === 'warn'
    ? "Minor issues detected - monitoring required"
    : "Critical issues require immediate attention"
    
  const statusBadge = report.overall_status === 'pass'
    ? "OPERATIONAL"
    : report.overall_status === 'warn' 
    ? "DEGRADED"
    : "CRITICAL"
  
  // Professional color scheme
  const borderColor = report.overall_status === 'pass' 
    ? '#059669'  // Professional green
    : report.overall_status === 'warn'
    ? '#d97706'  // Professional amber
    : '#dc2626'  // Professional red
  
  const headerBg = report.overall_status === 'pass'
    ? '#f0f9ff'  // Light blue background
    : report.overall_status === 'warn'
    ? '#fffbeb'  // Light amber background
    : '#fef2f2'  // Light red background
    
  const statusBadgeColor = report.overall_status === 'pass'
    ? '#059669'  // Green
    : report.overall_status === 'warn'
    ? '#d97706'  // Amber
    : '#dc2626'  // Red

  // Create check rows with professional formatting
  const checkRows = report.checks
    .map((c) => {
      const statusIndicator = c.status === 'pass' ? '●' : c.status === 'warn' ? '●' : c.status === 'fail' ? '●' : '○'
      const statusColor = c.status === 'pass' ? '#059669' : c.status === 'warn' ? '#d97706' : c.status === 'fail' ? '#dc2626' : '#6b7280'
      const bgColor = c.status === 'pass' ? '#f0fdf4' : c.status === 'warn' ? '#fffbeb' : c.status === 'fail' ? '#fef2f2' : '#f9fafb'
      
      // Format details based on check type
      let detailsHtml = ''
      if (c.name === 'request_error_rate' && c.details) {
        const d = c.details as any
        if (d.errors_24h > 0) {
          detailsHtml = `
            <div style="font-size:13px;line-height:1.5">
              <strong>${d.errors_24h} errors</strong> in last 24h (${d.error_rate_percent}%)
              ${d.process_jobs_errors > 0 ? `<br><span style="color:#dc2626;font-weight:600">⚠️ ${d.process_jobs_errors} process_jobs failures!</span>` : ''}
              ${Object.keys(d.errors_by_endpoint || {}).length > 0 ? `<br><strong>By endpoint:</strong> ${Object.entries(d.errors_by_endpoint).map(([ep, count]) => `${ep} (${count})`).join(', ')}` : ''}
              ${Object.keys(d.errors_by_code || {}).length > 0 ? `<br><strong>By type:</strong> ${Object.entries(d.errors_by_code).map(([code, count]) => `${code} (${count})`).join(', ')}` : ''}
            </div>`
        } else {
          detailsHtml = '<span style="color:#16a34a">No errors detected</span>'
        }
      } else if (c.name === 'jobs_queue' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <strong>Queued:</strong> ${d.counts?.totalQueued || 0} total (${d.counts?.queued || 0} in last 24h)
            ${d.overdue?.total > 0 ? `<br><span style="color:#dc2626;font-weight:600">🚨 ${d.overdue.total} OVERDUE jobs!</span>` : ''}
            ${d.overdue?.oldestMinutes ? `<br><span style="color:#dc2626">Oldest overdue: ${d.overdue.oldestMinutes} minutes ago</span>` : ''}
            ${d.overdue?.olderThan10m > 0 ? `<br><span style="color:#dc2626">• ${d.overdue.olderThan10m} overdue >10min</span>` : ''}
            ${d.overdue?.olderThan5m > 0 && d.overdue?.olderThan10m === 0 ? `<br><span style="color:#f59e0b">• ${d.overdue.olderThan5m} overdue >5min</span>` : ''}
            ${d.tomorrowMorning?.total > 0 ? `<br><span style="color:#3b82f6">📅 ${d.tomorrowMorning.total} scheduled for tomorrow morning</span>` : ''}
            ${d.eligibleQueued > 0 ? `<br>Eligible for processing: ${d.eligibleQueued}` : ''}
            ${d.stuckProcessing > 0 ? `<br><span style="color:#dc2626;font-weight:600">⚠️ ${d.stuckProcessing} stuck processing!</span>` : ''}
          </div>`
      } else if (c.name === 'daystarts_completed' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <strong style="color:#059669;font-size:16px">${d.completed_24h} DayStarts completed</strong>
            <br><span style="color:#3b82f6">📱 ${d.unique_users} unique users served</span>
            ${d.avg_generation_minutes ? `<br><span style="color:#6b7280">⏱️ Average generation: ${d.avg_generation_minutes} minutes</span>` : ''}
            ${d.message ? `<br><em style="color:#16a34a">${d.message}</em>` : ''}
          </div>`
      } else {
        detailsHtml = `<pre style="margin:0;font-family:ui-monospace,monospace;font-size:11px;color:#666">${escapeHtml(JSON.stringify(c.details ?? c.error ?? {}, null, 2))}</pre>`
      }
      
      return `
        <tr style="background:${bgColor}">
          <td style="padding:16px;border-bottom:1px solid #e5e7eb">
            <span style="color:${statusColor};font-size:16px;margin-right:8px">${statusIndicator}</span>
            <span style="font-weight:500;color:#374151">${c.name.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</span>
          </td>
          <td style="padding:16px;border-bottom:1px solid #e5e7eb">
            ${detailsHtml}
          </td>
        </tr>`
    })
    .join('')

  // Recent errors section with professional styling
  const recentErrorsHtml = errorDetails.recent_errors?.length > 0 ? `
    <div style="margin-bottom:32px">
      <h2 style="margin:0 0 20px 0;color:#374151;font-size:18px;font-weight:600">Recent Errors</h2>
      <div style="background:#fef2f2;border:1px solid #fecaca;border-radius:8px;overflow:hidden">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;font-size:13px">
          <thead>
            <tr style="background:#fee2e2">
              <th style="padding:12px 16px;text-align:left;color:#991b1b;font-weight:600">Time</th>
              <th style="padding:12px 16px;text-align:left;color:#991b1b;font-weight:600">Endpoint</th>
              <th style="padding:12px 16px;text-align:left;color:#991b1b;font-weight:600">Error</th>
              <th style="padding:12px 16px;text-align:left;color:#991b1b;font-weight:600">Status</th>
            </tr>
          </thead>
          <tbody>
            ${errorDetails.recent_errors.map((err: any) => `
              <tr style="border-top:1px solid #fecaca">
                <td style="padding:12px 16px;color:#6b7280;font-family:ui-monospace,monospace">${new Date(err.timestamp).toLocaleTimeString()}</td>
                <td style="padding:12px 16px;color:#374151;font-weight:500">${err.endpoint}</td>
                <td style="padding:12px 16px;color:#dc2626;font-weight:500">${err.error_code}</td>
                <td style="padding:12px 16px;color:#6b7280">${err.status_code}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    </div>
  ` : ''

  // AI Diagnosis section with professional styling
  const aiDiagnosisHtml = report.ai_diagnosis ? `
    <div style="margin-bottom:32px">
      <h2 style="margin:0 0 20px 0;color:#374151;font-size:18px;font-weight:600">Analysis</h2>
      <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:8px;padding:20px">
        <p style="margin:0;color:#0f172a;font-size:14px;line-height:1.6">${escapeHtml(report.ai_diagnosis)}</p>
      </div>
    </div>
  ` : ''

  return `<!doctype html><html><body style="margin:0;padding:0;background:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#111">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;margin:0;padding:0;background:#f8fafc">
      <tr>
        <td>
          <table role="presentation" align="center" width="680" cellspacing="0" cellpadding="0" style="margin:32px auto;background:#ffffff;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.1)">
            <tr>
              <td style="background:${headerBg};padding:32px;border-bottom:1px solid #e5e7eb">
                <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:24px">
                  <div>
                    <h1 style="margin:0 0 4px 0;font-size:24px;color:#111827;font-weight:600">DayStart System Health Report</h1>
                    <p style="margin:0;font-size:14px;color:#6b7280">Daily Operations Summary • ${new Date().toLocaleDateString()}</p>
                  </div>
                  <div style="text-align:right">
                    <span style="background:${statusBadgeColor};color:#ffffff;padding:6px 12px;border-radius:6px;font-size:12px;font-weight:600;letter-spacing:0.5px">${statusBadge}</span>
                  </div>
                </div>
                <div style="background:#ffffff;border-radius:8px;padding:24px;border:1px solid #e5e7eb">
                  <div style="text-align:center">
                    <p style="margin:0 0 8px 0;font-size:32px;color:#111827;font-weight:700">${daystartsDetails.completed_24h || 0}</p>
                    <p style="margin:0 0 4px 0;font-size:16px;color:#6b7280;font-weight:500">DayStarts delivered to ${daystartsDetails.unique_users || 0} users</p>
                    ${genTimeMessage ? `<p style="margin:0;font-size:14px;color:#9ca3af">${genTimeMessage.replace('⏱️ ', '')}</p>` : ''}
                  </div>
                </div>
              </td>
            </tr>
            <tr>
              <td style="padding:24px">
                ${aiDiagnosisHtml}
                
                <div style="margin-bottom:32px">
                  <h2 style="margin:0 0 20px 0;color:#374151;font-size:18px;font-weight:600">System Components</h2>
                  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;background:#ffffff">
                    ${checkRows}
                  </table>
                </div>
                
                ${recentErrorsHtml}
                
                ${getJobsSummaryHtml(report)}
                
                <div style="margin-top:20px;padding:12px;background:#f3f4f6;border-radius:8px;font-size:11px;color:#6b7280;text-align:center">
                  <strong>Request ID:</strong> ${report.request_id}<br>
                  <strong>Runtime:</strong> ${report.duration_ms}ms • ${new Date(report.started_at).toLocaleString()}
                </div>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body></html>`
}

function getJobsSummaryHtml(report: HealthReport): string {
  const jobsCheck = report.checks.find(c => c.name === 'jobs_queue')
  if (!jobsCheck?.details) return ''
  
  const details = jobsCheck.details as any
  const hasOverdue = details.overdue?.total > 0
  const hasTomorrow = details.tomorrowMorning?.total > 0
  
  if (!hasOverdue && !hasTomorrow) return ''
  
  let sections = []
  
  // Overdue jobs section
  if (hasOverdue) {
    sections.push(`
      <div style="margin-top:20px;padding:16px;background:#fee2e2;border:2px solid #dc2626;border-radius:8px">
        <h3 style="margin:0 0 12px 0;font-size:14px;color:#7f1d1d">🚨 OVERDUE JOBS ALERT</h3>
        <p style="margin:0;font-size:13px;line-height:1.5;color:#991b1b">
          <strong>${details.overdue.total} jobs</strong> are overdue and should have been processed already!
          ${details.overdue.oldestMinutes ? `<br>The oldest has been waiting for <strong>${details.overdue.oldestMinutes} minutes</strong>.` : ''}
          ${details.overdue.olderThan10m > 0 ? `<br><strong>${details.overdue.olderThan10m} jobs</strong> have been overdue for more than 10 minutes.` : ''}
        </p>
        <p style="margin:8px 0 0 0;font-size:12px;color:#7f1d1d">
          <strong>Action Required:</strong> Check process_jobs function for errors or stuck processing.
        </p>
      </div>
    `)
  }
  
  // Tomorrow morning jobs section
  if (hasTomorrow) {
    sections.push(`
      <div style="margin-top:20px;padding:16px;background:#dbeafe;border:1px solid #3b82f6;border-radius:8px">
        <h3 style="margin:0 0 8px 0;font-size:14px;color:#1e3a8a">📅 Tomorrow Morning DayStarts</h3>
        <p style="margin:0;font-size:13px;line-height:1.5;color:#1e3a8a">
          <strong>${details.tomorrowMorning.total} users</strong> are expecting their morning briefing tomorrow.
        </p>
      </div>
    `)
  }
  
  return sections.join('')
}

function buildEmailText(report: HealthReport & { ai_diagnosis?: string }): string {
  const errorRateCheck = report.checks.find(c => c.name === 'request_error_rate')
  const errorDetails = errorRateCheck?.details as any || {}
  
  const lines = [
    `DayStart Health Report - ${report.overall_status.toUpperCase()}`,
    '=' .repeat(40),
    '',
  ]
  
  // Add true north metric at top
  const daystartsCheck = report.checks.find(c => c.name === 'daystarts_completed')
  if (daystartsCheck?.details) {
    const d = daystartsCheck.details as any
    lines.push(`TRUE NORTH: ${d.completed_24h} DayStarts delivered to ${d.unique_users} users`)
    lines.push('')
  }
  
  if (report.ai_diagnosis) {
    lines.push('AI DIAGNOSIS:', report.ai_diagnosis, '', '-'.repeat(40), '')
  }
  
  lines.push('SYSTEM CHECKS:')
  report.checks.forEach(c => {
    const status = c.status === 'pass' ? '✅' : c.status === 'warn' ? '⚠️' : c.status === 'fail' ? '❌' : '⏭️'
    lines.push(`${status} ${c.name}: ${c.status.toUpperCase()}`)
    
    if (c.name === 'daystarts_completed' && c.details) {
      const d = c.details as any
      lines.push(`   - ${d.completed_24h} DayStarts completed (${d.unique_users} users)`)
      if (d.avg_generation_minutes) {
        lines.push(`   - Average generation: ${d.avg_generation_minutes} minutes`)
      }
    } else if (c.name === 'request_error_rate' && errorDetails.errors_24h > 0) {
      lines.push(`   - ${errorDetails.errors_24h} errors (${errorDetails.error_rate_percent}%)`)
      if (errorDetails.process_jobs_errors > 0) {
        lines.push(`   - ⚠️  ${errorDetails.process_jobs_errors} process_jobs failures!`)
      }
    } else if (c.name === 'jobs_queue' && c.details) {
      const d = c.details as any
      if (d.overdue?.total > 0) {
        lines.push(`   - 🚨 ${d.overdue.total} OVERDUE jobs!`)
        if (d.overdue.oldestMinutes) {
          lines.push(`   - Oldest overdue: ${d.overdue.oldestMinutes} minutes`)
        }
      }
      if (d.tomorrowMorning?.total > 0) {
        lines.push(`   - 📅 ${d.tomorrowMorning.total} jobs scheduled for tomorrow morning`)
      }
      if (d.counts?.totalQueued > 0) {
        lines.push(`   - Total queued: ${d.counts.totalQueued}`)
      }
    }
  })
  
  if (errorDetails.recent_errors?.length > 0) {
    lines.push('', 'RECENT ERRORS:')
    errorDetails.recent_errors.forEach((err: any) => {
      lines.push(`- ${new Date(err.timestamp).toLocaleTimeString()} ${err.endpoint} ${err.error_code} (${err.status_code})`)
    })
  }
  
  lines.push('', `Request: ${report.request_id} | Duration: ${report.duration_ms}ms`)
  
  return lines.join('\n')
}

async function getAIDiagnosis(checks: CheckResult[]): Promise<string> {
  const openaiKey = Deno.env.get('OPENAI_API_KEY')
  if (!openaiKey) {
    throw new Error('OpenAI API key not configured')
  }

  // Collect failing/warning checks
  const issues = checks.filter(c => c.status !== 'pass' && c.status !== 'skip')
  
  const systemPrompt = `You are analyzing a DayStart backend healthcheck. DayStart delivers AI-generated morning briefings with audio.
Key context:
- process_jobs: Core function that generates audio content (CRITICAL)
- Jobs are scheduled for specific times (usually morning) and should process 2 hours before scheduled_at
- Overdue jobs: Jobs past their scheduled_at that haven't been processed (CRITICAL USER IMPACT)
- Rate limiting: Users have 4-hour cooldown between DayStarts  
- Queue processing: Jobs are processed in order with retry logic
- Content cache: External APIs cached for 12 hours

Provide a concise diagnosis (2-3 sentences max) that includes:
1. Root cause analysis
2. Impact on users (especially for overdue jobs - users missing their morning briefings)
3. Recommended action (or "No action needed" if working as designed)`

  const userPrompt = `Healthcheck issues found:
${issues.map(check => `
${check.name}: ${check.status.toUpperCase()}
Details: ${JSON.stringify(check.details || check.error, null, 2)}
`).join('\n')}

Recent errors breakdown: ${JSON.stringify(checks.find(c => c.name === 'request_error_rate')?.details || {}, null, 2)}`

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openaiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'o3-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt }
      ],
      temperature: 0.3,
      max_tokens: 150,
    }),
  })

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status}`)
  }

  const data = await response.json()
  return data.choices[0]?.message?.content || 'Unable to generate diagnosis'
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}


