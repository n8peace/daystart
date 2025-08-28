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
      contentSources.push({ type: 'news', source: 'newsapi_general', ttlHours: 168, fetchFunction: () => fetchNewsAPIGeneral() })
      contentSources.push({ type: 'news', source: 'newsapi_business', ttlHours: 168, fetchFunction: () => fetchNewsAPIBusiness() })
      contentSources.push({ type: 'news', source: 'newsapi_targeted', ttlHours: 168, fetchFunction: () => fetchNewsAPITargeted() })
    } else { missingEnvs.push('NEWSAPI_KEY') }
    if (Deno.env.get('GNEWS_API_KEY')) {
      contentSources.push({ type: 'news', source: 'gnews_comprehensive', ttlHours: 168, fetchFunction: () => fetchGNewsComprehensive() })
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
              const articles = Array.isArray((data as any).articles) ? (data as any).articles : []
              
              // For news, we now process all articles for intelligence
              if (articles.length > 0) {
                // Apply importance scoring and categorization
                const enhancedArticles = articles.map(article => enhanceArticleWithIntelligence(article, source.source))
                
                // Store enhanced articles in data
                ;(data as any).articles = enhancedArticles
                
                // Create compact summaries for backwards compatibility
                const compactNews = await summarizeNewsMini(enhancedArticles.slice(0, 12), source.source)
              if (Array.isArray(compactNews) && compactNews.length > 0) {
                ;(data as any).compact = { ...((data as any).compact || {}), news: compactNews.slice(0, 12) }
                }
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

    // Enhanced News Processing: Generate Top 10 Stories
    try {
      if (results.successful > 0) {
        console.log('🧠 Starting enhanced news intelligence processing...')
        await generateTopTenStories(supabase, request_id)
        console.log('✅ Enhanced news processing completed')
      }
    } catch (error) {
      console.error('❌ Enhanced news processing failed:', error)
      // Don't fail the entire refresh if this fails
    }

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

// Enhanced NewsAPI fetch functions - Multiple endpoints for comprehensive coverage

// General top headlines
async function fetchNewsAPIGeneral(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  const url = `https://newsapi.org/v2/top-headlines?country=us&pageSize=25&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI General error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'general'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_general',
    endpoint: 'top-headlines'
  }
}

// Business-focused headlines  
async function fetchNewsAPIBusiness(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  const url = `https://newsapi.org/v2/top-headlines?country=us&category=business&pageSize=25&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Business error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'business'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_business',
    endpoint: 'top-headlines/business'
  }
}

// Targeted high-impact keywords
async function fetchNewsAPITargeted(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // High-impact search terms
  const searchTerms = 'election OR economy OR "supreme court" OR "federal reserve" OR climate OR inflation OR recession'
  const from = new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString() // Last 12 hours
  
  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=popularity&from=${from}&pageSize=30&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Targeted error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'targeted'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_targeted',
    endpoint: 'everything/targeted',
    search_terms: searchTerms
  }
}

// Enhanced GNews comprehensive fetch
async function fetchGNewsComprehensive(): Promise<any> {
  const apiKey = Deno.env.get('GNEWS_API_KEY')
  if (!apiKey) throw new Error('GNEWS_API_KEY not configured')

  const url = `https://gnews.io/api/v4/top-headlines?country=us&max=25&token=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (!data.articles) {
    throw new Error(`GNews error: ${data.errors?.[0]?.message || 'No articles returned'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'GNews',
      category: 'general'
    })),
    total_results: data.totalArticles,
    fetched_at: new Date().toISOString(),
    source: 'gnews_comprehensive',
    endpoint: 'top-headlines'
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
      userSymbols = [...new Set(jobs.flatMap((job: any) => (job.stock_symbols || []).map(String)))]
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

// ============================================================================
// ENHANCED NEWS INTELLIGENCE SYSTEM
// ============================================================================

// Intelligence enhancement for individual articles
function enhanceArticleWithIntelligence(article: any, sourceName: string): any {
  return {
    ...article,
    importance_score: calculateImportanceScore(article),
    topic_category: categorizeStory(article),
    geographic_scope: determineGeographicScope(article),
    enhanced_at: new Date().toISOString(),
    source_name: sourceName
  }
}

