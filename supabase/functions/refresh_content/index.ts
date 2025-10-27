import { serve } from "https://deno.land/std@0.208.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
// Local lint shim for Deno globals in non-Deno editors
declare const Deno: any

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
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

  // Bearer auth guard - service role key only
  const authHeader = req.headers.get('authorization') || ''
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

  if (!authHeader || !supabaseServiceKey || !safeEq(authHeader, `Bearer ${supabaseServiceKey}`)) {
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
      contentSources.push({ type: 'news', source: 'newsapi_local_us_major', ttlHours: 168, fetchFunction: () => fetchNewsAPILocalUSMajor() })
      contentSources.push({ type: 'news', source: 'newsapi_local_us_west', ttlHours: 168, fetchFunction: () => fetchNewsAPILocalUSWest() })
      contentSources.push({ type: 'news', source: 'newsapi_local_us_east', ttlHours: 168, fetchFunction: () => fetchNewsAPILocalUSEast() })
      contentSources.push({ type: 'news', source: 'newsapi_local_us_south', ttlHours: 168, fetchFunction: () => fetchNewsAPILocalUSSouth() })
      contentSources.push({ type: 'news', source: 'newsapi_local_us_midwest', ttlHours: 168, fetchFunction: () => fetchNewsAPILocalUSMidwest() })
      contentSources.push({ type: 'news', source: 'newsapi_state_issues', ttlHours: 168, fetchFunction: () => fetchNewsAPIStateIssues() })
    } else { missingEnvs.push('NEWSAPI_KEY') }
    if (Deno.env.get('GNEWS_API_KEY')) {
      contentSources.push({ type: 'news', source: 'gnews_comprehensive', ttlHours: 168, fetchFunction: () => fetchGNewsComprehensive() })
    } else { missingEnvs.push('GNEWS_API_KEY') }
    if (Deno.env.get('THENEWSAPI_KEY')) {
      contentSources.push({ type: 'news', source: 'thenewsapi_general', ttlHours: 168, fetchFunction: () => fetchTheNewsAPI() })
    } else { missingEnvs.push('THENEWSAPI_KEY') }
    if (Deno.env.get('NEWSDATA_IO_KEY')) {
      contentSources.push({ type: 'news', source: 'newsdata_io_latest', ttlHours: 168, fetchFunction: () => fetchNewsDataIO() })
    } else { missingEnvs.push('NEWSDATA_IO_KEY') }
    if (Deno.env.get('NEWSAPI_AI_KEY')) {
      contentSources.push({ type: 'news', source: 'newsapi_ai_general', ttlHours: 168, fetchFunction: () => fetchNewsAPIAI() })
    } else { missingEnvs.push('NEWSAPI_AI_KEY') }
    if (Deno.env.get('RAPIDAPI_KEY')) {
      contentSources.push({ type: 'stocks', source: 'yahoo_finance', ttlHours: 168, fetchFunction: () => fetchYahooFinance(supabase) })
    } else { missingEnvs.push('RAPIDAPI_KEY') }
    contentSources.push({ type: 'sports', source: 'espn', ttlHours: 168, fetchFunction: () => fetchESPN() })
    if (Deno.env.get('SPORTSDB_API')) {
      contentSources.push({ type: 'sports', source: 'thesportdb', ttlHours: 168, fetchFunction: () => fetchTheSportDB() })
    } else { missingEnvs.push('SPORTSDB_API') }

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
              // Enhanced sports processing with intelligence
              const games = Array.isArray((data as any)?.games) ? (data as any).games : Array.isArray((data as any)?.events) ? (data as any).events : []
              
              if (games.length > 0) {
                // Apply sports intelligence enhancement
                const enhancedGames = games.map(game => enhanceGameWithIntelligence(game, source.source))
                
                // Store enhanced games in data
                if ((data as any).games) {
                  ;(data as any).games = enhancedGames
                } else if ((data as any).events) {
                  ;(data as any).events = enhancedGames
                }
                
                // Create compact sports for backwards compatibility
                const compactSports = compactSportsLocal(data)
                if (Array.isArray(compactSports) && compactSports.length > 0) {
                  ;(data as any).compact = { ...((data as any).compact || {}), sports: compactSports.slice(0, 24) }
                }
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

// Major US Cities and Metro Areas
async function fetchNewsAPILocalUSMajor(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // Major cities across all regions - broad appeal
  const searchTerms = '"New York" OR "Los Angeles" OR "Chicago" OR "Houston" OR "Phoenix" OR "Philadelphia" OR "San Antonio" OR "San Diego" OR "Dallas" OR "Austin" OR "Jacksonville" OR "Fort Worth" OR "Columbus" OR "Charlotte" OR "San Francisco" OR "Indianapolis" OR "Seattle" OR "Denver" OR "Boston" OR "Nashville"'
  const from = new Date(Date.now() - 18 * 60 * 60 * 1000).toISOString() // Last 18 hours

  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=publishedAt&from=${from}&pageSize=40&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Local US Major error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'local_us_major'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_local_us_major',
    endpoint: 'everything/local_us_major',
    search_terms: searchTerms
  }
}

// West Coast Regional News
async function fetchNewsAPILocalUSWest(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // West Coast cities, counties, and regional terms
  const searchTerms = '"California" OR "Oregon" OR "Washington" OR "Nevada" OR "San Francisco" OR "Bay Area" OR "Los Angeles" OR "Orange County" OR "San Diego" OR "Sacramento" OR "Fresno" OR "Long Beach" OR "Oakland" OR "Bakersfield" OR "Anaheim" OR "Santa Ana" OR "Riverside" OR "Stockton" OR "Irvine" OR "Fremont" OR "Portland" OR "Seattle" OR "Spokane" OR "Tacoma" OR "Vancouver" OR "Bellevue" OR "Las Vegas" OR "Henderson" OR "Reno"'
  const from = new Date(Date.now() - 18 * 60 * 60 * 1000).toISOString()

  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=publishedAt&from=${from}&pageSize=35&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Local US West error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'local_us_west'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_local_us_west',
    endpoint: 'everything/local_us_west',
    search_terms: searchTerms
  }
}

