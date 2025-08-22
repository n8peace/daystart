import { serve } from "https://deno.land/std@0.208.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
// Local lint shim for Deno globals in non-Deno editors
declare const Deno: any

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-worker-token',
}

interface ContentSource {
  type: 'news' | 'stocks' | 'sports'
  source: string
  ttlHours: number
  fetchFunction: () => Promise<any>
}

// Simple constant-time string comparison to avoid timing leaks
function safeEq(a: string = '', b: string = ''): boolean {
  if (a.length !== b.length) return false
  let res = 0
  for (let i = 0; i < a.length; i++) res |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return res === 0
}

// Fetch with timeout + retries + backoff, respecting Retry-After on 429
async function fetchWithRetry(url: string, init: RequestInit = {}, tries = 3, baseMs = 600, timeoutMs = 15000): Promise<Response> {
  let lastErr: any
  for (let i = 0; i < tries; i++) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    try {
      const res = await fetch(url, {
        ...init,
        signal: controller.signal,
        headers: {
          'user-agent': 'daystart/1.0',
          ...(init.headers || {}) as Record<string, string>,
        },
      })
      if (res.status === 429 && i < tries - 1) {
        const retryAfterSec = Number(res.headers.get('retry-after') || '0')
        const backoff = baseMs * (2 ** i)
        await new Promise(r => setTimeout(r, Math.max(backoff, retryAfterSec * 1000)))
        continue
      }
      if (!res.ok && i < tries - 1) {
        const backoff = baseMs * (2 ** i)
        await new Promise(r => setTimeout(r, backoff))
        continue
      }
      return res
    } catch (e) {
      lastErr = e
      if (i < tries - 1) {
        const backoff = baseMs * (2 ** i)
        await new Promise(r => setTimeout(r, backoff))
      }
    } finally {
      clearTimeout(timer)
    }
  }
  throw lastErr
}