// Calculate importance score based on content analysis
function calculateImportanceScore(article: any): number {
  let score = 0
  const text = `${article.title || ''} ${article.description || ''}`.toLowerCase()
  
  // Source authority (basic trust scoring)
  const source = (article.source || '').toLowerCase()
  if (['reuters', 'associated press', 'ap', 'bbc', 'npr'].includes(source)) score += 10
  else if (['wall street journal', 'new york times', 'washington post', 'bloomberg'].includes(source)) score += 8
  else if (['cnn', 'fox news', 'msnbc', 'abc news', 'cbs news'].includes(source)) score += 6
  else score += 3 // Default for other sources
  
  // High-impact topic keywords
  if (text.includes('election') || text.includes('vote') || text.includes('ballot')) score += 20
  if (text.includes('economy') || text.includes('recession') || text.includes('inflation') || text.includes('unemployment')) score += 15
  if (text.includes('war') || text.includes('conflict') || text.includes('crisis') || text.includes('attack')) score += 15
  if (text.includes('supreme court') || text.includes('scotus') || text.includes('constitutional')) score += 12
  if (text.includes('federal reserve') || text.includes('fed') || text.includes('interest rate')) score += 12
  if (text.includes('climate') || text.includes('disaster') || text.includes('hurricane') || text.includes('wildfire')) score += 10
  if (text.includes('president') || text.includes('congress') || text.includes('senate') || text.includes('house')) score += 8
  if (text.includes('market') || text.includes('stock') || text.includes('trading')) score += 8
  if (text.includes('technology') || text.includes('ai') || text.includes('artificial intelligence')) score += 6
  if (text.includes('health') || text.includes('pandemic') || text.includes('outbreak') || text.includes('vaccine')) score += 7
  
  // Business impact indicators
  if (text.includes('billion') || text.includes('trillion')) score += 5
  if (text.includes('merger') || text.includes('acquisition') || text.includes('ipo')) score += 4
  if (text.includes('earnings') || text.includes('revenue') || text.includes('profit')) score += 3
  
  // Government/policy indicators
  if (text.includes('bill') || text.includes('law') || text.includes('policy') || text.includes('regulation')) score += 6
  if (text.includes('investigation') || text.includes('indictment') || text.includes('lawsuit')) score += 5
  
  // Urgency indicators
  if (text.includes('breaking') || text.includes('urgent')) score += 8
  if (text.includes('developing') || text.includes('live') || text.includes('update')) score += 4
  
  // Recency boost (more recent = higher impact)
  if (article.publishedAt) {
    const hoursOld = (Date.now() - new Date(article.publishedAt).getTime()) / (1000 * 60 * 60)
    if (hoursOld < 1) score += 10
    else if (hoursOld < 6) score += 5
    else if (hoursOld < 12) score += 2
  }
  
  return Math.max(0, Math.min(100, score)) // Clamp to 0-100
}

// Categorize story by topic
function categorizeStory(article: any): string {
  const text = `${article.title || ''} ${article.description || ''}`.toLowerCase()
  
  if (text.includes('election') || text.includes('congress') || text.includes('senate') || 
      text.includes('president') || text.includes('government') || text.includes('policy')) return 'politics'
  if (text.includes('economy') || text.includes('market') || text.includes('stock') || 
      text.includes('business') || text.includes('company') || text.includes('earnings')) return 'business'  
  if (text.includes('technology') || text.includes('tech') || text.includes('ai') || 
      text.includes('software') || text.includes('internet')) return 'technology'
  if (text.includes('health') || text.includes('medical') || text.includes('hospital') || 
      text.includes('doctor') || text.includes('disease')) return 'health'
  if (text.includes('climate') || text.includes('environment') || text.includes('weather') || 
      text.includes('hurricane') || text.includes('earthquake')) return 'climate'
  if (text.includes('sports') || text.includes('game') || text.includes('team') || 
      text.includes('player') || text.includes('championship')) return 'sports'
  if (text.includes('international') || text.includes('foreign') || text.includes('global') || 
      text.includes('china') || text.includes('russia') || text.includes('europe')) return 'international'
  
  return 'general'
}