// East Coast Regional News
async function fetchNewsAPILocalUSEast(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // East Coast cities, counties, and regional terms
  const searchTerms = '"New York" OR "New Jersey" OR "Pennsylvania" OR "Connecticut" OR "Massachusetts" OR "Rhode Island" OR "Vermont" OR "New Hampshire" OR "Maine" OR "Maryland" OR "Delaware" OR "Virginia" OR "North Carolina" OR "South Carolina" OR "Georgia" OR "Florida" OR "Manhattan" OR "Brooklyn" OR "Queens" OR "Bronx" OR "Staten Island" OR "Long Island" OR "Philadelphia" OR "Pittsburgh" OR "Boston" OR "Cambridge" OR "Worcester" OR "Providence" OR "Hartford" OR "Bridgeport" OR "New Haven" OR "Baltimore" OR "Virginia Beach" OR "Norfolk" OR "Richmond" OR "Newport News" OR "Alexandria" OR "Portsmouth" OR "Chesapeake" OR "Atlanta" OR "Columbus" OR "Augusta" OR "Savannah" OR "Miami" OR "Tampa" OR "Orlando" OR "Jacksonville" OR "St. Petersburg" OR "Hialeah" OR "Tallahassee" OR "Fort Lauderdale" OR "Port St. Lucie" OR "Pembroke Pines" OR "Cape Coral" OR "Hollywood" OR "Gainesville" OR "Miramar" OR "Coral Springs"'
  const from = new Date(Date.now() - 18 * 60 * 60 * 1000).toISOString()

  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=publishedAt&from=${from}&pageSize=35&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Local US East error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'local_us_east'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_local_us_east',
    endpoint: 'everything/local_us_east',
    search_terms: searchTerms
  }
}

// Southern Regional News
async function fetchNewsAPILocalUSSouth(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // Southern states, cities, and regional terms
  const searchTerms = '"Texas" OR "Florida" OR "Georgia" OR "North Carolina" OR "Virginia" OR "Tennessee" OR "Louisiana" OR "South Carolina" OR "Alabama" OR "Kentucky" OR "Oklahoma" OR "Arkansas" OR "Mississippi" OR "West Virginia" OR "Houston" OR "San Antonio" OR "Dallas" OR "Austin" OR "Fort Worth" OR "El Paso" OR "Charlotte" OR "Jacksonville" OR "Memphis" OR "Nashville" OR "Louisville" OR "New Orleans" OR "Baton Rouge" OR "Birmingham" OR "Huntsville" OR "Mobile" OR "Montgomery" OR "Little Rock" OR "Fayetteville" OR "Jackson" OR "Gulfport" OR "Tulsa" OR "Oklahoma City" OR "Charleston" OR "Columbia" OR "Greenville" OR "Myrtle Beach" OR "Knoxville" OR "Chattanooga" OR "Clarksville" OR "Murfreesboro"'
  const from = new Date(Date.now() - 18 * 60 * 60 * 1000).toISOString()

  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=publishedAt&from=${from}&pageSize=35&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Local US South error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'local_us_south'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_local_us_south',
    endpoint: 'everything/local_us_south',
    search_terms: searchTerms
  }
}

// Midwest Regional News
async function fetchNewsAPILocalUSMidwest(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // Midwest states, cities, and regional terms
  const searchTerms = '"Illinois" OR "Ohio" OR "Michigan" OR "Indiana" OR "Wisconsin" OR "Minnesota" OR "Iowa" OR "Missouri" OR "Kansas" OR "Nebraska" OR "North Dakota" OR "South Dakota" OR "Chicago" OR "Columbus" OR "Indianapolis" OR "Detroit" OR "Milwaukee" OR "Kansas City" OR "Omaha" OR "Minneapolis" OR "St. Paul" OR "Wichita" OR "Cleveland" OR "Cincinnati" OR "Toledo" OR "Akron" OR "Dayton" OR "Grand Rapids" OR "Warren" OR "Sterling Heights" OR "Lansing" OR "Ann Arbor" OR "Flint" OR "Dearborn" OR "Madison" OR "Green Bay" OR "Kenosha" OR "Racine" OR "Appleton" OR "St. Louis" OR "Springfield" OR "Independence" OR "Columbia" OR "Lee\'s Summit" OR "O\'Fallon" OR "St. Joseph" OR "Des Moines" OR "Cedar Rapids" OR "Davenport" OR "Sioux City" OR "Waterloo"'
  const from = new Date(Date.now() - 18 * 60 * 60 * 1000).toISOString()

  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=publishedAt&from=${from}&pageSize=35&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI Local US Midwest error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'local_us_midwest'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_local_us_midwest',
    endpoint: 'everything/local_us_midwest',
    search_terms: searchTerms
  }
}

// State-Level Policy and Government Issues
async function fetchNewsAPIStateIssues(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  // State-level government, policy, and regional issues
  const searchTerms = '("governor" OR "state legislature" OR "state senate" OR "state house" OR "state budget" OR "state tax" OR "state law" OR "ballot measure" OR "proposition" OR "referendum") AND ("California" OR "Texas" OR "Florida" OR "New York" OR "Pennsylvania" OR "Illinois" OR "Ohio" OR "Georgia" OR "North Carolina" OR "Michigan" OR "New Jersey" OR "Virginia" OR "Washington" OR "Arizona" OR "Massachusetts" OR "Tennessee" OR "Indiana" OR "Missouri" OR "Maryland" OR "Wisconsin" OR "Colorado" OR "Minnesota" OR "South Carolina" OR "Alabama" OR "Louisiana" OR "Kentucky" OR "Oregon" OR "Oklahoma" OR "Connecticut" OR "Utah" OR "Iowa" OR "Nevada" OR "Arkansas" OR "Mississippi" OR "Kansas" OR "New Mexico" OR "Nebraska" OR "West Virginia" OR "Idaho" OR "Hawaii" OR "New Hampshire" OR "Maine" OR "Montana" OR "Rhode Island" OR "Delaware" OR "South Dakota" OR "North Dakota" OR "Alaska" OR "Vermont" OR "Wyoming")'
  const from = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString() // Last 24 hours

  const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(searchTerms)}&language=en&sortBy=publishedAt&from=${from}&pageSize=30&apiKey=${apiKey}`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI State Issues error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: (data.articles || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.publishedAt || '',
      source: a.source?.name || 'NewsAPI',
      category: 'local_us_state'
    })),
    total_results: data.totalResults,
    fetched_at: new Date().toISOString(),
    source: 'newsapi_state_issues',
    endpoint: 'everything/state_issues',
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

// TheNewsAPI.com fetch function
async function fetchTheNewsAPI(): Promise<any> {
  const apiKey = Deno.env.get('THENEWSAPI_KEY')
  if (!apiKey) throw new Error('THENEWSAPI_KEY not configured')

  const url = `https://api.thenewsapi.com/v1/news/all?api_token=${apiKey}&language=en&limit=25&sort=published_on`
  const data = await getJSON<any>(url)
  
  if (!data.data) {
    throw new Error(`TheNewsAPI error: ${data.message || 'No articles returned'}`)
  }

  return {
    articles: (data.data || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.url || '',
      publishedAt: a.published_on || '',
      source: a.source || 'TheNewsAPI',
      category: (a.categories && a.categories.length > 0) ? a.categories[0] : 'general'
    })),
    total_results: data.meta?.found || data.data.length,
    fetched_at: new Date().toISOString(),
    source: 'thenewsapi_general',
    endpoint: 'news/all'
  }
}

