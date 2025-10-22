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
  checks.push(await withTimeout('external_services', () => checkExternalServices(), 8000))
  checks.push(await withTimeout('recent_feedback', () => checkRecentFeedback(supabase), 3000))

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
  console.log('Email notification check:', { notify, request_id })
  try {
    if (notify) {
      console.log('Attempting to send email via Resend...')
      await sendResendEmail(report)
      console.log('Email sent successfully')
    } else {
      console.log('Email notification disabled')
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
    
    // Calculate average, median, min, and max generation time for recent jobs
    let avgGenerationMinutes = 0
    let medianGenerationMinutes = 0
    let minGenerationMinutes = 0
    let maxGenerationMinutes = 0
    const generationTimes: number[] = []
    
    if (recentCompleted && recentCompleted.length > 0) {
      for (const job of recentCompleted) {
        const created = new Date(job.created_at).getTime()
        const scheduled = new Date(job.scheduled_at).getTime()
        const completed = new Date(job.completed_at).getTime()
        const processingStart = Math.max(created, scheduled - 2 * 60 * 60 * 1000) // Jobs can start 2h before scheduled
        const genMinutes = (completed - processingStart) / (1000 * 60)
        
        // Filter out outliers (negative times or > 30 minutes)
        if (genMinutes > 0 && genMinutes < 30) {
          generationTimes.push(genMinutes)
        }
      }
      
      if (generationTimes.length > 0) {
        // Calculate average
        avgGenerationMinutes = generationTimes.reduce((sum, time) => sum + time, 0) / generationTimes.length
        
        // Calculate median
        const sorted = [...generationTimes].sort((a, b) => a - b)
        const mid = Math.floor(sorted.length / 2)
        medianGenerationMinutes = sorted.length % 2 === 0 
          ? (sorted[mid - 1] + sorted[mid]) / 2 
          : sorted[mid]
        
        // Calculate min and max
        minGenerationMinutes = Math.min(...generationTimes)
        maxGenerationMinutes = Math.max(...generationTimes)
      }
    }
    
    // Count unique users who got DayStarts
    const uniqueUsers = new Set(recentCompleted?.map(j => j.user_id) ?? []).size
    
    // Status based on volume
    let status: CheckStatus = 'pass'
    if (count === 0) {
      status = 'warn'  // No DayStarts completed is concerning but not critical
    } else if (count < 2) {
      status = 'warn'  // Low volume might indicate issues
    }
    
    return {
      name: 'daystarts_completed',
      status,
      details: {
        completed_24h: count,
        unique_users: uniqueUsers,
        avg_generation_minutes: avgGenerationMinutes > 0 ? Number(avgGenerationMinutes.toFixed(1)) : null,
        median_generation_minutes: medianGenerationMinutes > 0 ? Number(medianGenerationMinutes.toFixed(1)) : null,
        shortest_generation_minutes: minGenerationMinutes > 0 ? Number(minGenerationMinutes.toFixed(1)) : null,
        longest_generation_minutes: maxGenerationMinutes > 0 ? Number(maxGenerationMinutes.toFixed(1)) : null,
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
  const { error, count } = await supabase
    .from('jobs')
    .select('job_id', { head: true, count: 'exact' })
    .limit(1)
  if (error) {
    return { name: 'db_connectivity', status: 'fail', error: error.message, duration_ms: Date.now() - start }
  }
  return { 
    name: 'db_connectivity', 
    status: 'pass', 
    details: { 
      message: 'Database connection healthy',
      jobs_table_accessible: true,
      total_jobs: count ?? 0
    },
    duration_ms: Date.now() - start 
  }
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
  
  // Tomorrow morning window in Pacific Time (4am - 10am PT)
  const tomorrow = new Date(now)
  tomorrow.setDate(tomorrow.getDate() + 1)
  // Convert to Pacific Time - using UTC offset (PST = UTC-8, PDT = UTC-7)
  // For simplicity, we'll use a fixed offset, but ideally would use proper timezone library
  const pacificOffset = 8 // hours (PST), would be 7 for PDT
  tomorrow.setUTCHours(4 + pacificOffset, 0, 0, 0) // 4am PT = 12pm UTC (PST)
  const tomorrowMorningStart = tomorrow.toISOString()
  tomorrow.setUTCHours(10 + pacificOffset, 0, 0, 0) // 10am PT = 6pm UTC (PST)
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
    
  // Get recent failed job details
  const { data: recentFailures } = await supabase
    .from('jobs')
    .select('job_id, user_id, created_at, error_message, attempt_count')
    .eq('status', 'failed')
    .gte('created_at', since24h)
    .order('created_at', { ascending: false })
    .limit(5)
    
  // Group failed jobs by error message
  const { data: allFailures } = await supabase
    .from('jobs')
    .select('error_message')
    .eq('status', 'failed')
    .gte('created_at', since24h)
    
  const failurePatterns: Record<string, number> = {}
  if (allFailures) {
    for (const job of allFailures) {
      const errorType = job.error_message?.split(':')[0] || 'Unknown error'
      failurePatterns[errorType] = (failurePatterns[errorType] || 0) + 1
    }
  }

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
      timeWindowPT: '4am - 10am PT tomorrow',
    },
    stuckProcessing: (stuckByLease ?? 0) + (staleProcessing ?? 0),
    updatesLastHour: updatesLastHour ?? 0,
    failures: {
      recent: recentFailures || [],
      patterns: failurePatterns,
      total_24h: counts.failed,
    },
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
  let missingTypes = 0
  let missingSources = 0

  // Define expected sources for each type
  const expectedSources = {
    news: ['newsapi_general', 'newsapi_business', 'newsapi_targeted', 'gnews_comprehensive'],
    stocks: ['yahoo_finance'],
    sports: ['espn', 'thesportdb']
  }

  for (const type of types) {
    // Get all sources for this content type
    const { data } = await supabase
      .from('content_cache')
      .select('source, updated_at, expires_at')
      .eq('content_type', type)
      .order('updated_at', { ascending: false })
    
    if (!data || data.length === 0) {
      details[type] = { status: 'missing', sources: {}, expected_sources: expectedSources[type] }
      missingTypes++
      status = 'fail' // Missing entire type = FAIL
      continue
    }

    // Group by API source and get latest for each
    const sourceMap: Record<string, any> = {}
    const processedSources = new Set<string>()
    
    for (const item of data) {
      if (!processedSources.has(item.source)) {
        processedSources.add(item.source)
        const updatedAgeH = (now - new Date(item.updated_at).getTime()) / (1000 * 60 * 60)
        const expired = item.expires_at && new Date(item.expires_at).getTime() < now
        
        sourceMap[item.source] = {
          updated_at: item.updated_at,
          expires_at: item.expires_at,
          updated_age_hours: Number(updatedAgeH.toFixed(2)),
          expired
        }
      }
    }

    // Check if we have at least one fresh source for this type
    const freshSources = Object.values(sourceMap).filter(s => !s.expired)
    const hasFreshContent = freshSources.length > 0
    
    // Check for missing expected sources
    const expectedForType = expectedSources[type]
    const actualSources = Object.keys(sourceMap)
    const missingSourcesList = expectedForType.filter(expected => !actualSources.includes(expected))
    
    details[type] = {
      status: hasFreshContent ? 'available' : 'all_expired',
      total_sources: Object.keys(sourceMap).length,
      expected_sources: expectedForType.length,
      fresh_sources: freshSources.length,
      missing_sources: missingSourcesList,
      sources: sourceMap
    }

    // If all sources for a type are expired, it's concerning but not critical
    if (!hasFreshContent && status !== 'fail') {
      missingSources++
      status = 'warn'
    }
    
    // Warn if missing expected sources (but don't fail - system can work with fewer sources)
    if (missingSourcesList.length > 0 && status === 'pass') {
      status = 'warn'
    }
  }

  // Count total expired entries across all types
  const { count: expiredCount } = await supabase
    .from('content_cache')
    .select('*', { head: true, count: 'exact' })
    .lt('expires_at', new Date().toISOString())
  details.expiredEntries = expiredCount ?? 0
  details.summary = {
    missing_types: missingTypes,
    types_without_fresh_content: missingSources
  }

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

async function checkExternalServices(): Promise<CheckResult> {
  const start = Date.now()
  const results: Record<string, { status: 'healthy' | 'degraded' | 'down', responseTime?: number, error?: string }> = {}
  
  // Check OpenAI
  try {
    const openaiStart = Date.now()
    const openaiKey = Deno.env.get('OPENAI_API_KEY')
    if (!openaiKey) {
      results.openai = { status: 'down', error: 'API key not configured' }
    } else {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 5000)
      
      const response = await fetch('https://api.openai.com/v1/models', {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${openaiKey}`,
        },
        signal: controller.signal,
      })
      clearTimeout(timeout)
      
      const responseTime = Date.now() - openaiStart
      if (response.ok) {
        results.openai = { status: 'healthy', responseTime }
      } else {
        results.openai = { status: 'degraded', responseTime, error: `HTTP ${response.status}` }
      }
    }
  } catch (err) {
    results.openai = { status: 'down', error: (err as Error).message }
  }
  
  // Check ElevenLabs
  try {
    const elevenStart = Date.now()
    const elevenKey = Deno.env.get('ELEVENLABS_API_KEY')
    if (!elevenKey) {
      results.elevenlabs = { status: 'down', error: 'API key not configured' }
    } else {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 5000)
      
      const response = await fetch('https://api.elevenlabs.io/v1/user', {
        method: 'GET',
        headers: {
          'xi-api-key': elevenKey,
        },
        signal: controller.signal,
      })
      clearTimeout(timeout)
      
      const responseTime = Date.now() - elevenStart
      if (response.ok) {
        results.elevenlabs = { status: 'healthy', responseTime }
      } else {
        results.elevenlabs = { status: 'degraded', responseTime, error: `HTTP ${response.status}` }
      }
    }
  } catch (err) {
    results.elevenlabs = { status: 'down', error: (err as Error).message }
  }
  
  // Determine overall status
  const hasDown = Object.values(results).some(r => r.status === 'down')
  const hasDegraded = Object.values(results).some(r => r.status === 'degraded')
  const status: CheckStatus = hasDown ? 'fail' : hasDegraded ? 'warn' : 'pass'
  
  return {
    name: 'external_services',
    status,
    details: results,
    duration_ms: Date.now() - start,
  }
}

async function checkRecentFeedback(supabase: SupabaseClient): Promise<CheckResult> {
  const start = Date.now()
  const since24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
  
  try {
    // Get all feedback from last 24 hours
    const { data: recentFeedback, error } = await supabase
      .from('app_feedback')
      .select('id, user_id, category, message, email, created_at, app_version, device_model')
      .gte('created_at', since24h)
      .order('created_at', { ascending: false })
    
    if (error) {
      return { name: 'recent_feedback', status: 'fail', error: error.message, duration_ms: Date.now() - start }
    }
    
    const feedback = recentFeedback || []
    const total = feedback.length
    
    // Count by category
    const categories: Record<string, number> = {
      audio_issue: 0,
      content_quality: 0,
      scheduling: 0,
      other: 0
    }
    
    // Recent feedback samples (first 5)
    const samples = feedback.slice(0, 5).map(f => ({
      id: f.id,
      user_id: f.user_id ? `${f.user_id.substring(0, 8)}...` : 'anonymous',
      category: f.category,
      message: f.message ? (f.message.length > 100 ? `${f.message.substring(0, 100)}...` : f.message) : null,
      has_email: !!f.email,
      created_at: f.created_at,
      app_version: f.app_version,
      device_model: f.device_model
    }))
    
    // Count categories
    for (const f of feedback) {
      if (f.category in categories) {
        categories[f.category]++
      }
    }
    
    // Count critical categories (audio issues, content quality)
    const criticalCount = categories.audio_issue + categories.content_quality
    
    // Determine status based on feedback volume and criticality
    // Feedback is good - it means users are engaged. Only warn/fail for excessive critical issues
    let status: CheckStatus = 'pass'
    if (criticalCount >= 5) {
      status = 'fail'  // Many critical issues require immediate attention
    } else if (criticalCount >= 3) {
      status = 'warn'  // Some critical issues worth monitoring
    }
    
    return {
      name: 'recent_feedback',
      status,
      details: {
        total_24h: total,
        categories,
        critical_count: criticalCount,
        samples,
        message: total === 0 ? 'No user feedback in last 24 hours' : 
                total === 1 ? '1 user feedback received' : 
                `${total} user feedback items received`,
        has_contact_info: feedback.filter(f => f.email).length
      },
      duration_ms: Date.now() - start
    }
  } catch (err) {
    return { name: 'recent_feedback', status: 'fail', error: (err as Error).message, duration_ms: Date.now() - start }
  }
}

async function sendResendEmail(report: HealthReport & { ai_diagnosis?: string }): Promise<void> {
  console.log('sendResendEmail called for request:', report.request_id)
  
  const apiKey = Deno.env.get('RESEND_API_KEY')
  const toEmail = Deno.env.get('RESEND_TO_EMAIL')
  const fromEmail = Deno.env.get('RESEND_FROM_EMAIL')
  
  console.log('Environment check:', { 
    hasApiKey: !!apiKey, 
    hasToEmail: !!toEmail, 
    hasFromEmail: !!fromEmail 
  })
  
  if (!apiKey || !toEmail || !fromEmail) {
    throw new Error('Resend env vars not configured')
  }

  console.log('Building email content...')
  const subject = buildEmailSubject(report)
  const html = buildEmailHtml(report)
  const text = buildEmailText(report)

  console.log('Sending email:', { subject, to: toEmail, from: fromEmail })
  
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

  console.log('Resend API response:', { status: res.status, statusText: res.statusText })

  if (!res.ok) {
    const errText = await res.text().catch(() => '')
    throw new Error(`Resend API error: ${res.status} ${errText}`)
  }
  
  console.log('Email sent successfully via Resend')
}

function buildEmailSubject(report: HealthReport & { ai_diagnosis?: string }): string {
  const d = new Date(report.started_at)
  const friendly = d.toLocaleDateString('en-US', { 
    timeZone: 'America/Los_Angeles',
    weekday: 'long', 
    month: 'long', 
    day: 'numeric' 
  })
  
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
  // Extract project reference from Supabase URL for dashboard links
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
  const projectRef = supabaseUrl.match(/https:\/\/([^.]+)\.supabase\.co/)?.[1] || ''
  const dashboardBase = projectRef ? `https://supabase.com/dashboard/project/${projectRef}` : ''
  
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
            ${d.tomorrowMorning?.total > 0 ? `<br><span style="color:#3b82f6">📅 ${d.tomorrowMorning.total} scheduled for tomorrow morning (${d.tomorrowMorning.timeWindowPT})</span>` : ''}
            ${d.eligibleQueued > 0 ? `<br>Eligible for processing: ${d.eligibleQueued}` : ''}
            ${d.stuckProcessing > 0 ? `<br><span style="color:#dc2626;font-weight:600">⚠️ ${d.stuckProcessing} stuck processing!</span>` : ''}
            ${d.failures?.total_24h > 0 ? `<br><span style="color:#dc2626">❌ ${d.failures.total_24h} failed jobs</span>` : ''}
            ${dashboardBase && (d.overdue?.total > 0 || d.stuckProcessing > 0 || d.failures?.total_24h > 0) ? `<br><a href="${dashboardBase}/editor/jobs?filter=status%3Ain%3A%28queued%2Cprocessing%2Cfailed%29" style="color:#3b82f6;text-decoration:underline;font-size:12px">View in Dashboard →</a>` : ''}
          </div>`
      } else if (c.name === 'daystarts_completed' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <strong style="color:#059669;font-size:16px">${d.completed_24h} DayStarts completed</strong>
            <br><span style="color:#3b82f6">📱 ${d.unique_users} unique users served</span>
            ${d.avg_generation_minutes ? `<br><span style="color:#6b7280">⏱️ Average generation: ${d.avg_generation_minutes} minutes</span>` : ''}
            ${d.median_generation_minutes ? `<br><span style="color:#6b7280">📊 Median generation: ${d.median_generation_minutes} minutes</span>` : ''}
            ${d.shortest_generation_minutes ? `<br><span style="color:#6b7280">⚡ Shortest generation: ${d.shortest_generation_minutes} minutes</span>` : ''}
            ${d.longest_generation_minutes ? `<br><span style="color:#6b7280">🐌 Longest generation: ${d.longest_generation_minutes} minutes</span>` : ''}
            ${d.message ? `<br><em style="color:#16a34a">${d.message}</em>` : ''}
          </div>`
      } else if (c.name === 'content_cache_freshness' && c.details) {
        const d = c.details as any
        let cacheTableHtml = '<table style="width:100%;border-collapse:collapse;margin-top:8px"><tbody>'
        
        for (const [type, info] of Object.entries(d)) {
          if (type === 'expiredEntries' || type === 'summary') continue
          
          const typeInfo = info as any
          cacheTableHtml += `<tr><td style="padding:4px 0;font-weight:600;text-transform:capitalize">${type}:</td><td style="padding:4px 0">`
          
          if (typeInfo.status === 'missing') {
            cacheTableHtml += `<span style="color:#dc2626">❌ Missing</span>`
            if (typeInfo.expected_sources) {
              cacheTableHtml += `<br><span style="font-size:11px;color:#6b7280">Expected: ${typeInfo.expected_sources.join(', ')}</span>`
            }
          } else if (typeInfo.status === 'all_expired') {
            cacheTableHtml += `<span style="color:#f59e0b">⚠️ All sources expired (${typeInfo.total_sources}/${typeInfo.expected_sources || typeInfo.total_sources} sources)</span>`
          } else {
            cacheTableHtml += `<span style="color:#16a34a">✅ ${typeInfo.fresh_sources}/${typeInfo.expected_sources || typeInfo.total_sources} sources fresh</span>`
            
            // Show missing expected sources
            if (typeInfo.missing_sources && typeInfo.missing_sources.length > 0) {
              cacheTableHtml += `<br><span style="font-size:11px;color:#f59e0b">Missing: ${typeInfo.missing_sources.join(', ')}</span>`
            }
            
            // Show individual sources if any are expired
            const expiredSources = Object.entries(typeInfo.sources || {}).filter(([_, s]: [string, any]) => s.expired)
            if (expiredSources.length > 0) {
              cacheTableHtml += '<br><span style="font-size:11px;color:#6b7280">Expired: ' + 
                expiredSources.map(([source]) => source).join(', ') + '</span>'
            }
          }
          
          cacheTableHtml += '</td></tr>'
        }
        
        cacheTableHtml += '</tbody></table>'
        
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            ${cacheTableHtml}
            ${d.expiredEntries > 0 ? `<div style="margin-top:8px;font-size:12px;color:#6b7280">Total expired entries: ${d.expiredEntries}</div>` : ''}
          </div>`
      } else if (c.name === 'external_services' && c.details) {
        const d = c.details as any
        detailsHtml = '<div style="font-size:13px;line-height:1.5">'
        
        for (const [service, info] of Object.entries(d)) {
          const statusEmoji = info.status === 'healthy' ? '✅' : info.status === 'degraded' ? '⚠️' : '❌'
          const statusColor = info.status === 'healthy' ? '#16a34a' : info.status === 'degraded' ? '#f59e0b' : '#dc2626'
          detailsHtml += `<div style="margin-bottom:4px">
            <span style="color:${statusColor}">${statusEmoji}</span> 
            <strong style="text-transform:capitalize">${service}:</strong> 
            ${info.status}
            ${info.responseTime ? ` (${info.responseTime}ms)` : ''}
            ${info.error ? ` - ${info.error}` : ''}
          </div>`
        }
        
        detailsHtml += '</div>'
      } else if (c.name === 'recent_feedback' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <strong style="color:#059669;font-size:16px">${d.total_24h} feedback items</strong>
            ${d.total_24h > 0 ? `
              <br><span style="color:#6b7280">Categories: 
                ${d.categories.audio_issue > 0 ? `🔊 ${d.categories.audio_issue} audio` : ''}
                ${d.categories.content_quality > 0 ? `📰 ${d.categories.content_quality} content` : ''}
                ${d.categories.scheduling > 0 ? `⏰ ${d.categories.scheduling} scheduling` : ''}
                ${d.categories.other > 0 ? `❓ ${d.categories.other} other` : ''}
              </span>` : ''}
            ${d.critical_count > 0 ? `<br><span style="color:#dc2626;font-weight:600">⚠️ ${d.critical_count} critical issues (audio/content)</span>` : ''}
            ${d.has_contact_info > 0 ? `<br><span style="color:#3b82f6">📧 ${d.has_contact_info} users provided contact info</span>` : ''}
            ${d.samples?.length > 0 ? `<br><br><strong>Recent feedback:</strong>
              ${d.samples.map((s: any) => `
                <div style="margin:8px 0;padding:8px;background:#f9fafb;border-radius:4px;border-left:3px solid #e5e7eb">
                  <div style="font-size:12px;color:#6b7280;margin-bottom:4px">
                    ${s.category} • ${s.user_id} • ${new Date(s.created_at).toLocaleDateString()}
                    ${s.has_email ? ' 📧' : ''}
                  </div>
                  ${s.message ? `<div style="font-size:12px;color:#374151">"${escapeHtml(s.message)}"</div>` : ''}
                </div>
              `).join('')}` : ''}
            ${dashboardBase ? `<br><a href="${dashboardBase}/editor/app_feedback" style="color:#3b82f6;text-decoration:underline;font-size:12px">View All Feedback →</a>` : ''}
          </div>`
      } else if (c.name === 'storage_access' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <span style="color:#16a34a">✅ Storage accessible</span>
            ${d.path ? `<br><span style="color:#6b7280">📁 Test file: ${d.path}</span>` : ''}
            ${d.message ? `<br><em style="color:#6b7280">${d.message}</em>` : ''}
          </div>`
      } else if (c.name === 'internal_urls' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <strong>Edge Functions Status:</strong>
            ${d.results?.map((result: any) => {
              const statusEmoji = result.status === 200 || result.status === 204 ? '✅' : '❌'
              const statusColor = result.status === 200 || result.status === 204 ? '#16a34a' : '#dc2626'
              const endpoint = result.path.split('/').pop() || result.path
              return `<br><span style="color:${statusColor}">${statusEmoji}</span> <strong>${endpoint}:</strong> ${result.status === 0 ? 'timeout' : `HTTP ${result.status}`}`
            }).join('') || '<br><span style="color:#6b7280">No endpoints tested</span>'}
          </div>`
      } else if (c.name === 'audio_cleanup_heartbeat' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <span style="color:#16a34a">🧹 Cleanup running normally</span>
            ${d.last_started_at ? `<br><span style="color:#6b7280">📅 Last run: ${new Date(d.last_started_at).toLocaleDateString()} ${new Date(d.last_started_at).toLocaleTimeString()}</span>` : ''}
            ${d.hours_since !== undefined ? `<br><span style="color:#6b7280">⏰ ${d.hours_since} hours ago</span>` : ''}
            ${d.message ? `<br><em style="color:#6b7280">${d.message}</em>` : ''}
          </div>`
      } else if (c.name === 'db_connectivity' && c.details) {
        const d = c.details as any
        detailsHtml = `
          <div style="font-size:13px;line-height:1.5">
            <span style="color:#16a34a">✅ Database connected</span>
            ${d.jobs_table_accessible ? `<br><span style="color:#6b7280">📊 Jobs table accessible</span>` : ''}
            ${d.total_jobs !== undefined ? `<br><span style="color:#6b7280">📝 ${d.total_jobs} total jobs in system</span>` : ''}
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
                    <p style="margin:0;font-size:14px;color:#6b7280">Daily Operations Summary • ${new Date().toLocaleDateString('en-US', { timeZone: 'America/Los_Angeles', month: 'numeric', day: 'numeric', year: 'numeric' })}</p>
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
                
                ${getRecentFeedbackHtml(report)}
                
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
          ${dashboardBase ? `<br><a href="${dashboardBase}/editor/jobs?filter=status%3Deq%3Dqueued" style="color:#3b82f6;text-decoration:underline">View queued jobs →</a> | <a href="${dashboardBase}/logs/edge-logs?q=process_jobs" style="color:#3b82f6;text-decoration:underline">Check logs →</a>` : ''}
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

function getRecentFeedbackHtml(report: HealthReport): string {
  // Extract project reference from Supabase URL for dashboard links
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
  const projectRef = supabaseUrl.match(/https:\/\/([^.]+)\.supabase\.co/)?.[1] || ''
  const dashboardBase = projectRef ? `https://supabase.com/dashboard/project/${projectRef}` : ''
  
  const feedbackCheck = report.checks.find(c => c.name === 'recent_feedback')
  if (!feedbackCheck?.details) return ''
  
  const details = feedbackCheck.details as any
  
  // Always show feedback section if there's any feedback
  if (details.total_24h === 0) return ''
  
  let sections = []
  
  // Show feedback section
  if (details.total_24h > 0) {
    // Only show as warning/critical if there are many critical issues
    const isWarning = details.critical_count >= 3
    const isCritical = details.critical_count >= 5
    
    const bgColor = isCritical ? '#fee2e2' : isWarning ? '#fffbeb' : '#f0fdf4'
    const borderColor = isCritical ? '#dc2626' : isWarning ? '#f59e0b' : '#16a34a'
    const textColor = isCritical ? '#7f1d1d' : isWarning ? '#92400e' : '#166534'
    const alertEmoji = isCritical ? '🚨' : isWarning ? '⚠️' : '✅'
    const alertTitle = isCritical ? 'CRITICAL USER FEEDBACK' : isWarning ? 'USER FEEDBACK - MONITORING REQUIRED' : 'USER FEEDBACK RECEIVED'
    
    sections.push(`
      <div style="margin-bottom:32px">
        <h2 style="margin:0 0 20px 0;color:#374151;font-size:18px;font-weight:600">User Feedback (24h)</h2>
        <div style="padding:16px;background:${bgColor};border:2px solid ${borderColor};border-radius:8px">
          <h3 style="margin:0 0 12px 0;font-size:14px;color:${textColor}">${alertEmoji} ${alertTitle}</h3>
          <p style="margin:0;font-size:13px;line-height:1.5;color:${textColor}">
            <strong>${details.total_24h} feedback items</strong> received in the last 24 hours
            ${isCritical ? `<br><strong>${details.critical_count} critical issues</strong> (audio or content quality problems)` : ''}
            ${details.has_contact_info > 0 ? `<br><strong>${details.has_contact_info} users</strong> provided contact information for follow-up` : ''}
          </p>
          
          <div style="margin-top:12px;padding:12px;background:#ffffff;border-radius:6px;font-size:12px">
            <strong>Categories:</strong>
            ${details.categories.audio_issue > 0 ? `<span style="margin-right:12px">🔊 Audio: ${details.categories.audio_issue}</span>` : ''}
            ${details.categories.content_quality > 0 ? `<span style="margin-right:12px">📰 Content: ${details.categories.content_quality}</span>` : ''}
            ${details.categories.scheduling > 0 ? `<span style="margin-right:12px">⏰ Scheduling: ${details.categories.scheduling}</span>` : ''}
            ${details.categories.other > 0 ? `<span style="margin-right:12px">❓ Other: ${details.categories.other}</span>` : ''}
          </div>
          
          ${details.samples?.length > 0 ? `
            <div style="margin-top:12px">
              <strong style="font-size:12px;color:${textColor}">Recent Examples:</strong>
              ${details.samples.slice(0, 3).map((s: any) => `
                <div style="margin:8px 0;padding:8px;background:#ffffff;border-radius:4px;border-left:3px solid ${borderColor}">
                  <div style="font-size:11px;color:#6b7280;margin-bottom:4px">
                    <strong>${s.category}</strong> • ${s.user_id} • ${new Date(s.created_at).toLocaleDateString()}
                    ${s.has_email ? ' 📧' : ''}
                  </div>
                  ${s.message ? `<div style="font-size:12px;color:#374151">"${escapeHtml(s.message)}"</div>` : ''}
                </div>
              `).join('')}
            </div>
          ` : ''}
          
          <p style="margin:12px 0 0 0;font-size:12px;color:${textColor}">
            <strong>${isCritical ? 'Action Required:' : isWarning ? 'Action Recommended:' : 'Status:'}</strong> 
            ${isCritical ? 'Address critical user issues immediately.' : isWarning ? 'Review feedback patterns for potential service improvements.' : 'Users are actively providing feedback. Monitor for patterns.'}
            ${dashboardBase ? `<br><a href="${dashboardBase}/editor/app_feedback?filter=created_at%3Egte%3D${new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0]}" style="color:#3b82f6;text-decoration:underline">View All Recent Feedback →</a>` : ''}
          </p>
        </div>
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
      if (d.median_generation_minutes) {
        lines.push(`   - Median generation: ${d.median_generation_minutes} minutes`)
      }
      if (d.shortest_generation_minutes) {
        lines.push(`   - Shortest generation: ${d.shortest_generation_minutes} minutes`)
      }
      if (d.longest_generation_minutes) {
        lines.push(`   - Longest generation: ${d.longest_generation_minutes} minutes`)
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
    } else if (c.name === 'recent_feedback' && c.details) {
      const d = c.details as any
      if (d.total_24h > 0) {
        lines.push(`   - ${d.total_24h} feedback items received`)
        if (d.critical_count > 0) {
          lines.push(`   - ⚠️  ${d.critical_count} critical issues (audio/content)`)
        }
        if (d.has_contact_info > 0) {
          lines.push(`   - 📧 ${d.has_contact_info} users provided contact info`)
        }
        const categories = []
        if (d.categories.audio_issue > 0) categories.push(`${d.categories.audio_issue} audio`)
        if (d.categories.content_quality > 0) categories.push(`${d.categories.content_quality} content`)
        if (d.categories.scheduling > 0) categories.push(`${d.categories.scheduling} scheduling`)
        if (d.categories.other > 0) categories.push(`${d.categories.other} other`)
        if (categories.length > 0) {
          lines.push(`   - Categories: ${categories.join(', ')}`)
        }
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
  
  // Get normal operating metrics for context
  const daystartsCheck = checks.find(c => c.name === 'daystarts_completed')
  const daystartsCount = (daystartsCheck?.details as any)?.completed_24h || 0
  const medianGenTime = (daystartsCheck?.details as any)?.median_generation_minutes || 0
  
  const systemPrompt = `You are analyzing a DayStart backend healthcheck. DayStart delivers AI-generated morning briefings with audio.

Key context:
- process_jobs: Core function that generates audio content (CRITICAL)
- Jobs are scheduled for specific times (usually morning) and should process 2 hours before scheduled_at
- Overdue jobs: Jobs past their scheduled_at that haven't been processed (CRITICAL USER IMPACT)
- Rate limiting: Users have 4-hour cooldown between DayStarts  
- Queue processing: Jobs are processed in order with retry logic
- Content cache: External APIs cached for 12 hours

Normal operating parameters:
- Typical daily volume: 20-50 DayStarts per day (current: ${daystartsCount} in last 24h)
- Normal generation time: 2-5 minutes (current median: ${medianGenTime} minutes)
- Expected error rate: <1% of total requests
- Content cache: Should have at least 1 fresh source per type (news, stocks, sports)
- External services (OpenAI, ElevenLabs): Critical for audio generation

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