// Determine geographic scope
function determineGeographicScope(article: any): string {
  const text = `${article.title || ''} ${article.description || ''}`.toLowerCase()
  
  // Check for international indicators
  if (text.includes('china') || text.includes('russia') || text.includes('europe') || 
      text.includes('ukraine') || text.includes('international') || text.includes('global')) return 'international'
  
  // Check for state/local indicators (this is basic - could be enhanced)
  if (text.includes('california') || text.includes('texas') || text.includes('florida') || 
      text.includes('new york') || text.includes('los angeles') || text.includes('chicago')) return 'state'
  
  // Check for federal/national indicators
  if (text.includes('federal') || text.includes('congress') || text.includes('senate') || 
      text.includes('supreme court') || text.includes('president')) return 'national'
  
  return 'national' // Default assumption
}

// Article deduplication across sources
function deduplicateArticles(articles: any[]): any[] {
  const seen = new Set<string>()
  const deduped: any[] = []
  
  for (const article of articles) {
    // Create a key from URL, title, or description
    const key = (article.url || article.title || article.description || '').toLowerCase().slice(0, 100)
    if (!key || seen.has(key)) continue
    
    seen.add(key)
    deduped.push(article)
  }
  
  return deduped
}

// Ensure topic diversity in article selection
function ensureTopicDiversity(articles: any[], maxCount: number = 25): any[] {
  const categories = ['politics', 'business', 'technology', 'international', 'health', 'climate']
  const result: any[] = []
  const used = new Set<any>()
  
  // First pass: ensure at least one from each major category
  for (const category of categories) {
    const best = articles
      .filter(a => a.topic_category === category && !used.has(a))
      .sort((a, b) => b.importance_score - a.importance_score)[0]
    
    if (best) {
      result.push(best)
      used.add(best)
    }
  }
  
  // Second pass: fill remaining slots with highest scoring articles
  const remaining = articles
    .filter(a => !used.has(a))
    .sort((a, b) => b.importance_score - a.importance_score)
  
  for (const article of remaining) {
    if (result.length >= maxCount) break
    result.push(article)
  }
  
  return result.slice(0, maxCount)
}

// Main function to generate top 10 stories from all sources
async function generateTopTenStories(supabase: any, requestId: string): Promise<void> {
  console.log(`[${requestId}] 🧠 Starting top 10 story generation...`)
  
  try {
    // 1. Fetch all news content from cache
    const { data: newsContent, error } = await supabase.rpc('get_fresh_content', {
      requested_types: ['news']
    })
    
    if (error || !newsContent?.news) {
      console.log(`[${requestId}] ⚠️ No news content available for processing`)
      return
    }
    
    console.log(`[${requestId}] 📰 Found ${newsContent.news.length} news sources`)
    
    // 2. Collect all articles from all sources
    const allArticles: any[] = []
    for (const source of newsContent.news) {
      const articles = source.data?.articles || []
      allArticles.push(...articles)
    }
    
    console.log(`[${requestId}] 📊 Collected ${allArticles.length} total articles`)
    
    if (allArticles.length === 0) {
      console.log(`[${requestId}] ⚠️ No articles found in any source`)
      return
    }
    
    // 3. Deduplicate articles
    const dedupedArticles = deduplicateArticles(allArticles)
    console.log(`[${requestId}] 🔄 Deduplication: ${allArticles.length} → ${dedupedArticles.length} articles`)
    
    // 4. Sort by importance and ensure diversity
    const rankedArticles = ensureTopicDiversity(
      dedupedArticles.sort((a, b) => b.importance_score - a.importance_score),
      25
    )
    
    console.log(`[${requestId}] 🎯 Selected top 25 diverse articles for AI analysis`)
    
    // 5. Use GPT-4o-mini for final top 10 selection  
    const topTenStories = await selectFinalTopTen(rankedArticles, requestId)
    
    // 6. Cache the top 10 stories as a special source
    const topTenData = {
      stories: topTenStories,
      generation_metadata: {
        articles_processed: allArticles.length,
        articles_deduped: dedupedArticles.length,
        articles_analyzed: rankedArticles.length,
        ai_model: 'gpt-4o-mini',
        generated_at: new Date().toISOString(),
        request_id: requestId
      },
      // Maintain backwards compatibility - provide articles array
      articles: topTenStories.map(story => ({
        title: story.title,
        description: story.description,
        url: story.url,
        publishedAt: story.publishedAt,
        source: story.source
      })),
      // Enhanced compact format with comprehensive summaries
      compact: {
        news: topTenStories.map(story => ({
          id: story.id || story.url || `story_${Date.now()}`,
          source: story.source_name || story.source,
          publishedAt: story.publishedAt,
          description: story.enhanced_summary || story.ai_summary || story.title,
          geo: story.geographic_scope,
          category: story.topic_category,
          importance_score: story.importance_score,
          ai_rank: story.ai_rank,
          key_entities: story.key_entities || [],
          impact_level: story.impact_level || 'medium',
          selection_reason: story.selection_reason
        }))
      }
    }
    
    // Store as a special "top_ten" source
    const { error: cacheError } = await supabase.rpc('cache_content', {
      p_content_type: 'news',
      p_source: 'top_ten_ai_curated',
      p_data: topTenData,
      p_expires_hours: 12
    })
    
    if (cacheError) {
      console.error(`[${requestId}] ❌ Failed to cache top 10 stories:`, cacheError)
    } else {
      console.log(`[${requestId}] ✅ Successfully cached top 10 AI-curated stories`)
    }
    
  } catch (error) {
    console.error(`[${requestId}] ❌ Top 10 generation failed:`, error)
    throw error
  }
}