async function getJSON<T = any>(url: string, init?: RequestInit, timeoutMs = 15000): Promise<T> {
  const res = await fetchWithRetry(url, init, 3, 600, timeoutMs)
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  return await res.json()
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Bearer auth guard - accept either service role key or worker token
  const authHeader = req.headers.get('authorization') || ''
  const workerTokenHeader = req.headers.get('x-worker-token') || ''
  const expectedWorkerToken = Deno.env.get('WORKER_AUTH_TOKEN') || ''
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

  // Check if it's the worker token
  if (workerTokenHeader && expectedWorkerToken && safeEq(workerTokenHeader, expectedWorkerToken)) {
    // Valid worker token
  } 
  // Check if it's the service role key
  else if (authHeader && supabaseServiceKey && safeEq(authHeader, `Bearer ${supabaseServiceKey}`)) {
    // Valid service role key
  }
  // Otherwise unauthorized
  else {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  const request_id = crypto.randomUUID()
  
  try {
    console.log(`🔄 Content refresh accepted with request_id: ${request_id}`)
    
    // Start async processing without waiting
    refreshContentAsync(request_id).catch(error => {
      console.error('Async content refresh error:', error)
    })

    // Return immediate success response
    return new Response(
      JSON.stringify({
        success: true,
        message: 'Content refresh started',
        request_id,
        started_at: new Date().toISOString()
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    console.error('❌ Content refresh startup failed:', error)
    
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        message: 'Content refresh failed to start',
        request_id
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

async function refreshContentAsync(request_id: string): Promise<void> {
  try {
    // Initialize Supabase client with service role key for full access
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    console.log(`🔄 Starting content refresh cycle for request ${request_id}`)
    const startTime = Date.now()

    // Concurrency guard using advisory lock (no-op if RPC missing)
    let lockAcquired = false
    try {
      const { data: gotLock } = await supabase.rpc('try_refresh_lock')
      lockAcquired = !!gotLock
    } catch (_) {
      lockAcquired = true
    }
    if (!lockAcquired) {
      console.warn(`[${request_id}] Skipping refresh; another instance holds the lock`)
      return
    }

    // Define all content sources, guarding required envs
    const contentSources: ContentSource[] = []
    const missingEnvs: string[] = []
    if (Deno.env.get('NEWSAPI_KEY')) {
      contentSources.push({ type: 'news', source: 'newsapi', ttlHours: 168, fetchFunction: () => fetchNewsAPI() })
    } else { missingEnvs.push('NEWSAPI_KEY') }
    if (Deno.env.get('GNEWS_API_KEY')) {
      contentSources.push({ type: 'news', source: 'gnews', ttlHours: 168, fetchFunction: () => fetchGNews() })
    } else { missingEnvs.push('GNEWS_API_KEY') }
    if (Deno.env.get('RAPIDAPI_KEY')) {
      contentSources.push({ type: 'stocks', source: 'yahoo_finance', ttlHours: 168, fetchFunction: () => fetchYahooFinance(supabase) })
    } else { missingEnvs.push('RAPIDAPI_KEY') }
    contentSources.push({ type: 'sports', source: 'espn', ttlHours: 168, fetchFunction: () => fetchESPN() })
    contentSources.push({ type: 'sports', source: 'thesportdb', ttlHours: 168, fetchFunction: () => fetchTheSportDB() })

    const results = {
      successful: 0,
      failed: 0,
      errors: [] as string[],
      missing_envs: missingEnvs,
      sources: [] as { source: string; type: string; duration_ms: number; success: boolean; error?: string }[]
    }

    // Fetch from all sources in parallel
    const fetchPromises = contentSources.map(async (source) => {
      try {
        console.log(`📡 Fetching ${source.source} (${source.type})`)
        const t0 = Date.now()
        const data = await source.fetchFunction()
        
        if (data && Object.keys(data).length > 0) {
          // Attach compact content before caching to reduce downstream token usage
          try {
            if (source.type === 'news') {
              const articles = Array.isArray((data as any).articles) ? (data as any).articles.slice(0, 12) : []
              const compactNews = await summarizeNewsMini(articles, source.source)
              if (Array.isArray(compactNews) && compactNews.length > 0) {
                ;(data as any).compact = { ...((data as any).compact || {}), news: compactNews.slice(0, 12) }
              }
            } else if (source.type === 'sports') {
              const compactSports = compactSportsLocal(data)
              if (Array.isArray(compactSports) && compactSports.length > 0) {
                ;(data as any).compact = { ...((data as any).compact || {}), sports: compactSports.slice(0, 24) }
              }
            } else if (source.type === 'stocks') {
              const compactStocks = compactStocksLocal(data)
              if (Array.isArray(compactStocks) && compactStocks.length > 0) {
                ;(data as any).compact = { ...((data as any).compact || {}), stocks: compactStocks.slice(0, 24) }
              }
            }
          } catch (e) {
            console.warn(`⚠️ Compact step failed for ${source.source}:`, (e as any)?.message || e)
          }
          
          // Cache the content
          const { error } = await supabase.rpc('cache_content', {
            p_content_type: source.type,
            p_source: source.source,
            p_data: data,
            p_expires_hours: source.ttlHours
          })

          if (error) {
            console.error(`❌ Failed to cache ${source.source}: ${error.message}`)
            results.errors.push(`${source.source}: ${error.message}`)
            results.failed++
          } else {
            console.log(`✅ Cached ${source.source} successfully`)
            results.successful++
            results.sources.push({ source: source.source, type: source.type, duration_ms: Date.now() - t0, success: true })
          }
        } else {
          console.warn(`⚠️ ${source.source} returned empty data`)
          results.errors.push(`${source.source}: Empty data returned`)
          results.failed++
          results.sources.push({ source: source.source, type: source.type, duration_ms: Date.now() - t0, success: false, error: 'empty' })
        }
      } catch (error) {
        console.error(`❌ Error fetching ${source.source}: ${error.message}`)
        results.errors.push(`${source.source}: ${error.message}`)
        results.failed++
        results.sources.push({ source: source.source, type: source.type, duration_ms: 0, success: false, error: (error as Error).message })
      }
    })

    await Promise.all(fetchPromises)

    // Clean up expired content
    try {
      const { data: cleanupCount } = await supabase.rpc('cleanup_expired_content')
      console.log(`🧹 Cleaned up ${cleanupCount} expired entries`)
    } catch (error) {
      console.error(`⚠️ Cleanup failed: ${error.message}`)
    }

    const duration = Date.now() - startTime
    
    console.log(`📊 Content refresh completed for request ${request_id} in ${duration}ms`)
    console.log(`✅ Successful: ${results.successful}`)
    console.log(`❌ Failed: ${results.failed}`)

    // Best-effort request log summary with timings
    try {
      await supabase.from('request_logs').insert({
        request_id,
        endpoint: '/refresh_content',
        method: 'POST',
        status_code: 200,
        response_time_ms: duration,
      })
    } catch (_) {}

  } catch (error) {
    console.error(`❌ Content refresh async processing failed for request ${request_id}:`, error)
  } finally {
    try {
      // release advisory lock if functions exist
      await createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      ).rpc('release_refresh_lock')
    } catch (_) {}
  }
}

// News API fetch function
async function fetchNewsAPI(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  const url = `https://newsapi.org/v2/top-headlines?country=us&pageSize=10&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).slice(0, 5).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi'
  }
}

// GNews API fetch function
async function fetchGNews(): Promise<any> {
  const apiKey = Deno.env.get('GNEWS_API_KEY')
  if (!apiKey) throw new Error('GNEWS_API_KEY not configured')

  const url = `https://gnews.io/api/v4/top-headlines?country=us&max=10&token=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (!data.articles) {
    throw new Error(`GNews error: ${data.errors?.[0]?.message || 'No articles returned'}`)
  }

  return {
    articles: (data.articles || []).slice(0, 5).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'GNews'
    })),
    total_results: data.totalArticles,
    fetched_at: new Date().toISOString(),
    source: 'gnews'
  }
}

// Yahoo Finance fetch function (via RapidAPI)
async function fetchYahooFinance(supabase: any): Promise<any> {
  const rapidApiKey = Deno.env.get('RAPIDAPI_KEY')
  if (!rapidApiKey) throw new Error('RAPIDAPI_KEY not configured')

  // Expanded base symbols list with popular stocks, ETFs, and crypto
  const baseSymbols = [
    // Original tech stocks
    'AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'NVDA', 'META', 'NFLX',
    // Additional popular stocks
    'SPY', 'QQQ', 'IWM', 'VTI', 'VOO', 'JPM', 'JNJ', 'V', 'PG', 'UNH',
    'HD', 'DIS', 'MA', 'PYPL', 'BAC', 'ADBE', 'CRM', 'AMD', 'INTC',
    // Crypto pairs
    'BTC-USD', 'ETH-USD', 'ADA-USD', 'SOL-USD',
    // Forex pairs
    'EUR=X', 'GBP=X', 'JPY=X'
  ]

  // Get user-requested symbols from active jobs (next 48 hours)
  const next48Hours = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString()
  let userSymbols: string[] = []
  
  try {
    const { data: jobs } = await supabase
      .from('jobs')
      .select('stock_symbols')
      .not('stock_symbols', 'is', null)
      .gte('scheduled_at', new Date().toISOString())
      .lte('scheduled_at', next48Hours)
    
    if (jobs) {
      userSymbols = [...new Set(jobs.flatMap((job: any) => job.stock_symbols || []))]
      console.log(`📈 Found ${userSymbols.length} user-requested stock symbols: ${userSymbols.join(', ')}`)
    }
  } catch (error) {
    console.warn('⚠️ Failed to fetch user stock symbols, using base symbols only:', error)
  }

  // Combine base symbols with user symbols, remove duplicates
  const allSymbols = [...new Set([...baseSymbols, ...userSymbols])]
  console.log(`📈 Fetching ${allSymbols.length} total stock symbols (${baseSymbols.length} base + ${userSymbols.length} user)`)
  
  const symbolString = allSymbols.join('%2C') // URL encode commas
  
  const url = `https://apidojo-yahoo-finance-v1.p.rapidapi.com/market/v2/get-quotes?region=US&symbols=${symbolString}`
  const data = await getJSON<any>(url, {
    headers: {
      'x-rapidapi-host': 'apidojo-yahoo-finance-v1.p.rapidapi.com',
      'x-rapidapi-key': rapidApiKey
    }
  })
  
  if (!data.quoteResponse?.result) {
    throw new Error('Yahoo Finance: No quote data returned')
  }

  return {
    quotes: data.quoteResponse.result.map((quote: any) => ({
      symbol: quote.symbol,
      name: quote.longName || quote.shortName,
      price: quote.regularMarketPrice,
      change: quote.regularMarketChange,
      change_percent: quote.regularMarketChangePercent,
      market_cap: quote.marketCap
    })),
    market_summary: {
      market_time: data.quoteResponse.result[0]?.regularMarketTime,
      trading_session: 'regular'
    },
    fetched_at: new Date().toISOString(),
    source: 'yahoo_finance'
  }
}

// ESPN API fetch function
async function fetchESPN(): Promise<any> {
  // ESPN public API for sports scores
  const url = 'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard'
  const data = await getJSON<any>(url)
  
  return {
    games: data.events?.slice(0, 10).map((event: any) => ({
      id: event.id,
      name: event.name,
      date: event.date,
      status: event.status?.type?.name,
      competitors: event.competitions?.[0]?.competitors?.map((comp: any) => ({
        team: comp.team.displayName,
        score: comp.score,
        record: comp.records?.[0]?.summary
      })) || []
    })) || [],
    season: data.season,
    league: 'NBA',
    fetched_at: new Date().toISOString(),
    source: 'espn'
  }
}

// TheSportDB API fetch function
async function fetchTheSportDB(): Promise<any> {
  // Get today's and tomorrow's dates in YYYY-MM-DD format
  const today = new Date().toISOString().split('T')[0]
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().split('T')[0]
  
  // Fetch both today and tomorrow to catch events that slip to next day due to UTC
  const [todayData, tomorrowData] = await Promise.all([
    getJSON<any>(`https://www.thesportsdb.com/api/v1/json/123/eventsday.php?d=${today}`),
    getJSON<any>(`https://www.thesportsdb.com/api/v1/json/123/eventsday.php?d=${tomorrow}`)
  ])
  
  // Combine events from both days
  const allEvents = [
    ...(todayData.events || []),
    ...(tomorrowData.events || [])
  ]
  
  return {
    events: allEvents.slice(0, 20).map((event: any) => ({
      event: event.strEvent,
      date: event.dateEvent,
      time: event.strTime,
      home_team: event.strHomeTeam,
      away_team: event.strAwayTeam,
      home_score: event.intHomeScore,
      away_score: event.intAwayScore,
      status: event.strStatus,
      league: event.strLeague,
      sport: event.strSport
    })) || [],
    date: `${today},${tomorrow}`,
    fetched_at: new Date().toISOString(),
    source: 'thesportdb'
  }
}

// Compacting helpers
async function summarizeNewsMini(articles: any[] = [], sourceName: string = ''): Promise<any[]> {
  const openaiKey = Deno.env.get('OPENAI_API_KEY')
  if (!openaiKey || !Array.isArray(articles) || articles.length === 0) return []

  const payload = {
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `Create substantive, speakable news summaries for a morning TTS script.
Return strictly JSON: {"items": Array<CompactItem>}.
CompactItem fields:
- id: stable string (prefer url; else a 32-char hash of title)
- source: short source name
- publishedAt: ISO8601 if present
- speakable: concrete and factual summary with key details, context, and specific information
- geo: one of local|state|national|international
- category: one of politics|business|tech|sports|weather|other`
      },
      {
        role: 'user',
        content: `SOURCE: ${sourceName}
ARTICLES (JSON):
${JSON.stringify(articles.map(a => ({
  title: a?.title || '',
  description: a?.description || '',
  url: a?.url || '',
  publishedAt: a?.publishedAt || a?.date || ''
})).slice(0, 12))}
Return JSON only.`
      }
    ],
    temperature: 0.2,
    max_tokens: 900
  }

  const resp = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${openaiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  })

  if (!resp.ok) return []

  const data = await resp.json().catch(() => null)
  const content = data?.choices?.[0]?.message?.content || ''
  try {
    const parsed = JSON.parse(content)
    const items = Array.isArray(parsed?.items) ? parsed.items : []
    return items.map((it: any) => ({
      id: it?.id || it?.url || '',
      source: it?.source || sourceName,
      publishedAt: it?.publishedAt || '',
      speakable: String(it?.speakable || '').trim(),
      geo: it?.geo || 'national',
      category: it?.category || 'other'
    })).filter((it: any) => it.speakable)
  } catch {
    return []
  }
}

