import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ContentSource {
  type: 'news' | 'stocks' | 'sports'
  source: string
  fetchFunction: () => Promise<any>
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Initialize Supabase client with service role key for full access
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    console.log('🔄 Starting content refresh cycle')
    const startTime = Date.now()

    // Define all content sources
    const contentSources: ContentSource[] = [
      // News sources
      { type: 'news', source: 'newsapi', fetchFunction: () => fetchNewsAPI() },
      { type: 'news', source: 'gnews', fetchFunction: () => fetchGNews() },
      
      // Stock sources  
      { type: 'stocks', source: 'yahoo_finance', fetchFunction: () => fetchYahooFinance() },
      
      // Sports sources
      { type: 'sports', source: 'espn', fetchFunction: () => fetchESPN() },
      { type: 'sports', source: 'thesportdb', fetchFunction: () => fetchTheSportDB() },
    ]

    const results = {
      successful: 0,
      failed: 0,
      errors: [] as string[]
    }

    // Fetch from all sources in parallel
    const fetchPromises = contentSources.map(async (source) => {
      try {
        console.log(`📡 Fetching ${source.source} (${source.type})`)
        const data = await source.fetchFunction()
        
        if (data && Object.keys(data).length > 0) {
          // Cache the content
          const { error } = await supabase.rpc('cache_content', {
            p_content_type: source.type,
            p_source: source.source,
            p_data: data,
            p_expires_hours: 12
          })

          if (error) {
            console.error(`❌ Failed to cache ${source.source}: ${error.message}`)
            results.errors.push(`${source.source}: ${error.message}`)
            results.failed++
          } else {
            console.log(`✅ Cached ${source.source} successfully`)
            results.successful++
          }
        } else {
          console.warn(`⚠️ ${source.source} returned empty data`)
          results.errors.push(`${source.source}: Empty data returned`)
          results.failed++
        }
      } catch (error) {
        console.error(`❌ Error fetching ${source.source}: ${error.message}`)
        results.errors.push(`${source.source}: ${error.message}`)
        results.failed++
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
    
    console.log(`📊 Content refresh completed in ${duration}ms`)
    console.log(`✅ Successful: ${results.successful}`)
    console.log(`❌ Failed: ${results.failed}`)

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Content refresh completed',
        results: {
          successful: results.successful,
          failed: results.failed,
          duration_ms: duration,
          errors: results.errors
        }
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    console.error('❌ Content refresh failed:', error)
    
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        message: 'Content refresh failed'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

// News API fetch function
async function fetchNewsAPI(): Promise<any> {
  const apiKey = Deno.env.get('NEWSAPI_KEY')
  if (!apiKey) throw new Error('NEWSAPI_KEY not configured')

  const url = `https://newsapi.org/v2/top-headlines?country=us&pageSize=10&apiKey=${apiKey}`
  const response = await fetch(url)
  
  if (!response.ok) {
    throw new Error(`NewsAPI failed: ${response.status} ${response.statusText}`)
  }

  const data = await response.json()
  
  if (data.status !== 'ok') {
    throw new Error(`NewsAPI error: ${data.message || 'Unknown error'}`)
  }

  return {
    articles: data.articles?.slice(0, 5) || [], // Top 5 headlines
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
  const response = await fetch(url)
  
  if (!response.ok) {
    throw new Error(`GNews failed: ${response.status} ${response.statusText}`)
  }

  const data = await response.json()
  
  if (!data.articles) {
    throw new Error(`GNews error: ${data.errors?.[0]?.message || 'No articles returned'}`)
  }

  return {
    articles: data.articles.slice(0, 5), // Top 5 headlines
    total_results: data.totalArticles,
    fetched_at: new Date().toISOString(),
    source: 'gnews'
  }
}

// Yahoo Finance fetch function (via RapidAPI)
async function fetchYahooFinance(): Promise<any> {
  const rapidApiKey = Deno.env.get('RAPIDAPI_KEY')
  if (!rapidApiKey) throw new Error('RAPIDAPI_KEY not configured')

  const symbols = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'NVDA', 'META', 'NFLX']
  const symbolString = symbols.join('%2C') // URL encode commas
  
  const url = `https://apidojo-yahoo-finance-v1.p.rapidapi.com/market/v2/get-quotes?region=US&symbols=${symbolString}`
  const response = await fetch(url, {
    headers: {
      'x-rapidapi-host': 'apidojo-yahoo-finance-v1.p.rapidapi.com',
      'x-rapidapi-key': rapidApiKey
    }
  })
  
  if (!response.ok) {
    throw new Error(`Yahoo Finance failed: ${response.status} ${response.statusText}`)
  }

  const data = await response.json()
  
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
  const response = await fetch(url)
  
  if (!response.ok) {
    throw new Error(`ESPN failed: ${response.status} ${response.statusText}`)
  }

  const data = await response.json()
  
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
  // Get today's date in YYYY-MM-DD format
  const today = new Date().toISOString().split('T')[0]
  const url = `https://www.thesportsdb.com/api/v1/json/123/eventsday.php?d=${today}`
  const response = await fetch(url)
  
  if (!response.ok) {
    throw new Error(`TheSportDB failed: ${response.status} ${response.statusText}`)
  }

  const data = await response.json()
  
  return {
    events: data.events?.slice(0, 10).map((event: any) => ({
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
    date: today,
    fetched_at: new Date().toISOString(),
    source: 'thesportdb'
  }
}