// Use GPT-4o-mini to select final top 10 from top 25
async function selectFinalTopTen(candidates: any[], requestId: string): Promise<any[]> {
  const openaiKey = Deno.env.get('OPENAI_API_KEY')
  if (!openaiKey) {
    console.log(`[${requestId}] ⚠️ No OpenAI key - using basic ranking for top 10`)
    return candidates.slice(0, 10).map((article, index) => ({
      ...article,
      ai_rank: index + 1,
      ai_summary: article.title,
      selection_reason: 'High importance score'
    }))
  }
  
  console.log(`[${requestId}] 🤖 Using GPT-4o-mini to select final top 10 stories...`)
  
  try {
    const payload = {
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are a senior news editor selecting exactly 10 stories for a national morning briefing.

SELECTION CRITERIA (in order of priority):
1. IMPACT: Stories affecting the most people or having major consequences
2. TIMELINESS: Recent developments, breaking news, or evolving situations
3. RELEVANCE: Important for informed citizens to know today
4. DIVERSITY: Ensure breadth - avoid too many stories on the same topic

MANDATORY REQUIREMENTS:
- Select EXACTLY 10 stories
- Include at least 1 political/government story (if available)
- Include at least 1 economic/business story (if available)  
- Include at least 1 international story (if available)
- Maximum 3 stories from any single category
- Prioritize stories with high importance_score but ensure variety

Return JSON only:
{
  "selections": [
    {
      "article_index": 0,
      "importance_rank": 1,
      "selection_reason": "Brief reason why this story is important",
      "enhanced_summary": "Comprehensive 3-4 sentence summary covering WHO, WHAT, WHERE, WHEN, WHY, and HOW - optimized for TTS delivery with specific details and context"
    }
  ]
}`
        },
        {
          role: 'user',
          content: `Select exactly 10 stories from these ${candidates.length} candidates for today's morning briefing:

${JSON.stringify(candidates.map((article, index) => ({
  index,
  title: article.title,
  description: article.description?.slice(0, 200),
  source: article.source,
  importance_score: article.importance_score,
  topic_category: article.topic_category,
  geographic_scope: article.geographic_scope,
  publishedAt: article.publishedAt
})), null, 2)}`
        }
      ],
      temperature: 0.3,
      max_tokens: 2000
    }
    
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 
        'Authorization': `Bearer ${openaiKey}`, 
        'Content-Type': 'application/json' 
      },
      body: JSON.stringify(payload)
    })
    
    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status}`)
    }
    
    const data = await response.json()
    const content = data.choices?.[0]?.message?.content
    
    if (!content) {
      throw new Error('No content in OpenAI response')
    }
    
    const parsed = JSON.parse(content)
    const selections = parsed.selections || []
    
    if (!Array.isArray(selections) || selections.length === 0) {
      throw new Error('Invalid selections format from OpenAI')
    }
    
    console.log(`[${requestId}] ✅ GPT-4o-mini selected ${selections.length} stories`)
    
    // Build final top 10 with AI enhancements
    return selections.map(selection => {
      const originalArticle = candidates[selection.article_index]
      if (!originalArticle) {
        console.warn(`[${requestId}] ⚠️ Invalid article index: ${selection.article_index}`)
        return null
      }
      
      return {
        ...originalArticle,
        ai_rank: selection.importance_rank,
        selection_reason: selection.selection_reason,
        ai_summary: selection.enhanced_summary || originalArticle.title,
        enhanced_summary: selection.enhanced_summary || originalArticle.description || originalArticle.title,
        id: originalArticle.url || `story_${selection.article_index}_${Date.now()}`
      }
    }).filter(Boolean).slice(0, 10) // Ensure exactly 10 and filter nulls
    
  } catch (error) {
    console.error(`[${requestId}] ❌ GPT-4o-mini selection failed:`, error)
    // Fallback to basic ranking
    return candidates.slice(0, 10).map((article, index) => ({
      ...article,
      ai_rank: index + 1,
      ai_summary: article.description || article.title,
      enhanced_summary: article.description || article.title,
      selection_reason: 'Fallback: High importance score',
      id: article.url || `story_fallback_${index}_${Date.now()}`
    }))
  }
}