// NewsData.io fetch function
async function fetchNewsDataIO(): Promise<any> {
  const apiKey = Deno.env.get('NEWSDATA_IO_KEY')
  if (!apiKey) throw new Error('NEWSDATA_IO_KEY not configured')

  const url = `https://newsdata.io/api/1/latest?apikey=${apiKey}&country=us&language=en&size=25`
  const data = await getJSON<any>(url)
  
  if (data.status !== 'success') {
    throw new Error(`NewsData.io error: ${data.message || 'API request failed'}`)
  }

  return {
    articles: (data.results || []).map((a: any) => ({
      title: a.title || '',
      description: String(a.description || '').slice(0, 300),
      url: a.link || '',
      publishedAt: a.pubDate || '',
      source: a.source_id || 'NewsData.io',
      category: (a.category && a.category.length > 0) ? a.category[0] : 'general'
    })),
    total_results: data.totalResults || data.results?.length || 0,
    fetched_at: new Date().toISOString(),
    source: 'newsdata_io_latest',
    endpoint: 'latest'
  }
}

// NewsAPI.ai fetch function (placeholder - will need specific endpoint research)
async function fetchNewsAPIAI(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_AI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_AI_KEY not configured')

  // Note: This is a placeholder URL - actual endpoint needs to be researched
  // Based on research, NewsAPI.ai may require different authentication method
  const url = `https://eventregistry.org/api/v1/article/getArticles?apiKey=${apiKey}&resultType=articles&articlesCount=25&lang=eng`
  
  try {
    const data = await getJSON<any>(url)
    
    if (!data.articles) {
      throw new Error(`NewsAPI.ai error: ${data.error?.message || 'No articles returned'}`)
    }

    return {
      articles: (data.articles.results || []).map((a: any) => ({
        title: a.title || '',
        description: String(a.body || a.summary || '').slice(0, 300),
        url: a.url || '',
        publishedAt: a.dateTime || a.date || '',
        source: a.source?.title || 'NewsAPI.ai',
        category: 'general'
      })),
      total_results: data.articles.totalResults || data.articles.results?.length || 0,
      fetched_at: new Date().toISOString(),
      source: 'newsapi_ai_general',
      endpoint: 'articles'
    }
  } catch (error) {
    // If the endpoint is incorrect, log error but don't fail completely
    console.error('NewsAPI.ai fetch failed (endpoint may need correction):', error)
    throw new Error(`NewsAPI.ai configuration needs verification: ${error.message}`)
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
    // Market indices
    '^GSPC', '^DJI',
    // Popular ETFs and stocks
    'SPY', 'QQQ', 'DIA', 'IWM', 'VTI', 'VOO', 'JPM', 'JNJ', 'V', 'PG', 'UNH',
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

// ESPN API fetch function - Multi-sport comprehensive
async function fetchESPN(): Promise<any> {
  const sports = [
    { league: 'NFL', path: 'football/nfl', limit: 8 },
    { league: 'NCAAF', path: 'football/college-football', limit: 6 },
    { league: 'MLB', path: 'baseball/mlb', limit: 8 },
    { league: 'NBA', path: 'basketball/nba', limit: 6 },
    { league: 'NHL', path: 'hockey/nhl', limit: 6 }
  ];

  const allGames: any[] = [];
  const sportsBreakdown: any = {};
  const successfulFetches: string[] = [];
  const failedFetches: string[] = [];

  // Check if we're in October (World Series season) for enhanced MLB fetching
  const currentMonth = new Date().getMonth() + 1; // 1-12
  const isOctoberPlayoffs = currentMonth === 10;

  // Fetch all sports in parallel
  const fetchPromises = sports.map(async (sport) => {
    try {
      let allSportGames: any[] = [];

      // Enhanced MLB fetching during October (World Series season)
      if (sport.league === 'MLB' && isOctoberPlayoffs) {
        console.log(`[ESPN] Enhanced October MLB fetching - checking multiple date ranges`);
        
        // Get dates for the past 2 days + today + tomorrow  
        const dates = [];
        for (let i = -2; i <= 1; i++) {
          const date = new Date();
          date.setDate(date.getDate() + i);
          dates.push(date.toISOString().split('T')[0].replace(/-/g, ''));
        }

        // Fetch multiple date ranges for comprehensive World Series coverage
        const mlbFetchPromises = dates.map(async (dateStr) => {
          try {
            const dateUrl = `https://site.api.espn.com/apis/site/v2/sports/${sport.path}/scoreboard?dates=${dateStr}`;
            console.log(`[ESPN] Fetching MLB for date ${dateStr} from ${dateUrl}`);
            const dateData = await getJSON<any>(dateUrl);
            
            const dateGames = dateData.events?.map((event: any) => ({
              id: event.id,
              date: event.date,
              name: event.name,
              status: event.status?.type?.name || 'UNKNOWN',
              league: sport.league,
              competitors: event.competitions?.[0]?.competitors?.map((comp: any) => ({
                team: comp.team?.displayName || 'Unknown',
                score: comp.score || '0',
                record: comp.records?.[0]?.summary || ''
              })) || []
            })) || [];
            
            console.log(`[ESPN] Found ${dateGames.length} MLB games for ${dateStr}`);
            return dateGames;
          } catch (error) {
            console.warn(`[ESPN] Failed to fetch MLB for date ${dateStr}:`, error);
            return [];
          }
        });

        const mlbResults = await Promise.all(mlbFetchPromises);
        allSportGames = mlbResults.flat();
        
        // Remove duplicates by game ID
        const uniqueGames = new Map();
        allSportGames.forEach(game => {
          if (!uniqueGames.has(game.id)) {
            uniqueGames.set(game.id, game);
          }
        });
        allSportGames = Array.from(uniqueGames.values());
        
        // Sort by date (most recent first) and limit
        allSportGames.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
        allSportGames = allSportGames.slice(0, sport.limit);
        
        console.log(`[ESPN] Enhanced MLB fetch complete: ${allSportGames.length} unique games across ${dates.length} days`);
      } else {
        // Standard single-day fetch for other sports and non-October MLB
        const url = `https://site.api.espn.com/apis/site/v2/sports/${sport.path}/scoreboard`;
        console.log(`[ESPN] Standard fetching ${sport.league} from ${url}`);
        
        const data = await getJSON<any>(url);
        
        allSportGames = data.events?.slice(0, sport.limit).map((event: any) => ({
          id: event.id,
          date: event.date,
          name: event.name,
          status: event.status?.type?.name || 'UNKNOWN',
          league: sport.league,
          competitors: event.competitions?.[0]?.competitors?.map((comp: any) => ({
            team: comp.team?.displayName || 'Unknown',
            score: comp.score || '0',
            record: comp.records?.[0]?.summary || ''
          })) || []
        })) || [];
      }

      // Add to combined games array
      allGames.push(...allSportGames);
      
      // Store breakdown by sport
      sportsBreakdown[sport.league.toLowerCase()] = {
        games: allSportGames,
        total_events: allSportGames.length,
        fetched_games: allSportGames.length,
        enhanced_fetch: sport.league === 'MLB' && isOctoberPlayoffs
      };
      
      successfulFetches.push(sport.league);
      console.log(`[ESPN] Successfully fetched ${allSportGames.length} ${sport.league} games`);
      
      return { sport: sport.league, success: true, count: allSportGames.length };
    } catch (error) {
      console.warn(`[ESPN] Failed to fetch ${sport.league}:`, error);
      failedFetches.push(sport.league);
      return { sport: sport.league, success: false, error: error.message };
    }
  });

  // Wait for all fetches to complete
  const results = await Promise.allSettled(fetchPromises);
  
  // Sort games by date (most recent first)
  allGames.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());

  const summary = {
    total_games: allGames.length,
    successful_sports: successfulFetches,
    failed_sports: failedFetches,
    sports_fetched: successfulFetches.length,
    sports_failed: failedFetches.length
  };

  console.log(`[ESPN] Multi-sport fetch complete:`, summary);

  return {
    games: allGames,
    leagues: successfulFetches,
    sports_breakdown: sportsBreakdown,
    fetch_summary: summary,
    fetched_at: new Date().toISOString(),
    source: 'espn'
  };
}

// TheSportDB API fetch function
async function fetchTheSportDB(): Promise<any> {
  const apiKey = Deno.env.get('SPORTSDB_API')
  if (!apiKey) throw new Error('SPORTSDB_API not configured')

  // Get today's and tomorrow's dates in YYYY-MM-DD format
  const today = new Date().toISOString().split('T')[0]
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().split('T')[0]
  
  // Fetch both today and tomorrow to catch events that slip to next day due to UTC
  const [todayData, tomorrowData] = await Promise.all([
    getJSON<any>(`https://www.thesportsdb.com/api/v1/json/${apiKey}/eventsday.php?d=${today}`),
    getJSON<any>(`https://www.thesportsdb.com/api/v1/json/${apiKey}/eventsday.php?d=${tomorrow}`)
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
  const importanceScore = calculateImportanceScore(article)
  const topicCategory = categorizeStory(article)
  const geographicScope = determineGeographicScope(article)
  const editorialWeight = calculateEditorialWeight(article, importanceScore)
  const breakingNewsSpots = calculateBreakingNewsSpots(article, importanceScore, editorialWeight)
  const userGeographicRelevance = calculateUserGeographicRelevance(article)

  return {
    ...article,
    importance_score: importanceScore,
    topic_category: topicCategory,
    geographic_scope: geographicScope,
    editorial_weight: editorialWeight, // front_page, page_3, buried
    breaking_news_spots: breakingNewsSpots, // 1, 2, or 3 spots needed
    user_geographic_relevance: userGeographicRelevance, // Per major metro area
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

// Calculate editorial weight - "NYT font size" concept
function calculateEditorialWeight(article: any, importanceScore: number): string {
  const text = `${article.title || ''} ${article.description || ''}`.toLowerCase()
  
  // Front page criteria (major breaking news)
  if (importanceScore >= 70) return 'front_page'
  
  // Additional front page triggers regardless of score
  if (text.includes('breaking') || text.includes('urgent') || text.includes('live update')) return 'front_page'
  if (text.includes('declares war') || text.includes('nuclear') || text.includes('assassination')) return 'front_page'
  if (text.includes('9/11') || text.includes('terror attack') || text.includes('mass shooting')) return 'front_page'
  if (text.includes('election results') || text.includes('winner declared') || text.includes('victory speech')) return 'front_page'
  if (text.includes('stock market crash') || text.includes('market plunge') || text.includes('dow jones falls')) return 'front_page'
  if (text.includes('natural disaster') || text.includes('hurricane makes landfall') || text.includes('earthquake')) return 'front_page'
  if (text.includes('supreme court rules') || text.includes('landmark decision') || text.includes('constitutional')) return 'front_page'
  
  // Page 3 criteria (significant but not breaking)
  if (importanceScore >= 40) return 'page_3'
  if (text.includes('congress passes') || text.includes('senate votes') || text.includes('house approves')) return 'page_3'
  if (text.includes('federal reserve') || text.includes('interest rates') || text.includes('inflation report')) return 'page_3'
  if (text.includes('earnings report') && (text.includes('billion') || text.includes('beats expectations'))) return 'page_3'
  if (text.includes('investigation launched') || text.includes('charges filed') || text.includes('lawsuit')) return 'page_3'
  
  // Everything else is buried
  return 'buried'
}

// Calculate how many news spots this story deserves
function calculateBreakingNewsSpots(article: any, importanceScore: number, editorialWeight: string): number {
  const text = `${article.title || ''} ${article.description || ''}`.toLowerCase()
  
  // 3 spots for massive breaking news (2-3 times per year events)
  if (editorialWeight === 'front_page' && importanceScore >= 85) {
    if (text.includes('declares war') || text.includes('president') && (text.includes('dies') || text.includes('resigns'))) return 3
    if (text.includes('nuclear') || text.includes('9/11') || text.includes('assassination')) return 3
    if (text.includes('election night') && text.includes('winner') || text.includes('victory speech')) return 3
    if (text.includes('stock market crash') || text.includes('dow jones') && text.includes('plunge')) return 3
  }
  
  // 2 spots for major breaking news
  if (editorialWeight === 'front_page') {
    if (text.includes('breaking') || text.includes('urgent') || text.includes('developing')) return 2
    if (text.includes('supreme court') || text.includes('federal reserve') || text.includes('interest rates')) return 2
    if (text.includes('hurricane') || text.includes('earthquake') || text.includes('natural disaster')) return 2
    if (text.includes('election results') || text.includes('votes certified')) return 2
  }
  
  // Default to 1 spot
  return 1
}

// Calculate geographic relevance for major US metro areas
function calculateUserGeographicRelevance(article: any): Record<string, number> {
  const text = `${article.title || ''} ${article.description || ''}`.toLowerCase()
  const relevance: Record<string, number> = {}
  
  // Major metro areas and their keywords
  const metroAreas = {
    'los_angeles': ['los angeles', 'la county', 'hollywood', 'beverly hills', 'santa monica', 'pasadena', 'glendale', 'burbank', 'culver city', 'west hollywood', 'venice', 'manhattan beach', 'redondo beach', 'el segundo', 'torrance', 'carson', 'compton', 'long beach', 'anaheim', 'santa ana', 'irvine', 'huntington beach', 'orange county', 'oc'],
    'new_york': ['new york', 'nyc', 'manhattan', 'brooklyn', 'queens', 'bronx', 'staten island', 'long island', 'nassau county', 'suffolk county', 'westchester', 'new jersey', 'nj', 'jersey city', 'newark', 'hoboken'],
    'chicago': ['chicago', 'cook county', 'illinois', 'aurora', 'rockford', 'joliet', 'naperville', 'schaumburg', 'evanston', 'des plaines', 'arlington heights', 'palatine'],
    'houston': ['houston', 'harris county', 'texas', 'sugar land', 'baytown', 'conroe', 'galveston', 'pasadena', 'pearland', 'league city', 'missouri city'],
    'phoenix': ['phoenix', 'arizona', 'scottsdale', 'tempe', 'mesa', 'glendale', 'peoria', 'surprise', 'avondale', 'goodyear', 'buckeye'],
    'philadelphia': ['philadelphia', 'pennsylvania', 'camden', 'chester', 'wilmington', 'delaware', 'reading', 'allentown', 'bethlehem'],
    'san_antonio': ['san antonio', 'texas', 'bexar county', 'new braunfels', 'seguin', 'universal city', 'converse', 'live oak'],
    'san_diego': ['san diego', 'california', 'chula vista', 'oceanside', 'escondido', 'carlsbad', 'vista', 'san marcos', 'encinitas'],
    'dallas': ['dallas', 'texas', 'fort worth', 'arlington', 'plano', 'garland', 'irving', 'grand prairie', 'mesquite', 'richardson', 'carrollton'],
    'san_francisco': ['san francisco', 'bay area', 'california', 'oakland', 'san jose', 'fremont', 'hayward', 'sunnyvale', 'santa clara', 'mountain view', 'palo alto', 'redwood city', 'san mateo', 'daly city'],
    'austin': ['austin', 'texas', 'travis county', 'round rock', 'cedar park', 'pflugerville', 'leander', 'georgetown'],
    'jacksonville': ['jacksonville', 'florida', 'duval county', 'orange park', 'neptune beach', 'atlantic beach'],
    'seattle': ['seattle', 'washington', 'bellevue', 'tacoma', 'spokane', 'vancouver', 'kent', 'everett', 'renton', 'federal way', 'redmond'],
    'denver': ['denver', 'colorado', 'aurora', 'lakewood', 'thornton', 'arvada', 'westminster', 'centennial', 'boulder', 'fort collins'],
    'boston': ['boston', 'massachusetts', 'cambridge', 'quincy', 'lynn', 'brockton', 'new bedford', 'fall river', 'newton', 'somerville', 'framingham', 'haverhill'],
    'detroit': ['detroit', 'michigan', 'warren', 'sterling heights', 'ann arbor', 'lansing', 'flint', 'dearborn', 'livonia'],
    'nashville': ['nashville', 'tennessee', 'davidson county', 'murfreesboro', 'franklin', 'hendersonville', 'smyrna', 'brentwood'],
    'portland': ['portland', 'oregon', 'gresham', 'hillsboro', 'beaverton', 'bend', 'medford', 'springfield', 'corvallis'],
    'las_vegas': ['las vegas', 'nevada', 'henderson', 'north las vegas', 'reno', 'sparks', 'carson city'],
    'atlanta': ['atlanta', 'georgia', 'columbus', 'augusta', 'savannah', 'athens', 'sandy springs', 'roswell', 'johns creek', 'albany']
  }
  
  // Calculate relevance scores
  for (const [metro, keywords] of Object.entries(metroAreas)) {
    let score = 0
    
    for (const keyword of keywords) {
      if (text.includes(keyword)) {
        // Boost for exact city name matches
        if (keyword === metro.replace('_', ' ')) {
          score += 10
        } else {
          score += 5
        }
      }
    }
    
    // State-level relevance gets lower score
    const state = getStateForMetro(metro)
    if (state && text.includes(state)) {
      score += 2
    }
    
    relevance[metro] = Math.min(score, 20) // Cap at 20
  }
  
  return relevance
}

// Helper to get state for metro area
function getStateForMetro(metro: string): string {
  const stateMap: Record<string, string> = {
    'los_angeles': 'california', 'san_francisco': 'california', 'san_diego': 'california',
    'new_york': 'new york', 'houston': 'texas', 'dallas': 'texas', 'san_antonio': 'texas', 'austin': 'texas',
    'chicago': 'illinois', 'phoenix': 'arizona', 'philadelphia': 'pennsylvania',
    'jacksonville': 'florida', 'seattle': 'washington', 'denver': 'colorado',
    'boston': 'massachusetts', 'detroit': 'michigan', 'nashville': 'tennessee',
    'portland': 'oregon', 'las_vegas': 'nevada', 'atlanta': 'georgia'
  }
  return stateMap[metro] || ''
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

CRITICAL POLITICAL ACCURACY:
- Donald Trump is the CURRENT President of the United States (as of January 20, 2025)
- ALWAYS refer to him as "President Donald Trump" or "President Trump" - NEVER as "former president"
- Joe Biden is now the FORMER president - refer to him as "former President Biden" if mentioned
- Double-check any political references to ensure they reflect current reality

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

CRITICAL POLITICAL ACCURACY:
- Donald Trump is the CURRENT President of the United States (as of January 20, 2025)
- ALWAYS refer to him as "President Donald Trump" or "President Trump" - NEVER as "former president"
- Joe Biden is now the FORMER president - refer to him as "former President Biden" if mentioned
- Double-check any political references to ensure they reflect current reality

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

// ============================================================================
// ENHANCED SPORTS INTELLIGENCE SYSTEM
// ============================================================================

// Sports intelligence enhancement for individual games
function enhanceGameWithIntelligence(game: any, sourceName: string): any {
  const significanceScore = calculateSportsSignificance(game)
  const gameType = classifyGameType(game)
  const seasonalContext = getSeasonalContext(game)
  const sportsSpots = calculateSportsSpots(game, significanceScore, gameType)
  const userLocationRelevance = calculateSportsLocationRelevance(game)

  return {
    ...game,
    significance_score: significanceScore,
    game_type: gameType, // championship, playoff, season_opener, rivalry, regular
    seasonal_context: seasonalContext, // peak_season, playoff_season, off_season
    sports_spots: sportsSpots, // 1, 2, or 3 spots needed
    user_location_relevance: userLocationRelevance, // Per major metro area
    enhanced_at: new Date().toISOString(),
    source_name: sourceName
  }
}

// Calculate sports significance score (0-100)
function calculateSportsSignificance(game: any): number {
  let score = 0
  const gameTitle = `${game.name || ''} ${game.event || ''}`.toLowerCase()
  const league = (game.league || '').toLowerCase()
  const status = (game.status || '').toLowerCase()
  
  // Base league importance (adjusted for current season timing)
  const currentMonth = new Date().getMonth() + 1 // 1-12
  
  // Comprehensive seasonal adjustments by month
  if (currentMonth === 1) { // January - NFL playoffs, College championship
    if (league === 'nfl') score += 30 // Playoff season (highest priority)
    else if (league === 'ncaaf') score += 25 // Championship game
    else if (league === 'nba') score += 18 // Mid-season
    else if (league === 'nhl') score += 16 // Mid-season
    else if (league === 'mlb') score += 5 // Off-season
  } else if (currentMonth === 2) { // February - Super Bowl
    if (league === 'nfl') score += 35 // Super Bowl (maximum priority)
    else if (league === 'nba') score += 20 // All-Star period
    else if (league === 'nhl') score += 18 // All-Star period
    else if (league === 'mlb') score += 8 // Spring training
    else if (league === 'ncaaf') score += 5 // Off-season
  } else if (currentMonth === 3) { // March - Basketball playoff push
    if (league === 'nba') score += 22 // Playoff push
    else if (league === 'nhl') score += 20 // Playoff push
    else if (league === 'mlb') score += 10 // Spring training
    else if (league === 'nfl') score += 5 // Off-season
    else if (league === 'ncaaf') score += 5 // Off-season
  } else if (currentMonth === 4) { // April - NBA/NHL playoffs, MLB starts
    if (league === 'nba') score += 28 // Playoff season
    else if (league === 'nhl') score += 26 // Playoff season
    else if (league === 'mlb') score += 22 // Opening Day excitement
    else if (league === 'nfl') score += 5 // Off-season
    else if (league === 'ncaaf') score += 5 // Off-season
  } else if (currentMonth === 5) { // May - Championship rounds
    if (league === 'nba') score += 26 // Conference Finals
    else if (league === 'nhl') score += 24 // Conference Finals
    else if (league === 'mlb') score += 16 // Early season
    else if (league === 'nfl') score += 5 // Off-season
    else if (league === 'ncaaf') score += 5 // Off-season
  } else if (currentMonth === 6) { // June - Championships
    if (league === 'nba') score += 30 // NBA Finals
    else if (league === 'nhl') score += 28 // Stanley Cup Finals
    else if (league === 'mlb') score += 18 // Peak season
    else if (league === 'nfl') score += 5 // Off-season
    else if (league === 'ncaaf') score += 5 // Off-season
  } else if (currentMonth === 7) { // July - Baseball only
    if (league === 'mlb') score += 20 // All-Star break, peak season
    else if (league === 'nfl') score += 5 // Off-season
    else if (league === 'nba') score += 5 // Off-season
    else if (league === 'nhl') score += 5 // Off-season
    else if (league === 'ncaaf') score += 5 // Off-season
  } else if (currentMonth === 8) { // August - Football returns
    if (league === 'mlb') score += 18 // Peak season
    else if (league === 'ncaaf') score += 20 // Season starts
    else if (league === 'nfl') score += 12 // Preseason
    else if (league === 'nba') score += 5 // Off-season
    else if (league === 'nhl') score += 5 // Off-season
  } else if (currentMonth === 9) { // September - Football peak, baseball playoffs
    if (league === 'nfl') score += 22 // Season starts
    else if (league === 'ncaaf') score += 20 // Peak season
    else if (league === 'mlb') score += 24 // Playoff push
    else if (league === 'nhl') score += 8 // Preseason
    else if (league === 'nba') score += 5 // Off-season
  } else if (currentMonth === 10) { // October - MLB playoffs, seasons start
    if (league === 'mlb') score += 28 // Playoff season (highest priority)
    else if (league === 'nfl') score += 20 // Peak season
    else if (league === 'ncaaf') score += 18 // Peak season
    else if (league === 'nba') score += 20 // Season opener excitement
    else if (league === 'nhl') score += 15 // Season starts
  } else if (currentMonth === 11) { // November - Football peak, World Series
    if (league === 'mlb') score += 30 // World Series
    else if (league === 'nfl') score += 22 // Peak season
    else if (league === 'ncaaf') score += 24 // Conference championships
    else if (league === 'nba') score += 16 // Early season
    else if (league === 'nhl') score += 14 // Early season
  } else if (currentMonth === 12) { // December - Football playoffs, basketball/hockey peak
    if (league === 'nfl') score += 26 // Playoff push
    else if (league === 'ncaaf') score += 25 // CFP Semifinals
    else if (league === 'nba') score += 18 // Peak season
    else if (league === 'nhl') score += 16 // Peak season
    else if (league === 'mlb') score += 5 // Off-season
  } else {
    // Fallback scoring if month logic fails
    if (league === 'nfl') score += 20
    else if (league === 'nba') score += 18
    else if (league === 'mlb') score += 16
    else if (league === 'nhl') score += 14
    else if (league === 'ncaaf') score += 12
  }
  
  // Championship and playoff indicators
  if (gameTitle.includes('world series')) score += 40
  if (gameTitle.includes('finals')) score += 35
  if (gameTitle.includes('championship')) score += 30
  if (gameTitle.includes('playoff')) score += 25
  if (gameTitle.includes('division series') || gameTitle.includes('alds') || gameTitle.includes('nlds')) score += 25
  if (gameTitle.includes('wild card')) score += 20
  if (gameTitle.includes('conference championship')) score += 30
  if (gameTitle.includes('super bowl')) score += 50

  // Enhanced World Series detection for October
  if (league === 'mlb' && currentMonth === 10) {
    const currentDate = new Date()
    const dayOfMonth = currentDate.getDate()
    
    // Late October (25-31) - likely World Series games
    if (dayOfMonth >= 25) {
      score += 35 // Treat all late October MLB games as World Series level
      console.log(`[Sports Intelligence] Late October MLB boost applied: +35 for ${gameTitle}`)
    }
    
    // Any October MLB game gets playoff treatment
    score += 20
    console.log(`[Sports Intelligence] October MLB playoff boost applied: +20 for ${gameTitle}`)
  }

  // Dodgers boost for LA users during October playoffs
  if (league === 'mlb' && currentMonth === 10 && gameTitle.includes('dodgers')) {
    score += 25 // Extra boost for Dodgers during playoffs
    console.log(`[Sports Intelligence] Dodgers playoff boost applied: +25 for ${gameTitle}`)
  }
  
  // Season context
  if (gameTitle.includes('season opener') || gameTitle.includes('home opener')) score += 20
  if (gameTitle.includes('season finale') || gameTitle.includes('regular season finale')) score += 15
  
  // Game status boost
  if (status.includes('live') || status.includes('in progress')) score += 15
  if (status.includes('final') || status.includes('ft')) score += 10
  
  // Rivalry and big matchup indicators
  const rivalryPairs = [
    ['yankees', 'red sox'], ['lakers', 'celtics'], ['cowboys', 'giants'],
    ['packers', 'bears'], ['dodgers', 'giants'], ['warriors', 'lakers']
  ]
  
  for (const [team1, team2] of rivalryPairs) {
    if (gameTitle.includes(team1) && gameTitle.includes(team2)) {
      score += 15
      break
    }
  }
  
  // Major upset indicators (if score data available)
  const homeScore = game.home_score || game.competitors?.[0]?.score
  const awayScore = game.away_score || game.competitors?.[1]?.score
  if (homeScore && awayScore) {
    const scoreDiff = Math.abs(Number(homeScore) - Number(awayScore))
    if (scoreDiff >= 20) score += 10 // Big margin
  }
  
  return Math.max(0, Math.min(100, score)) // Clamp to 0-100
}

// Classify game type for prioritization
function classifyGameType(game: any): string {
  const gameTitle = `${game.name || ''} ${game.event || ''}`.toLowerCase()
  
  if (gameTitle.includes('world series') || gameTitle.includes('super bowl')) return 'championship'
  if (gameTitle.includes('finals')) return 'championship'
  if (gameTitle.includes('championship')) return 'championship'
  if (gameTitle.includes('playoff') || gameTitle.includes('division series') || gameTitle.includes('wild card')) return 'playoff'
  if (gameTitle.includes('season opener') || gameTitle.includes('home opener')) return 'season_opener'
  
  // Check for rivalry games
  const rivalryPairs = [
    ['yankees', 'red sox'], ['lakers', 'celtics'], ['cowboys', 'giants'],
    ['packers', 'bears'], ['dodgers', 'giants'], ['warriors', 'lakers']
  ]
  
  for (const [team1, team2] of rivalryPairs) {
    if (gameTitle.includes(team1) && gameTitle.includes(team2)) {
      return 'rivalry'
    }
  }
  
  return 'regular'
}

// Get seasonal context for sports with comprehensive monthly logic
function getSeasonalContext(game: any): string {
  const currentMonth = new Date().getMonth() + 1 // 1-12
  const league = (game.league || '').toLowerCase()
  
  // Month-by-month seasonal intelligence
  if (currentMonth === 1) { // January
    if (league === 'nfl') return 'playoff_season' // Wild Card, Divisional, Conference Championships
    if (league === 'nba') return 'peak_season' // Mid-season
    if (league === 'nhl') return 'peak_season' // Mid-season
    if (league === 'ncaaf') return 'championship_season' // CFP National Championship
    if (league === 'mlb') return 'off_season'
  }
  
  if (currentMonth === 2) { // February
    if (league === 'nfl') return 'championship_season' // Super Bowl
    if (league === 'nba') return 'peak_season' // All-Star break
    if (league === 'nhl') return 'peak_season' // All-Star break
    if (league === 'ncaaf') return 'off_season'
    if (league === 'mlb') return 'spring_training'
  }
  
  if (currentMonth === 3) { // March
    if (league === 'nfl') return 'off_season'
    if (league === 'nba') return 'peak_season' // Playoff push
    if (league === 'nhl') return 'peak_season' // Playoff push
    if (league === 'ncaaf') return 'off_season'
    if (league === 'mlb') return 'spring_training'
  }
  
  if (currentMonth === 4) { // April
    if (league === 'nfl') return 'off_season'
    if (league === 'nba') return 'playoff_season' // NBA Playoffs start
    if (league === 'nhl') return 'playoff_season' // Stanley Cup Playoffs start
    if (league === 'ncaaf') return 'off_season'
    if (league === 'mlb') return 'season_start' // Opening Day
  }
  
  if (currentMonth === 5) { // May
    if (league === 'nfl') return 'off_season'
    if (league === 'nba') return 'playoff_season' // Conference Semifinals/Finals
    if (league === 'nhl') return 'playoff_season' // Conference Semifinals/Finals
    if (league === 'ncaaf') return 'off_season'
    if (league === 'mlb') return 'early_season'
  }
  
  if (currentMonth === 6) { // June
    if (league === 'nfl') return 'off_season'
    if (league === 'nba') return 'championship_season' // NBA Finals
    if (league === 'nhl') return 'championship_season' // Stanley Cup Finals
    if (league === 'ncaaf') return 'off_season'
    if (league === 'mlb') return 'peak_season'
  }
  
  if (currentMonth === 7) { // July
    if (league === 'nfl') return 'off_season'
    if (league === 'nba') return 'off_season'
    if (league === 'nhl') return 'off_season'
    if (league === 'ncaaf') return 'off_season'
    if (league === 'mlb') return 'peak_season' // All-Star break
  }
  
  if (currentMonth === 8) { // August
    if (league === 'nfl') return 'preseason'
    if (league === 'nba') return 'off_season'
    if (league === 'nhl') return 'off_season'
    if (league === 'ncaaf') return 'season_start' // College football starts
    if (league === 'mlb') return 'peak_season'
  }
  
  if (currentMonth === 9) { // September
    if (league === 'nfl') return 'season_start' // NFL season starts
    if (league === 'nba') return 'off_season'
    if (league === 'nhl') return 'preseason'
    if (league === 'ncaaf') return 'peak_season'
    if (league === 'mlb') return 'playoff_push' // September playoff race
  }
  
  if (currentMonth === 10) { // October
    if (league === 'nfl') return 'peak_season'
    if (league === 'nba') return 'season_start' // NBA season starts
    if (league === 'nhl') return 'season_start' // NHL season starts
    if (league === 'ncaaf') return 'peak_season'
    if (league === 'mlb') return 'playoff_season' // Wild Card, Division Series
  }
  
  if (currentMonth === 11) { // November
    if (league === 'nfl') return 'peak_season'
    if (league === 'nba') return 'early_season'
    if (league === 'nhl') return 'early_season'
    if (league === 'ncaaf') return 'peak_season' // Conference championships
    if (league === 'mlb') return 'championship_season' // World Series
  }
  
  if (currentMonth === 12) { // December
    if (league === 'nfl') return 'playoff_push' // Final weeks, playoff race
    if (league === 'nba') return 'peak_season'
    if (league === 'nhl') return 'peak_season'
    if (league === 'ncaaf') return 'playoff_season' // CFP Semifinals
    if (league === 'mlb') return 'off_season'
  }
  
  return 'peak_season' // Default fallback
}

// Calculate how many sports spots this game deserves
function calculateSportsSpots(game: any, significanceScore: number, gameType: string): number {
  const gameTitle = `${game.name || ''} ${game.event || ''}`.toLowerCase()
  const league = (game.league || '').toLowerCase()
  const currentMonth = new Date().getMonth() + 1
  const dayOfMonth = new Date().getDate()
  
  // 3 spots for ultimate championship games
  if (gameType === 'championship' && significanceScore >= 80) {
    if (gameTitle.includes('world series game 7') || gameTitle.includes('super bowl') || 
        gameTitle.includes('nba finals game 7') || gameTitle.includes('stanley cup final game 7')) {
      return 3
    }
  }

  // 3 spots for World Series games during late October
  if (league === 'mlb' && currentMonth === 10 && dayOfMonth >= 25) {
    // All late October MLB games likely World Series - get maximum coverage
    console.log(`[Sports Spots] 3 spots allocated for late October MLB: ${gameTitle}`)
    return 3
  }

  // 3 spots for explicit World Series games anytime
  if (gameTitle.includes('world series')) {
    console.log(`[Sports Spots] 3 spots allocated for World Series: ${gameTitle}`)
    return 3
  }

  // 2 spots for Dodgers during October playoffs (LA team priority)
  if (league === 'mlb' && currentMonth === 10 && gameTitle.includes('dodgers')) {
    console.log(`[Sports Spots] 2 spots allocated for Dodgers playoff game: ${gameTitle}`)
    return 2
  }
  
  // 2 spots for major events
  if (gameType === 'championship' || significanceScore >= 70) return 2
  if (gameType === 'playoff' || gameType === 'season_opener') return 2
  
  // 2 spots for major upsets or high-significance regular games
  if (significanceScore >= 60) return 2
  
  // Default to 1 spot
  return 1
}

// Calculate location relevance for major US metro areas
function calculateSportsLocationRelevance(game: any): Record<string, number> {
  const gameTitle = `${game.name || ''} ${game.event || ''}`.toLowerCase()
  const homeTeam = `${game.home_team || game.competitors?.[0]?.team || ''}`.toLowerCase()
  const awayTeam = `${game.away_team || game.competitors?.[1]?.team || ''}`.toLowerCase()
  const relevance: Record<string, number> = {}
  
  // Major metro areas and their teams
  const metroTeams = {
    'los_angeles': ['lakers', 'clippers', 'dodgers', 'angels', 'rams', 'chargers', 'kings', 'ducks'],
    'new_york': ['yankees', 'mets', 'knicks', 'nets', 'giants', 'jets', 'rangers', 'islanders'],
    'chicago': ['bulls', 'blackhawks', 'cubs', 'white sox', 'bears'],
    'boston': ['celtics', 'red sox', 'patriots', 'bruins'],
    'philadelphia': ['76ers', 'phillies', 'eagles', 'flyers'],
    'san_francisco': ['warriors', 'giants', '49ers', 'sharks'],
    'dallas': ['mavericks', 'rangers', 'cowboys', 'stars'],
    'houston': ['rockets', 'astros', 'texans'],
    'miami': ['heat', 'marlins', 'dolphins', 'panthers'],
    'atlanta': ['hawks', 'braves', 'falcons'],
    'detroit': ['pistons', 'tigers', 'lions', 'red wings'],
    'phoenix': ['suns', 'diamondbacks', 'cardinals', 'coyotes'],
    'seattle': ['mariners', 'seahawks', 'kraken'],
    'denver': ['nuggets', 'rockies', 'broncos', 'avalanche'],
    'cleveland': ['cavaliers', 'guardians', 'browns'],
    'milwaukee': ['bucks', 'brewers'],
    'portland': ['trail blazers'],
    'las_vegas': ['golden knights', 'raiders'],
    'nashville': ['predators', 'titans'],
    'tampa': ['lightning', 'rays', 'buccaneers']
  }
  
  // Calculate relevance scores
  for (const [metro, teams] of Object.entries(metroTeams)) {
    let score = 0
    
    for (const team of teams) {
      if (homeTeam.includes(team) || awayTeam.includes(team) || gameTitle.includes(team)) {
        score += 20 // High score for local team involvement
      }
    }
    
    // Boost for local rivalries
    const localTeams = teams.filter(team => homeTeam.includes(team) || awayTeam.includes(team))
    if (localTeams.length === 2) {
      score += 10 // Both teams from same metro (rare but happens)
    }
    
    relevance[metro] = Math.min(score, 30) // Cap at 30
  }
  
  return relevance
}