function compactSportsLocal(data: any): any[] {
  const events = Array.isArray((data as any)?.events) ? (data as any).events : Array.isArray((data as any)?.games) ? (data as any).games : []
  const out: any[] = []
  for (const ev of events) {
    const status = String(ev?.status || '').toUpperCase()
    const date = String(ev?.date || ev?.dateEvent || '')
    const home = ev?.home_team || ev?.competitors?.[0]?.team || ''
    const away = ev?.away_team || ev?.competitors?.[1]?.team || ''
    const hs = ev?.home_score ?? ev?.competitors?.[0]?.score
    const as = ev?.away_score ?? ev?.competitors?.[1]?.score
    let speakable = ''
    if (status === 'FT') {
      speakable = `${home} beat ${away} ${hs}-${as}.`
    } else if (status === 'NS') {
      speakable = `${home} vs ${away} later today.`
    } else if (status === 'LIVE') {
      speakable = `${home} vs ${away} in progress.`
    } else {
      continue
    }
    out.push({ id: `${home}-${away}-${date}`, league: ev?.league || (data as any)?.league || '', date, status, speakable })
  }
  return out
}

function compactStocksLocal(data: any): any[] {
  const quotes = Array.isArray((data as any)?.quotes) ? (data as any).quotes : []
  return quotes.map((q: any) => {
    const pct = typeof q?.change_percent === 'number' ? Number(q.change_percent).toFixed(2) : null
    const dir = (q?.change ?? 0) >= 0 ? 'up' : 'down'
    const line = pct !== null ? `${q?.symbol} ${dir} ${Math.abs(Number(pct))}% to ${q?.price}.` : `${q?.symbol} at ${q?.price}.`
    return {
      symbol: q?.symbol,
      name: q?.name || '',
      price: q?.price,
      chg: q?.change,
      chgPct: q?.change_percent,
      speakable: line
    }
  })
}