// Enhanced compacting helpers with full 5W+H coverage
async function summarizeNewsMini(articles: any[] = [], sourceName: string = ''): Promise<any[]> {
  const openaiKey = Deno.env.get('OPENAI_API_KEY')
  if (!openaiKey || !Array.isArray(articles) || articles.length === 0) return []

  const payload = {
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `Create comprehensive, TTS-optimized news summaries for a morning briefing script.
Each summary must be 3-4 complete sentences covering WHO, WHAT, WHERE, WHEN, WHY, and HOW.

REQUIREMENTS:
- WHO: Key people, organizations, or entities involved
- WHAT: The specific event or development that happened
- WHERE: Geographic location or context
- WHEN: Timing (be specific about dates/timeframes)
- WHY: Background context, reasons, or motivations
- HOW: Process, method, or mechanism of the event

Make summaries detailed enough for a listener to understand the full story context.
Use natural, conversational language optimized for text-to-speech.
Include specific numbers, names, and concrete details when available.

Return strictly JSON: {"items": Array<CompactItem>}.
CompactItem fields:
- id: stable string (prefer url; else a 32-char hash of title)
- source: short source name
- publishedAt: ISO8601 if present
- description: 3-4 sentence comprehensive summary covering all 5W+H
- geo: one of local|state|national|international
- category: one of politics|business|tech|sports|weather|other
- key_entities: array of main people/organizations mentioned
- impact_level: one of high|medium|low`
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

Create comprehensive 3-4 sentence summaries for each article. Include WHO is involved, WHAT happened, WHERE it occurred, WHEN it took place, WHY it matters, and HOW it unfolded. Return JSON only.`
      }
    ],
    temperature: 0.2,
    max_tokens: 1500  // Increased for longer summaries
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
      description: String(it?.description || '').trim(),
      geo: it?.geo || 'national',
      category: it?.category || 'other',
      key_entities: Array.isArray(it?.key_entities) ? it.key_entities.map(String) : [],
      impact_level: it?.impact_level || 'medium'
    })).filter((it: any) => it.description && it.description.length > 50) // Ensure substantial content
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
    let description = ''
    if (status === 'FT') {
      description = `${home} beat ${away} ${hs}-${as}.`
    } else if (status === 'NS') {
      description = `${home} vs ${away} later today.`
    } else if (status === 'LIVE') {
      description = `${home} vs ${away} in progress.`
    } else {
      continue
    }
    out.push({ id: `${home}-${away}-${date}`, league: ev?.league || (data as any)?.league || '', date, status, description })
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
      description: line
    }
  })
}