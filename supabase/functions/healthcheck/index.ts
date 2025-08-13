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
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    const authHeader = req.headers.get('authorization')
    const expectedToken = Deno.env.get('WORKER_AUTH_TOKEN')
    if (!authHeader || authHeader !== `Bearer ${expectedToken}`) {
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
  checks.push(await withTimeout('db_connectivity', () => checkDbConnectivity(supabase), 3000))
  checks.push(await withTimeout('jobs_queue', () => checkJobsHealth(supabase), 5000))
  checks.push(await withTimeout('content_cache_freshness', () => checkContentCache(supabase), 4000))
  checks.push(await withTimeout('storage_access', () => checkStorageAccess(supabase), 4000))
  checks.push(await withTimeout('internal_urls', () => checkInternalUrls(), 3000))
  checks.push(await withTimeout('audio_cleanup_heartbeat', () => checkAudioCleanupHeartbeat(supabase), 3000))
  checks.push(await withTimeout('request_error_rate', () => checkRequestErrorRate(supabase), 3000))

  const overall = aggregateOverall(checks)
  const finished_at = new Date().toISOString()
  const report: HealthReport = {
    overall_status: overall.status,
    summary: overall.summary,
    checks,
    request_id,
    started_at,
    finished_at,
    duration_ms: Date.now() - t0,
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
  const tenMinAgo = new Date(now.getTime() - 10 * 60 * 1000).toISOString()
  const thirtyMinAgo = new Date(now.getTime() - 30 * 60 * 1000).toISOString()

  const [queued, processing, ready, failed] = await Promise.all([
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').gte('created_at', since24h),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'processing').gte('created_at', since24h),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'ready').gte('created_at', since24h),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'failed').gte('created_at', since24h),
  ])

  const counts = {
    queued: queued.count ?? 0,
    processing: processing.count ?? 0,
    ready: ready.count ?? 0,
    failed: failed.count ?? 0,
  }

  // Oldest queued job age
  const { data: oldestQueued } = await supabase
    .from('jobs')
    .select('created_at')
    .eq('status', 'queued')
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle()

  let oldestQueuedMinutes: number | null = null
  if (oldestQueued?.created_at) {
    oldestQueuedMinutes = Math.floor((now.getTime() - new Date(oldestQueued.created_at).getTime()) / 60000)
  }

  // Queued older than thresholds
  const [queuedGt10, queuedGt30] = await Promise.all([
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').lt('created_at', tenMinAgo),
    supabase.from('jobs').select('*', { head: true, count: 'exact' }).eq('status', 'queued').lt('created_at', thirtyMinAgo),
  ])

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
    counts,
    oldestQueuedMinutes,
    queuedOlderThan10m: queuedGt10.count ?? 0,
    queuedOlderThan30m: queuedGt30.count ?? 0,
    stuckProcessing: (stuckByLease ?? 0) + (staleProcessing ?? 0),
    updatesLastHour: updatesLastHour ?? 0,
  }

  if ((queuedGt30.count ?? 0) > 0 || ((stuckByLease ?? 0) + (staleProcessing ?? 0)) > 0) {
    status = 'fail'
  } else if ((queuedGt10.count ?? 0) > 0 || (updatesLastHour ?? 0) === 0) {
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
  const token = Deno.env.get('WORKER_AUTH_TOKEN') ?? ''

  // Use OPTIONS to avoid invoking heavy logic and external calls
  const endpoints = [
    { path: '/functions/v1/refresh_content', method: 'OPTIONS', headers: {} as Record<string, string> },
    { path: '/functions/v1/process_jobs', method: 'OPTIONS', headers: { authorization: `Bearer ${token}` } },
  ]

  const results: Array<{ path: string; status: number }> = []
  for (const ep of endpoints) {
    try {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 1500)
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

  const anyFail = results.some((r) => r.status === 0 || r.status >= 500)
  return { name: 'internal_urls', status: anyFail ? 'warn' : 'pass', details: { results }, duration_ms: Date.now() - start }
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

  const total = await supabase
    .from('request_logs')
    .select('*', { head: true, count: 'exact' })
    .gte('created_at', since24h)
  const errors = await supabase
    .from('request_logs')
    .select('*', { head: true, count: 'exact' })
    .gte('created_at', since24h)
    .not('error_code', 'is', null)

  const totalCount = total.count ?? 0
  const errorCount = errors.count ?? 0
  const rate = totalCount > 0 ? (errorCount / totalCount) * 100 : 0

  let status: CheckStatus = 'pass'
  if (rate > 5) status = 'fail'
  else if (rate > 1) status = 'warn'

  return {
    name: 'request_error_rate',
    status,
    details: { total_24h: totalCount, errors_24h: errorCount, error_rate_percent: Number(rate.toFixed(2)) },
    duration_ms: Date.now() - start,
  }
}

async function sendResendEmail(report: HealthReport): Promise<void> {
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

function buildEmailSubject(report: HealthReport): string {
  const d = new Date(report.started_at)
  // Omit year per preference
  const friendly = d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
  const statusIcon = report.overall_status === 'pass' ? '✅' : report.overall_status === 'warn' ? '⚠️' : '❌'
  return `${statusIcon} DayStart Healthcheck — ${friendly}`
}

function buildEmailHtml(report: HealthReport): string {
  const rows = report.checks
    .map((c) => {
      const color = c.status === 'pass' ? '#16a34a' : c.status === 'warn' ? '#ca8a04' : c.status === 'fail' ? '#dc2626' : '#6b7280'
      return `<tr style="border-bottom:1px solid #eee"><td style="padding:8px 12px;font-weight:600">${c.name}</td><td style="padding:8px 12px;color:${color}">${c.status.toUpperCase()}</td><td style="padding:8px 12px;font-family:ui-monospace, SFMono-Regular, Menlo, monospace;font-size:12px">${escapeHtml(
        JSON.stringify(c.details ?? (c.error ? { error: c.error } : {})),
      )}</td></tr>`
    })
    .join('')
  return `<!doctype html><html><body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color:#111">
    <h2 style="margin:0 0 8px 0">Healthcheck</h2>
    <p style="margin:0 0 12px 0"><strong>Overall:</strong> ${report.overall_status.toUpperCase()}</p>
    <p style="margin:0 0 16px 0">${escapeHtml(report.summary)}</p>
    <table cellspacing="0" cellpadding="0" style="border-collapse:collapse;min-width:520px">
      <thead><tr><th align="left" style="padding:8px 12px;border-bottom:2px solid #000">Check</th><th align="left" style="padding:8px 12px;border-bottom:2px solid #000">Status</th><th align="left" style="padding:8px 12px;border-bottom:2px solid #000">Details</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <p style="margin-top:16px;color:#666;font-size:12px">Request: ${report.request_id} • Started: ${report.started_at} • Duration: ${report.duration_ms} ms</p>
  </body></html>`
}

function buildEmailText(report: HealthReport): string {
  const lines = [
    `Overall: ${report.overall_status.toUpperCase()}`,
    report.summary,
    '',
    ...report.checks.map((c) => `- ${c.name}: ${c.status.toUpperCase()} ${c.error ? `(error: ${c.error})` : ''}`),
    '',
    `Request: ${report.request_id} | Started: ${report.started_at} | Duration: ${report.duration_ms}ms`,
  ]
  return lines.join('\n')
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


