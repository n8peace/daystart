import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// Local lint shim for Deno globals in non-Deno editors
declare const Deno: any;

// Helper: ~145 wpm is natural TTS; adjust as needed
function targetWords(seconds: number, wpm = 145): number {
  return Math.round((seconds / 60) * wpm);
}

// Dynamic token allocation based on script length
function getTokenLimits(seconds: number): { maxTokens: number; targetWords: number } {
  const words = targetWords(seconds);
  // Rule of thumb: ~0.75 tokens per word for output, plus buffer for complex content
  const baseTokens = Math.round(words * 1.2);
  const maxTokens = Math.max(300, Math.min(2000, baseTokens)); // Reasonable bounds
  
  return { maxTokens, targetWords: words };
}

// Dynamic story count based on duration
function getStoryLimits(seconds: number): { news: number; sports: number; stocks: number } {
  if (seconds <= 60) {
    // 1 minute: bare minimum
    return { news: 2, sports: 1, stocks: 1 };
  } else if (seconds <= 180) {
    // 3 minutes: light coverage
    return { news: 3, sports: 1, stocks: 2 };
  } else if (seconds <= 300) {
    // 5 minutes: standard coverage
    return { news: 5, sports: 1, stocks: 2 };
  } else {
    // 5+ minutes: comprehensive coverage
    return { news: 6, sports: 2, stocks: 3 };
  }
}

// (Removed keyword-based news prioritization helpers; model will choose relevance based on user.location)

// Light trust weighting for sources and dedupe across feeds
const TRUSTED = ['ap','associated press','reuters','bbc','npr','la times','bloomberg','cbs news','axios','arstechnica','the verge'];
function trustScore(name: string = ''): number {
  const n = name.toLowerCase();
  return TRUSTED.some(s => n.includes(s)) ? 2 : 1;
}

function flattenAndDedupeNews(newsData: any[] = []): any[] {
  const seen = new Set<string>();
  const out: any[] = [];
  for (const src of newsData || []) {
    for (const a of src?.data?.articles || []) {
      const key = String(a.url || a.title || '').toLowerCase().slice(0, 180);
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ ...a, sourceName: src.source, trust: trustScore(src.source) });
    }
  }
  // Newer + trusted first (light, non-opinionated ordering)
  return out.sort((a, b) => {
    const ta = new Date(a.publishedAt || 0).getTime();
    const tb = new Date(b.publishedAt || 0).getTime();
    return (tb - ta) || (b.trust - a.trust);
  });
}

function flattenAndParseStocks(stocksData: any[] = []): any[] {
  const seen = new Set<string>();
  const out: any[] = [];
  
  for (const src of stocksData || []) {
    try {
      let quotes: any[] = [];
      
      // Handle different data formats
      if (typeof src.data === 'string') {
        // Data is JSON-stringified, parse it
        const parsed = JSON.parse(src.data);
        quotes = parsed?.quotes || [];
      } else if (src.data?.quotes) {
        // Data is already parsed with quotes array
        quotes = src.data.quotes;
      } else if (Array.isArray(src.data)) {
        // Data is directly an array of stocks
        quotes = src.data;
      } else if (Array.isArray(src)) {
        // Source itself is an array of stocks (backward compatibility)
        quotes = src;
      }
      
      // Add each quote to output, deduping by symbol
      for (const quote of quotes || []) {
        const symbol = String(quote?.symbol || '').toUpperCase();
        if (!symbol || seen.has(symbol)) continue;
        
        seen.add(symbol);
        out.push({
          name: quote.name || '',
          symbol: quote.symbol || '',
          price: quote.price || 0,
          change: quote.change || 0,
          change_percent: quote.change_percent || quote.chgPct || 0,
          percentChange: quote.change_percent || quote.chgPct || 0, // Alias for backward compatibility
          market_cap: quote.market_cap || 0,
          timestamp: quote.timestamp || quote.fetched_at || new Date().toISOString(),
          source: src.source || 'unknown'
        });
      }
    } catch (error) {
      console.warn(`[DEBUG] Failed to parse stock data from source ${src.source}:`, error);
      // Continue with other sources even if one fails
    }
  }
  
  // Sort by market cap descending (larger companies first)
  return out.sort((a, b) => (b.market_cap || 0) - (a.market_cap || 0));
}

function flattenAndParseSports(sportsData: any[] = []): any[] {
  const seen = new Set<string>();
  const out: any[] = [];
  
  for (const src of sportsData || []) {
    try {
      let games: any[] = [];
      
      // Handle different data formats
      if (typeof src.data === 'string') {
        // Data is JSON-stringified, parse it
        const parsed = JSON.parse(src.data);
        games = parsed?.games || parsed?.events || [];
      } else if (src.data?.games) {
        // Data is already parsed with games array
        games = src.data.games;
      } else if (src.data?.events) {
        // Data uses 'events' instead of 'games'
        games = src.data.events;
      } else if (Array.isArray(src.data)) {
        // Data is directly an array of games
        games = src.data;
      } else if (Array.isArray(src)) {
        // Source itself is an array of games (backward compatibility)
        games = src;
      }
      
      // Add each game to output, deduping by id
      for (const game of games || []) {
        const gameId = String(game?.id || '');
        if (!gameId || seen.has(gameId)) continue;
        
        seen.add(gameId);
        
        // Extract team names for easier processing
        const competitors = game.competitors || [];
        let home_team = '';
        let away_team = '';
        let home_score = '';
        let away_score = '';
        
        if (competitors.length >= 2) {
          // Assume first competitor is home, second is away (ESPN format)
          home_team = competitors[0]?.team || '';
          away_team = competitors[1]?.team || '';
          home_score = competitors[0]?.score || '0';
          away_score = competitors[1]?.score || '0';
        }
        
        out.push({
          id: game.id || '',
          date: game.date || '',
          name: game.name || `${away_team} at ${home_team}`,
          status: game.status || 'UNKNOWN',
          league: game.league || src.source || 'unknown',
          competitors: game.competitors || [],
          home_team,
          away_team,
          home_score,
          away_score,
          event: game.name || game.event || `${away_team} vs ${home_team}`,
          source: src.source || 'unknown'
        });
      }
    } catch (error) {
      console.warn(`[DEBUG] Failed to parse sports data from source ${src.source}:`, error);
      // Continue with other sources even if one fails
    }
  }
  
  // Sort by date (most recent first)
  return out.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
}

function compactNewsItem(a: any) {
  return {
    title: a?.title?.slice(0, 160) || '',
    description: a?.description?.slice(0, 280) || '',
    source: a?.sourceName || '',
    publishedAt: a?.publishedAt || ''
  };
}

// Filter sports items to today's fixtures/results and valid statuses
function filterValidSportsItems(sports: any[] = [], dateISO: string, tz?: string): any[] {
  const target = tz ? new Date(new Date(dateISO + 'T00:00:00').toLocaleString('en-US', { timeZone: tz }))
                    : new Date(dateISO + 'T00:00:00');
  const today = target.toISOString().slice(0, 10);
  
  // Also include tomorrow to catch events that slip due to UTC timezone differences
  const tomorrow = new Date(target.getTime() + 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  
  // Debug: log filtering process
  const debugFiltered: any[] = [];
  
  const filtered = (sports || []).filter((ev: any) => {
    const d = String(ev?.date || '').slice(0, 10);
    const status = String(ev?.status || '').toLowerCase();
    
    // More flexible status matching to handle various API formats
    const isValidStatus = 
      status.includes('final') ||      // ESPN: STATUS_FINAL, TheSportDB: Match Finished
      status.includes('finish') ||     // TheSportDB: Match Finished
      status.includes('ft') ||         // Common: FT (Full Time)
      status.includes('live') ||       // Common: LIVE, In Progress
      status.includes('progress') ||   // ESPN: in progress
      status.includes('scheduled') ||  // ESPN: STATUS_SCHEDULED
      status.includes('started') ||    // TheSportDB: Not Started
      status === 'ns' ||              // Common: NS (Not Started)
      status.includes('pre-game') ||   // Common: PRE-GAME
      status.includes('postponed');    // Handle postponed games too
    
    const validDate = (d === today || d === tomorrow);
    const isValid = validDate && isValidStatus;
    
    // Collect debug info for rejected events
    if (!isValid && debugFiltered.length < 5) {
      debugFiltered.push({
        event: ev?.event || ev?.name || 'Unknown',
        date: d,
        status: status,
        validDate,
        isValidStatus,
        reason: !validDate ? 'wrong date' : 'invalid status'
      });
    }
    
    return isValid;
  });
  
  // Log filtering results
  if (debugFiltered.length > 0) {
    console.log(`[DEBUG] Sports filtering - Rejected events (first 5):`);
    debugFiltered.forEach(item => {
      console.log(`  - ${item.event}: ${item.reason} (date=${item.date}, status='${item.status}')`);
    });
  }
  console.log(`[DEBUG] Sports filtering: ${sports.length} total → ${filtered.length} valid (today=${today}, tomorrow=${tomorrow})`);
  
  return filtered;
}

function teamWhitelistFromSports(sports: any[] = []): string[] {
  const set = new Set<string>();
  for (const ev of sports || []) {
    ['home_team', 'away_team'].forEach(k => {
      const v = ev?.[k];
      if (v) set.add(String(v).toLowerCase());
    });
  }
  return Array.from(set);
}

// Compute a rough per-section word budget based on duration and what's included
function sectionBudget(seconds: number, include: { weather: boolean; calendar: boolean; news: boolean; sports: boolean; stocks: boolean; quotes: boolean }): Record<string, number> {
  const base: Array<[string, number]> = [
    ['greeting',  40],
    ['weather',   include.weather ? 120 : 0],
    ['calendar',  include.calendar ? 120 : 0],
    ['news',      include.news ? 500 : 0],
    ['sports',    include.sports ? 90 : 0],
    ['stocks',    include.stocks ? 80 : 0],
    ['quote',     include.quotes ? 150 : 0],
    ['close',     40],
  ];
  const total = base.reduce((sum, [, w]) => sum + w, 0) || 1;
  const target = targetWords(seconds);
  const entries = base.map(([k, w]) => [k, Math.round((w / total) * target)] as [string, number]);
  return Object.fromEntries(entries);
}

// Check if date falls on weekend (Saturday or Sunday)
function isWeekend(dateISO: string, tz?: string): boolean {
  const targetDate = tz 
    ? new Date(new Date(dateISO + 'T00:00:00').toLocaleString('en-US', { timeZone: tz }))
    : new Date(dateISO + 'T00:00:00');
  const day = targetDate.getUTCDay(); // 0 = Sunday, 6 = Saturday
  return day === 0 || day === 6;
}

// Get day context with weekday encouragements and US holidays
function getDayContext(dateISO: string, tz?: string): { label: string, encouragements: string[] } {
  const target = tz 
    ? new Date(new Date(dateISO + 'T00:00:00').toLocaleString('en-US', { timeZone: tz }))
    : new Date(dateISO + 'T00:00:00');

  const weekday = target.toLocaleDateString('en-US', { weekday: 'long', timeZone: tz });
  const monthDay = target.toLocaleDateString('en-US', { month: 'long', day: 'numeric', timeZone: tz });
  const year = target.getFullYear();

  const encouragements: string[] = [];

  // Weekly rhythm variants
  if (weekday === "Monday") {
    encouragements.push(
      "Fresh start",
      "New week energy", 
      "Monday momentum",
      "Week one begins",
      "Clean slate Monday",
      "Monday reset",
      "New chapter starts",
      "Week's first lap",
      ""  // Allow skipping
    );
  }
  
  if (weekday === "Tuesday") {
    encouragements.push(
      "Tuesday stride",
      "Getting into gear",
      "Week's warming up",
      "Momentum building",
      "Tuesday tempo",
      "Second verse",
      "Finding the rhythm",
      ""
    );
  }
  
  if (weekday === "Wednesday") {
    encouragements.push(
      "Halfway through the week",
      "Hump day momentum",
      "Middle stretch",
      "Week's turning point",
      "Halfway up the hill",
      "Wednesday wisdom",
      "Peak of the week",
      "Midweek milestone",
      "Center stage Wednesday",
      ""
    );
  }
  
  if (weekday === "Thursday") {
    encouragements.push(
      "Almost there Thursday",
      "Home stretch begins",
      "Thursday thunder",
      "Weekend's in view",
      "Fourth quarter energy",
      "Thursday momentum",
      "Nearly to the summit",
      "One more day",
      ""
    );
  }
  
  if (weekday === "Friday") {
    encouragements.push(
      "TGIF",
      "Weekend's in sight",
      "Friday feeling",
      "Home stretch",
      "Almost there",
      "Friday energy",
      "Week's final act",
      "Weekend countdown",
      "Friday finish line",
      "Last lap",
      ""
    );
  }
  
  if (weekday === "Saturday") {
    encouragements.push(
      "Enjoy the weekend",
      "Saturday vibes",
      "Weekend mode",
      "Time to recharge",
      "Saturday slow-down",
      "Weekend breathing room",
      "Saturday freedom",
      ""
    );
  }
  
  if (weekday === "Sunday") {
    encouragements.push(
      "Sunday reset",
      "Weekend wrap-up",
      "Sunday reflection",
      "Gentle Sunday",
      "Week prep day",
      "Sunday pause",
      "Rest and reset",
      ""
    );
  }

  // Comprehensive US Holidays
  const holidays: Record<string, string[]> = {
    // Fixed date holidays
    "January 1": ["Happy New Year", "New year, new possibilities", "Fresh calendar energy"],
    "February 14": ["Happy Valentine's Day", "Love is in the air", "Valentine's vibes"],
    "March 17": ["Happy St. Patrick's Day", "Feeling lucky today", "Irish eyes are smiling"],
    "July 4": ["Happy Fourth of July", "Independence Day spirit", "Stars and stripes forever"],
    "October 31": ["Happy Halloween", "Spooky season vibes", "Trick or treat energy"],
    "November 11": ["Veterans Day honor", "Thank a veteran today", "Service and sacrifice remembered"],
    "December 24": ["Christmas Eve magic", "Holiday anticipation", "Silent night energy"],
    "December 25": ["Merry Christmas", "Christmas joy", "Peace and goodwill"],
    "December 31": ["New Year's Eve", "Year-end reflection", "Tomorrow's fresh start"]
  };

  // Calculate floating holidays for current year
  const floatingHolidays = getFloatingHolidays(year);
  const currentDateKey = target.toLocaleDateString('en-US', { month: 'long', day: 'numeric', timeZone: tz });
  
  // Check fixed holidays
  if (holidays[currentDateKey]) {
    encouragements.push(...holidays[currentDateKey]);
  }
  
  // Check floating holidays
  if (floatingHolidays[currentDateKey]) {
    encouragements.push(...floatingHolidays[currentDateKey]);
  }

  return {
    label: weekday,
    encouragements,
    isHoliday: !!holidays[currentDateKey] || !!floatingHolidays[currentDateKey]
  };
}

// Calculate floating US holidays for a given year
function getFloatingHolidays(year: number): Record<string, string[]> {
  const holidays: Record<string, string[]> = {};
  
  // Martin Luther King Jr. Day (3rd Monday in January)
  const mlkDay = getNthWeekday(year, 0, 1, 3); // January, Monday, 3rd
  holidays[mlkDay] = ["MLK Day reflection", "Dream and determination", "Justice and hope"];
  
  // Presidents Day (3rd Monday in February)  
  const presidentsDay = getNthWeekday(year, 1, 1, 3); // February, Monday, 3rd
  holidays[presidentsDay] = ["Presidents Day", "Leadership legacy", "Democracy in action"];
  
  // Memorial Day (Last Monday in May)
  const memorialDay = getLastWeekday(year, 4, 1); // May, Monday
  holidays[memorialDay] = ["Memorial Day honor", "Remember the fallen", "Service and sacrifice"];
  
  // Labor Day (1st Monday in September)
  const laborDay = getNthWeekday(year, 8, 1, 1); // September, Monday, 1st
  holidays[laborDay] = ["Labor Day appreciation", "Workers unite", "Hard work honored"];
  
  // Columbus Day (2nd Monday in October)
  const columbusDay = getNthWeekday(year, 9, 1, 2); // October, Monday, 2nd
  holidays[columbusDay] = ["Columbus Day", "Exploration spirit", "Journey continues"];
  
  // Thanksgiving (4th Thursday in November)
  const thanksgiving = getNthWeekday(year, 10, 4, 4); // November, Thursday, 4th
  holidays[thanksgiving] = ["Happy Thanksgiving", "Gratitude overflows", "Count your blessings"];
  
  return holidays;
}

// Helper: Get nth weekday of month (e.g., 3rd Monday)
function getNthWeekday(year: number, month: number, weekday: number, n: number): string {
  const firstDay = new Date(year, month, 1);
  const firstWeekday = firstDay.getDay();
  const daysToAdd = (weekday - firstWeekday + 7) % 7;
  const nthDate = new Date(year, month, 1 + daysToAdd + (n - 1) * 7);
  return nthDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
}

// Helper: Get last weekday of month (e.g., last Monday in May)
function getLastWeekday(year: number, month: number, weekday: number): string {
  const lastDay = new Date(year, month + 1, 0); // Last day of month
  const lastWeekday = lastDay.getDay();
  const daysToSubtract = (lastWeekday - weekday + 7) % 7;
  const lastWeekdayDate = new Date(year, month + 1, 0 - daysToSubtract);
  return lastWeekdayDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
}

// Random choice helper with option to return empty string
function randomChoice<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

// Extract simple locality hints (no hardcoded locales)
function localityHints(loc: any): string[] {
  const hints: string[] = [];
  if (loc?.neighborhood) hints.push(String(loc.neighborhood).toLowerCase());
  if (loc?.city) hints.push(String(loc.city).toLowerCase());
  if (loc?.county) hints.push(String(loc.county).toLowerCase());
  if (loc?.metro) hints.push(String(loc.metro).toLowerCase());
  if (loc?.state) hints.push(String(loc.state).toLowerCase());
  return Array.from(new Set(hints)).filter(Boolean);
}

// Sample random transitions for smoother section changes
function getRandomTransitions() {
  const toWeatherOptions = ['A quick look outside —', 'First, the sky —', 'Step one: the weather —'];
  const toCalendarOptions = ['Before you head out —', 'On your slate —', 'Two things to timebox —'];
  const toNewsOptions = ['Now to the headlines …', 'In the news —', 'Closer to home —'];
  const toSportsOptions = ['One sports note —', 'Quick sports pulse —', 'Around the diamond —'];
  const toStocksOptions = ['On the tape —', 'For your watchlist —', 'Markets at the open —'];
  const toQuoteOptions = ['Pocket this —', 'A line to carry —', 'One thought for the morning —'];
  
  return {
    toWeather: toWeatherOptions[Math.floor(Math.random() * toWeatherOptions.length)],
    toCalendar: toCalendarOptions[Math.floor(Math.random() * toCalendarOptions.length)],
    toNews: toNewsOptions[Math.floor(Math.random() * toNewsOptions.length)],
    toSports: toSportsOptions[Math.floor(Math.random() * toSportsOptions.length)],
    toStocks: toStocksOptions[Math.floor(Math.random() * toStocksOptions.length)],
    toQuote: toQuoteOptions[Math.floor(Math.random() * toQuoteOptions.length)]
  };
}

// Sample random sign-off for script endings
function getRandomSignOff() {
  const signOffOptions = [
    "That's your morning wrapped — peel back the day slowly, and you'll find it's sweeter than it looks at first glance.",
    "Don't trip over the small peels life leaves on the floor — step past them and keep your stride steady.",
    "Stay yellow when the world wants you green, and stay mellow when the world tries to bruise you.",
    "Peel into this Monday with intention — because even bananas don't get eaten in one bite.",
    "Bananas never rush to ripen — take today one hour at a time, and let the good parts come naturally.",
    "From the morning bunch to the evening hush, carry the sweetness with you and share it where you can.",
    "Potassium powers possibility — give your mind the fuel it needs, and watch the energy carry you forward.",
    "That's the whole peel, deal, and reveal — nothing more to add except your own effort.",
    "Even bananas thrive in a bunch — lean on your people, lift up someone else, and the day gets lighter."
  ];
  
  return signOffOptions[Math.floor(Math.random() * signOffOptions.length)];
}

// Enhanced retry + timeout wrapper with detailed logging
async function withRetry<T>(fn: () => Promise<T>, tries = 3, baseMs = 600, timeoutMs = 45000, context = 'unknown'): Promise<T> {
  let lastErr: any;
  const startTime = Date.now();
  
  console.log(`🔄 withRetry starting for ${context}, timeout: ${timeoutMs}ms, tries: ${tries}`);
  
  for (let i = 0; i < tries; i++) {
    const attemptStart = Date.now();
    console.log(`📡 Attempt ${i + 1}/${tries} for ${context} (elapsed: ${attemptStart - startTime}ms)`);
    
    try {
      const result = await Promise.race([
        fn(),
        new Promise<never>((_, rej) => setTimeout(() => {
          const timeoutError = new Error(`timeout after ${timeoutMs}ms`);
          console.log(`⏰ TIMEOUT in ${context} after ${timeoutMs}ms (attempt ${i + 1}/${tries})`);
          rej(timeoutError);
        }, timeoutMs))
      ]);
      
      const attemptTime = Date.now() - attemptStart;
      const totalTime = Date.now() - startTime;
      console.log(`✅ ${context} succeeded in ${attemptTime}ms (total: ${totalTime}ms, attempt ${i + 1})`);
      return result;
    } catch (e) {
      lastErr = e;
      const attemptTime = Date.now() - attemptStart;
      const errorMsg = e instanceof Error ? e.message : String(e);
      console.log(`❌ ${context} failed in ${attemptTime}ms (attempt ${i + 1}/${tries}): ${errorMsg}`);
      
      if (i < tries - 1) {
        // Respect Retry-After header when available on Response
        let retryAfterMs = 0;
        if (e && typeof e === 'object' && 'headers' in (e as any)) {
          const ra = Number((e as any).headers?.get?.('retry-after')) || 0;
          retryAfterMs = ra * 1000;
          if (retryAfterMs > 0) {
            console.log(`🕐 Retry-After header: ${ra}s`);
          }
        }
        const backoff = baseMs * (2 ** i);
        const delayMs = Math.max(backoff, retryAfterMs);
        console.log(`⏳ Retrying ${context} in ${delayMs}ms (backoff: ${backoff}ms)`);
        await new Promise(r => setTimeout(r, delayMs));
      }
    }
  }
  
  const totalTime = Date.now() - startTime;
  const finalError = lastErr instanceof Error ? lastErr.message : String(lastErr);
  console.log(`💥 ${context} FAILED after ${tries} attempts in ${totalTime}ms. Final error: ${finalError}`);
  throw lastErr;
}

// Fix any unclosed or malformed break tags
function fixBreakTags(script: string): string {
  // Fix unclosed break tags (e.g., "<break time="2s"/" -> "[2 second pause]")
  script = script.replace(/<break\s+time="(\d+s)"\/(?!>)/g, '<break time="$1"/>');
  
  // Fix break tags missing closing angle bracket (e.g., "<break time="2s" -> "[2 second pause]")
  script = script.replace(/<break\s+time="(\d+s)"(?!\/?>)/g, '<break time="$1"/>');
  
  // Fix break tags with missing quotes or other malformations
  script = script.replace(/<break\s+time=(\d+s)\s*\/?>/g, '<break time="$1"/>');
  
  // Validate all break tags are properly closed
  const breakTagPattern = /<break\s+time="(\d+s)"\s*\/>/g;
  const validBreakTags = script.match(breakTagPattern) || [];
  
  // Log if we fixed any break tags
  const originalBreakCount = (script.match(/<break/g) || []).length;
  const fixedBreakCount = validBreakTags.length;
  
  if (originalBreakCount !== fixedBreakCount) {
    console.log(`[DEBUG] Fixed break tags: ${originalBreakCount} original, ${fixedBreakCount} valid after fixes`);
  }
  
  return script;
}

// Sanitize script output for TTS (preserve em-dashes, ellipses, and section breaks)
function sanitizeForTTS(raw: string): string {
  let s = raw.trim();

  // Remove bracketed stage directions but PRESERVE pause instructions
  // This regex removes all bracketed content EXCEPT patterns like [N second pause]
  s = s.replace(/\[(?!\d+\s+second\s+pause\])[^\]]*?\]/g, '');

  // Strip markdown symbols but keep dashes and ellipses
  s = s.replace(/[*_#`>]+/g, '');

  // Normalize whitespace but preserve double newlines (section breaks)
  s = s
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();

  // Remove label-y lines (e.g., "Weather:", "News:")
  s = s.replace(/^(weather|news|sports|stocks|quote|calendar)\s*:\s*/gim, '');

  // Remove any "Good morning" duplicates if model adds extras (but preserve Welcome to DayStart)
  // Only match true duplicates: "Good morning, Name. Good morning, Name." 
  s = s.replace(/^(good morning,\s*[^.]*\.\s*)(good morning,\s*[^.]*\.\s*)+/gi, '$1');

  // Clamp excessive pauses
  s = s.replace(/\.{4,}/g, '...').replace(/—{2,}/g, '—');

  // Guardrails: strip links and tracking params that can slip into TTS
  s = s.replace(/\bhttps?:\/\/\S+/gi, '');
  s = s.replace(/[?&](utm_[^=]+|fbclid)=[^&\s]+/gi, '');

  // Cap pauses per paragraph (≤1 ellipsis, ≤2 em dashes)
  function capPausesPerParagraph(text: string): string {
    return text.split(/\n\n+/).map(p => {
      let e = 0;
      p = p.replace(/\.{3,}/g, m => (++e <= 1 ? '...' : '.'));
      let d = 0;
      p = p.replace(/—/g, m => (++d <= 2 ? '—' : ','));
      return p;
    }).join('\n\n');
  }
  s = capPausesPerParagraph(s);

  return s.trim();
}

// This is a background job processor that can be triggered by:
// 1. Cron job every 1 minute
// 2. Manual webhook call
// 3. Queue system (future enhancement)

interface ProcessJobsResponse {
  success: boolean;
  processed_count: number;
  failed_count: number;
  message: string;
  request_id: string;
}

serve(async (req: Request): Promise<Response> => {
  const request_id = crypto.randomUUID();
  const worker_id = crypto.randomUUID();
  
  try {
    // CORS preflight support
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, content-type',
          'Access-Control-Allow-Methods': 'POST, OPTIONS'
        }
      });
    }
    // Only allow POST from authorized sources
    if (req.method !== 'POST') {
      return createResponse(false, 0, 0, 'Only POST method allowed', request_id);
    }

    // Basic auth check - service role key only
    const authHeader = req.headers.get('authorization');
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!authHeader || !supabaseServiceKey || authHeader !== `Bearer ${supabaseServiceKey}`) {
      return createResponse(false, 0, 0, 'Unauthorized', request_id);
    }

    // Parse optional jobId from request body
    let specificJobId: string | null = null;
    try {
      const body = await req.json();
      if (body?.jobId && typeof body.jobId === 'string') {
        specificJobId = body.jobId;
        console.log(`Worker ${worker_id} processing specific job: ${specificJobId}`);
      }
    } catch {
      // Body parsing is optional - if it fails, proceed with normal batch processing
    }

    // Return success immediately to prevent timeout
    console.log(`Worker ${worker_id} accepted job processing request`);
    
    // Start async processing without waiting
    processJobsAsync(worker_id, request_id, specificJobId).catch(error => {
      console.error('Async job processing error:', error);
    });

    // Return immediate success response
    return createResponse(true, 0, 0, 'Job processing started', request_id);

  } catch (error) {
    console.error('Worker error:', error);
    return createResponse(false, 0, 0, 'Internal worker error', request_id);
  }
});

async function processJobsAsync(worker_id: string, request_id: string, specificJobId?: string | null): Promise<void> {
  try {
    // Initialize Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Release any expired leases first
    await supabase.rpc('release_expired_leases');

    let processedCount = 0;
    let failedCount = 0;

    // If specific job ID provided, process only that job
    if (specificJobId) {
      console.log(`Processing specific job: ${specificJobId}`);
      
      // Try to lease the specific job
      const { data: leasedJobId, error: leaseError } = await supabase.rpc('lease_specific_job', {
        job_id: specificJobId,
        worker_id,
        lease_duration_minutes: 15
      });

      if (leaseError || !leasedJobId) {
        // If we can't lease it, it might already be processed or leased
        console.log(`Could not lease job ${specificJobId}: ${leaseError?.message || 'Job may already be processed'}`);
        return;
      }

      // Process the specific job
      try {
        await processJob(supabase, leasedJobId, worker_id);
        processedCount++;
      } catch (error) {
        console.error(`Failed to process job ${leasedJobId}:`, error);
        failedCount++;
      }
    } else {
      // Parallel batch processing
      const batchSize = 10; // Process 10 jobs in parallel
      const maxTotalJobs = 50; // Maximum total jobs to process per run
      let totalProcessed = 0;

      while (totalProcessed < maxTotalJobs) {
        // Lease a batch of jobs in parallel
        const leasePromises = Array(batchSize).fill(0).map(() => 
          supabase.rpc('lease_next_job', {
            worker_id,
            lease_duration_minutes: 15
          })
        );

        const leaseResults = await Promise.allSettled(leasePromises);
        
        // Extract successfully leased job IDs
        const jobIds = leaseResults
          .filter(result => result.status === 'fulfilled' && result.value.data && !result.value.error)
          .map(result => (result as PromiseFulfilledResult<any>).value.data);

        if (jobIds.length === 0) {
          console.log('No more jobs to process');
          break;
        }

        console.log(`Processing batch of ${jobIds.length} jobs: ${jobIds.join(', ')}`);

        // Process all jobs in the batch in parallel
        const processPromises = jobIds.map(async (jobId) => {
          try {
            const success = await processJob(supabase, jobId, worker_id);
            return { jobId, success, error: null };
          } catch (error) {
            console.error(`Failed to process job ${jobId}:`, error);
            
            // Mark job as failed
            await supabase
              .from('jobs')
              .update({
                status: 'failed',
                error_code: 'PROCESSING_ERROR',
                error_message: error.message,
                worker_id: null,
                lease_until: null,
                updated_at: new Date().toISOString()
              })
              .eq('job_id', jobId);
            
            return { jobId, success: false, error };
          }
        });

        const batchResults = await Promise.allSettled(processPromises);
        
        // Count results
        batchResults.forEach(result => {
          if (result.status === 'fulfilled') {
            if (result.value.success) {
              processedCount++;
            } else {
              failedCount++;
            }
          } else {
            failedCount++;
          }
        });

        totalProcessed += jobIds.length;
      }
    }

    const message = `Processed ${processedCount} jobs, ${failedCount} failed`;
    console.log(`Worker ${worker_id} completed: ${message}`);

  } catch (error) {
    console.error(`Worker ${worker_id} error:`, error);
  }
}

async function processJob(supabase: any, jobId: string, workerId: string): Promise<boolean> {
  // Get job details
  const { data: job, error: jobError } = await supabase
    .from('jobs')
    .select('*')
    .eq('job_id', jobId)
    .single();

  if (jobError || !job) {
    throw new Error('Job not found');
  }

  console.log(`Processing DayStart for ${job.user_id} on ${job.local_date}`);

  // Generate script content and track costs
  const scriptResult = await generateScript(job);
  
  // Update job with script and OpenAI cost
  await supabase
    .from('jobs')
    .update({
      script_content: scriptResult.content,
      script_cost: scriptResult.cost,
      updated_at: new Date().toISOString()
    })
    .eq('job_id', jobId);

  // Generate audio with retry logic
  let audioResult: any = null;
  let lastError: string = '';
  
  for (let attempt = 1; attempt <= 3; attempt++) {
    const result = await generateAudio(scriptResult.content, job, attempt);
    
    if (result.success) {
      audioResult = result;
      if (attempt > 1) {
        console.log(`Audio generation succeeded on attempt ${attempt} using ${result.provider}`);
      }
      break;
    }
    
    lastError = result.error || 'Unknown error';
    console.log(`Audio generation attempt ${attempt} failed: ${lastError}`);
    
    if (attempt < 3) {
      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
    }
  }
  
  if (!audioResult || !audioResult.success) {
    throw new Error(`Audio generation failed after 3 attempts: ${lastError}`);
  }

  // Upload audio to storage
  const audioPath = `${job.user_id}/${job.local_date}/${jobId}.aac`;
  
  const { error: uploadError } = await supabase.storage
    .from('daystart-audio')
    .upload(audioPath, audioResult.audioData, {
      contentType: 'audio/aac',
      upsert: true
    });

  if (uploadError) {
    throw new Error(`Audio upload failed: ${uploadError.message}`);
  }

  // Calculate total cost
  const totalCost = Number((scriptResult.cost + (audioResult.cost ?? 0)).toFixed(5));

  // Mark job as complete with all costs and TTS provider
  await supabase
    .from('jobs')
    .update({
      status: 'ready',
      audio_file_path: audioPath,
      audio_duration: audioResult.duration ?? 0,
      transcript: scriptResult.content.replace(/\[\d+\s+second\s+pause\]/g, ''),
      script_cost: scriptResult.cost,
      tts_cost: audioResult.cost ?? 0,
      tts_provider: audioResult.provider ?? 'elevenlabs',
      total_cost: totalCost,
      completed_at: new Date().toISOString(),
      worker_id: null,
      lease_until: null,
      updated_at: new Date().toISOString()
    })
    .eq('job_id', jobId);

  // Auto-delete sensitive user data after successful audio processing
  try {
    console.log(`🗑️ Auto-deleting calendar and weather data for job ${jobId} (privacy compliance)`);
    
    await supabase
      .from('jobs')
      .update({
        weather_data: null,
        calendar_events: null,
        location_data: null,
        updated_at: new Date().toISOString()
      })
      .eq('job_id', jobId);
    
    console.log(`✅ Successfully deleted sensitive data for job ${jobId}`);
  } catch (deletionError) {
    // Don't fail the job if deletion fails - audio is already ready
    console.warn(`⚠️ Failed to delete sensitive data for job ${jobId}:`, deletionError);
  }

  console.log(`Completed job ${jobId} - audio saved to ${audioPath}`);
  console.log(`Costs: Script=$${scriptResult.cost}, TTS=$${audioResult.cost} (${audioResult.provider}), Total=$${totalCost}`);
  return true;
}

async function generateScript(job: any): Promise<{content: string, cost: number}> {
  const openaiApiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openaiApiKey) {
    throw new Error('OpenAI API key not configured');
  }

  // Initialize Supabase client to get fresh content
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  // Get fresh content from cache
  const contentTypes: string[] = [];
  if (job.include_news) contentTypes.push('news');
  if (job.include_stocks) contentTypes.push('stocks');
  if (job.include_sports) contentTypes.push('sports');

  let contentData: any = {};
  if (contentTypes.length > 0) {
    console.log(`[DEBUG] Requesting content types: ${contentTypes.join(', ')}`);
    // Try enhanced content first (with AI-curated top 10), fall back to regular content
    let { data: freshContent, error: contentError } = await supabase.rpc('get_fresh_content_enhanced', {
      requested_types: contentTypes,
      prefer_ai_curated: true
    });
    
    // If enhanced function doesn't exist (during migration), fall back to regular function
    if (contentError && contentError.message?.includes('function') && contentError.message?.includes('does not exist')) {
      console.log('[DEBUG] Enhanced function not available, using regular get_fresh_content');
      const fallback = await supabase.rpc('get_fresh_content', {
        requested_types: contentTypes
      });
      freshContent = fallback.data;
      contentError = fallback.error;
    }
    
    if (contentError) {
      console.error('[DEBUG] Error fetching content:', contentError);
    }
    
    contentData = freshContent || {};
    console.log('[DEBUG] Content data received:', {
      news: Array.isArray(contentData.news) ? `${contentData.news.length} sources` : 'none',
      sports: Array.isArray(contentData.sports) ? `${contentData.sports.length} sources` : 'none',
      stocks: Array.isArray(contentData.stocks) ? `${contentData.stocks.length} sources` : 'none'
    });
    
    // Log sample of actual content
    if (contentData.news?.length > 0) {
      console.log('[DEBUG] Sample news item:', JSON.stringify(contentData.news[0], null, 2).substring(0, 500) + '...');
    }
  }

  // Build context for the script
  const context = {
    preferredName: job.preferred_name,
    date: job.local_date,
    timezone: job.timezone,
    includeWeather: job.include_weather,
    includeNews: job.include_news,
    includeSports: job.include_sports,
    includeStocks: job.include_stocks,
    stockSymbols: job.stock_symbols,
    includeQuotes: job.include_quotes,
    quotePreference: job.quote_preference,
    dayStartLength: job.daystart_length,
    locationData: job.location_data,
    weatherData: job.weather_data,
    calendarEvents: job.calendar_events,
    contentData: contentData
  };

  // Get dynamic limits based on user's duration
  const duration = context.dayStartLength || 240;
  const { maxTokens, targetWords } = getTokenLimits(duration);
  
  // Log the dynamic scaling for debugging
  console.log(`[DEBUG] Duration: ${duration}s, Target words: ${targetWords}, Max tokens: ${maxTokens}`);
  
  // Create prompt for GPT-4
  const prompt = buildScriptPrompt(context);
  
  // Log the prompt for debugging
  console.log('[DEBUG] Prompt length:', prompt.length, 'characters');
  console.log('[DEBUG] Full prompt being sent to GPT-4:');
  console.log('================== PROMPT START ==================');
  console.log(prompt);
  console.log('================== PROMPT END ==================');

  // Few-shot example to lock in the style
  const fewShotExample = {
    role: 'system',
    content: `EXAMPLE OF CORRECT STYLE (for a random user, do not copy facts or use any of this data):
Good morning, Jordan, it's Monday, August eighteenth. This is DayStart!

[3 second pause]

The sun is sliding up over Los Angeles, and Mar Vista will be feeling downright summery today. Highs in the low eighties with just a whisper of ocean breeze, which means you'll want to keep a cold drink nearby. The good news — no sign of that sticky humidity we had last week. The bad news — traffic is still traffic, and the four oh five is basically allergic to being on time.

[1 second pause]

Your calendar is looking friendly enough. The team stand-up at nine should be short, but if history is any guide, "short" will be defined differently by everyone on the Zoom call. At three, you've got that dentist appointment — and if you keep putting it off, your teeth are going to file for separation. Consider this your polite reminder not to cancel again.

[1 second pause]

Meanwhile in the wider world, the headlines are a mixed bag. Over the weekend, a coalition of state governors signed on to a renewable energy compact, promising faster timelines for solar build-outs. Critics say the deadlines are ambitious; optimists say at least somebody's trying. Abroad, markets are still churning on the back of last week's central bank moves in Europe. Closer to home, the wildfire situation up north is easing, thanks to a fortunate stretch of cooler nights. And if you needed a dose of levity, one of the top-trending stories this morning is a rescue operation for a dog that somehow managed to get itself stuck inside a pizza oven in Chicago. The pup is fine — the pizza, less so.

[1 second pause]

Sports-wise, the Dodgers pulled off a walk-off win against the Giants, which is exactly the sort of drama that makes the neighbors either cheer or swear depending on which hat they were wearing. The Sparks have a midweek game coming up, but for now they've got a few days to recover.

[1 second pause]

Markets open steady. Your tickers are front and center — Amazon is trading near one hundred thirty dollars, up one point two percent, while Nvidia is softer, off half a point. Microsoft is flat. Indices are basically unchanged.

[1 second pause]

A thought for the day: "Discipline is remembering what you want." It doesn't have to mean perfect routines or Instagram-worthy meal prep. Sometimes it just means shutting the laptop lid at six and remembering there's a world outside of emails.

[1 second pause]

And that's your start, Jordan. Step out into this Monday with a little humor, a little focus, and maybe even a little patience for that dentist.

Peel into this Monday with intention — because even bananas don't get eaten in one bite.

[1 second pause]

That's it for today. Have a good DayStart.

[2 second pause]

- REMINDER, THIS WAS AN EXAMPLE OF CORRECT STYLE (for a random user, do not copy facts or use any of this data).`
  };

  const systemMessage = {
    role: 'system',
    content: 'You are a professional morning briefing writer for a TTS wake-up app. Follow the user instructions exactly and obey the output contract.'
  };

  const userMessage = {
    role: 'user',
    content: prompt
  };

  const response = await withRetry(() => fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openaiApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini', // Cost-effective script generation
      messages: [fewShotExample, systemMessage, userMessage],
      max_tokens: maxTokens,    // Dynamic based on user's duration
      temperature: 0.5,         // tighter adherence
      top_p: 1,
    }),
  }), 3, 600, 45000, 'OpenAI-ContentGeneration');

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status}`);
  }

  const data = await response.json();
  
  // Log the response for debugging
  if (Deno.env.get('DEBUG') === '1') {
    console.log('[DEBUG] GPT-4 Response:', {
      model: data.model,
      usage: data.usage,
      finish_reason: data.choices?.[0]?.finish_reason
    });
  }
  
  const rawScript = data.choices?.[0]?.message?.content;

  if (!rawScript) {
    console.error('[DEBUG] No script in response. Full response:', JSON.stringify(data, null, 2));
    throw new Error('No script generated by OpenAI');
  }
  
  console.log('[DEBUG] Raw script from GPT-4:');
  if (Deno.env.get('DEBUG') === '1') {
    console.log('================== RAW SCRIPT START ==================');
    console.log(rawScript);
    console.log('================== RAW SCRIPT END ==================');
  }

  // Sanitize the script for TTS
  let script = sanitizeForTTS(rawScript);
  
  if (!script) {
    throw new Error('Script was empty after sanitization');
  }
  
  // Fix any unclosed break tags
  script = fixBreakTags(script);
  
  // Log final script for debugging if break tags were found
  const breakCount = (script.match(/<break/g) || []).length;
  if (breakCount > 0) {
    console.log(`[DEBUG] Script contains ${breakCount} break tags after fixing`);
    // Log a sample of the break tags for verification
    const breakMatches = script.match(/<break[^>]*>/g) || [];
    breakMatches.slice(0, 3).forEach((tag, i) => {
      console.log(`[DEBUG] Break tag ${i + 1}: ${tag}`);
    });
  }

  // Post-process: adjust to target band if outside bounds, without inventing new facts
  try {
    const target = getTokenLimits(duration).targetWords;
    const band = { min: Math.round(target * 0.9), max: Math.round(target * 1.1) };

    // Build a conservative context JSON for the adjust step
    const storyLimits = getStoryLimits(duration);
    const flattenedNews = flattenAndDedupeNews(context.contentData?.news || []).slice(0, 80);
    const allSports = flattenAndParseSports(context.contentData?.sports || []);
    const sportsToday = filterValidSportsItems(allSports, context.date, context.timezone).slice(0, 15);
    const sportsTeamWhitelist = teamWhitelistFromSports(sportsToday);
    const dataForBand = {
      user: {
        preferredName: context.preferredName || 'there',
        timezone: context.timezone,
        location: context.locationData || null,
      },
      date: { iso: context.date },
      duration: { seconds: duration, targetWords: target },
      limits: storyLimits,
      include: {
        weather: !!context.includeWeather,
        news: !!context.includeNews,
        sports: !!context.includeSports,
        stocks: !!context.includeStocks,
        quotes: !!context.includeQuotes,
        calendar: Array.isArray(context.calendarEvents) && context.calendarEvents.length > 0,
      },
      weather: context.weatherData || null,
      news: flattenedNews,
      sports: sportsToday,
      sportsTeamWhitelist,
      stocks: {
        sources: (context.contentData?.stocks || []).slice(0, 20),
        focusSymbols: context.stockSymbols || [],
      },
      calendarEvents: context.calendarEvents || [],
    };

    script = await adjustToTargetBand(
      script,
      band,
      JSON.stringify(dataForBand, null, 2),
      openaiApiKey
    );
  } catch (e) {
    console.warn('[DEBUG] adjustToTargetBand failed or skipped:', e?.message || e);
  }

  // Calculate cost based on token usage (GPT-4o mini pricing)
  const usage = data.usage;
  const inputCost = (usage.prompt_tokens / 1_000_000) * 0.15;  // $0.15 per 1M input tokens
  const outputCost = (usage.completion_tokens / 1_000_000) * 0.60;  // $0.60 per 1M output tokens
  const totalCost = Number((inputCost + outputCost).toFixed(5));

  console.log(`[DEBUG] OpenAI usage: ${usage.prompt_tokens} input + ${usage.completion_tokens} output tokens = $${totalCost}`);
  const words = script.trim().split(/\s+/).length;
  const estimatedDurationSec = Math.round((words / 145) * 60);
  console.log(`[DEBUG] Script length: ${words} words (sanitized from ${rawScript.split(' ').length} words)`);
  console.log(`[DEBUG] Estimated duration: ${estimatedDurationSec}s at 145 wpm`);
  console.log(`[DEBUG] Dynamic scaling: ${Math.round(context.dayStartLength/60)}min → ${getTokenLimits(context.dayStartLength).targetWords} word target, ${maxTokens} max tokens`);
  
  // Alert if script is too short (info level, not error)
  const expectedWords = getTokenLimits(context.dayStartLength).targetWords;
  const actualWords = script.split(' ').length;
  if (actualWords < expectedWords * 0.5) {
    console.log(`[DEBUG] ⚠️ Script is significantly shorter than expected! Expected ~${expectedWords} words, got ${actualWords} words`);
  }

  return {
    content: script,
    cost: totalCost
  };
}

// Ensure script length fits the computed band by expanding or tightening without inventing facts
async function adjustToTargetBand(text: string, band: { min: number; max: number }, contextJSON: string, openaiApiKey: string): Promise<string> {
  const words = text.trim().split(/\s+/).length;
  if (words >= band.min && words <= band.max) return text;

  const direction = words < band.min ? 'expand' : 'tighten';
  const delta = words < band.min ? band.min - words : words - band.max;

  const requested = Math.round(delta);
  const instruction = `
You previously wrote a morning TTS script. ${direction.toUpperCase()} it by ${requested} words (±15 words).
- Keep exactly the same facts; do NOT add names/teams not in JSON.
- If expanding: prioritize news and quotes first - add deeper context to the top news stories, then enrich the quote with brief reflection, then add details to weather and calendar. Only enrich by rephrasing or expanding reflection. Do not invent new factual details.
- If tightening: remove the least important detail from stocks first, then trim the last news item, avoiding cuts to quotes.
- Preserve the pausing style (—, …, blank lines) and tone.
Return ONLY the revised script.
DATA YOU CAN USE (JSON):
${contextJSON}
`;

  const resp = await withRetry(() => fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${openaiApiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'user', content: instruction },
        { role: 'assistant', content: text }
      ],
      temperature: 0.2,
      max_tokens: 900
    })
  }), 3, 600, 45000, 'OpenAI-TTS-Cleanup');

  const j = await resp.json();
  return j?.choices?.[0]?.message?.content?.trim() || text;
}

async function generateAudio(script: string, job: any, attemptNumber: number = 1): Promise<{success: boolean, audioData?: Uint8Array, duration?: number, cost?: number, provider?: string, error?: string}> {
  // Attempts 1-2: Use OpenAI as primary
  if (attemptNumber <= 2) {
    console.log(`Attempt ${attemptNumber}: Using OpenAI TTS`);
    return await generateAudioWithOpenAI(script, job);
  }

  // Attempt 3+: Fall back to ElevenLabs
  // Creator Plan: 5 concurrent requests, 100K chars/month, $0.30/1K chars
  const elevenlabsApiKey = Deno.env.get('ELEVENLABS_API_KEY');
  if (!elevenlabsApiKey) {
    throw new Error('ElevenLabs API key not configured');
  }

  // Map voice option to ElevenLabs voice ID
  const voiceMap: Record<string, string> = {
    // Numbered keys
    'voice1': 'wdRkW5c5eYi8vKR8E4V9',
    'voice2': '21m00Tcm4TlvDq8ikWAM',
    'voice3': 'QczW7rKFMVYyubTC1QDk',
    // Name keys (accepted for compatibility)
    'grace': 'wdRkW5c5eYi8vKR8E4V9',
    'rachel': '21m00Tcm4TlvDq8ikWAM',
    'matthew': 'QczW7rKFMVYyubTC1QDk',
  };

  const normalizedVoiceKey = String(job.voice_option || '').toLowerCase();
  const voiceId = voiceMap[normalizedVoiceKey] || voiceMap['voice1'];

  console.log(`Attempt ${attemptNumber}: Using ElevenLabs TTS`);
  
  // Prepare script for ElevenLabs (convert bracketed pauses to SSML)
  const processedScript = prepareTTSScript(script, 'elevenlabs');
  
  const response = await withRetry(() => fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: 'POST',
    headers: {
      'Accept': 'audio/aac',
      'Content-Type': 'application/json',
      'xi-api-key': elevenlabsApiKey,
    },
    body: JSON.stringify({
      text: processedScript,
      model_id: 'eleven_flash_v2_5',
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.7,
        style: 0.3,
        use_speaker_boost: true
      }
    }),
  }), 1, 600, 45000, `ElevenLabs-TTS-${normalizedVoiceKey}`); // Only 1 try here, retries handled at higher level

  if (!response.ok) {
    const errorText = await response.text();
    return { success: false, error: `ElevenLabs API error: ${response.status} - ${errorText}` };
  }

  const audioData = new Uint8Array(await response.arrayBuffer());
  
  // Estimate duration based on script length (rough approximation)
  const estimatedDuration = Math.ceil(script.length / 15); // ~15 chars per second

  // Calculate cost: $0.30 per 1,000 characters (Creator Plan)
  const characterCount = script.length;
  const cost = Number(((characterCount / 1000) * 0.30).toFixed(5));
  
  console.log(`ElevenLabs usage: ${characterCount} characters = $${cost}`);

  return {
    success: true,
    audioData,
    duration: estimatedDuration,
    cost,
    provider: 'elevenlabs'
  };
}

function convertBracketedPausesToSSML(script: string): string {
  // Convert bracketed pauses to SSML for ElevenLabs
  return script.replace(/\[(\d+) second pause\]/g, (match, seconds) => {
    return `<break time="${seconds}s"/>`;
  });
}

function prepareTTSScript(script: string, provider: 'openai' | 'elevenlabs'): string {
  if (provider === 'openai') {
    // OpenAI doesn't support SSML, so replace bracketed pauses with natural punctuation
    let processedScript = script;
    
    // Replace bracketed pauses with newlines (which create natural pauses in OpenAI TTS)
    processedScript = processedScript.replace(/\[1 second pause\]/g, '\n\n'); // short pause
    processedScript = processedScript.replace(/\[2 second pause\]/g, '\n\n\n'); // medium pause
    processedScript = processedScript.replace(/\[3 second pause\]/g, '\n\n\n\n'); // longer pause
    
    // Remove any remaining bracketed pauses with a default pause
    processedScript = processedScript.replace(/\[\d+ second pause\]/g, '\n\n');
    
    return processedScript;
  } else if (provider === 'elevenlabs') {
    // ElevenLabs supports SSML, so convert bracketed pauses
    return convertBracketedPausesToSSML(script);
  }
  
  // Default: return script as-is
  return script;
}

function normalizeSymbol(symbol: string): string {
  // Normalize symbol for comparison - trim whitespace and convert to uppercase
  return symbol.trim().toUpperCase();
}

async function generateAudioWithOpenAI(script: string, job: any): Promise<{success: boolean, audioData?: Uint8Array, duration?: number, cost?: number, provider?: string, error?: string}> {
  const openaiApiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openaiApiKey) {
    throw new Error('OpenAI API key not configured');
  }

  // Map voice option to OpenAI voice
  const voiceMap: Record<string, string> = {
    'voice1': 'sage',
    'voice2': 'shimmer',
    'voice3': 'ash',
  };

  const normalizedVoiceKey = String(job.voice_option || '').toLowerCase();
  const voiceNumber = normalizedVoiceKey.match(/voice(\d)/)?.[1] || '1';
  const voice = voiceMap[`voice${voiceNumber}`] || 'sage';

  console.log(`Using OpenAI TTS with voice: ${voice}`);
  
  // Prepare script for OpenAI (replace bracketed pauses with natural punctuation)
  const processedScript = prepareTTSScript(script, 'openai');

  try {
    const response = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini-tts',
        voice: voice,
        input: processedScript,
        response_format: 'aac'
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      return { success: false, error: `OpenAI TTS API error: ${response.status} - ${errorText}` };
    }

    const audioData = new Uint8Array(await response.arrayBuffer());
    
    // Estimate duration based on script length (rough approximation)
    const estimatedDuration = Math.ceil(script.length / 15); // ~15 chars per second

    // Calculate cost for OpenAI TTS
    // $0.60 per 1M input characters + ~$12 per 1M output tokens
    // Rough estimate: ~$0.015 per minute of audio
    const characterCount = script.length;
    const inputCost = (characterCount / 1_000_000) * 0.60;
    const estimatedMinutes = estimatedDuration / 60;
    const outputCost = estimatedMinutes * 0.015;
    const totalCost = Number((inputCost + outputCost).toFixed(5));
    
    console.log(`OpenAI TTS usage: ${characterCount} characters, ~${estimatedMinutes.toFixed(2)} minutes = $${totalCost}`);

    return {
      success: true,
      audioData,
      duration: estimatedDuration,
      cost: totalCost,
      provider: 'openai'
    };
  } catch (error) {
    console.error('OpenAI TTS error:', error);
    return { success: false, error: error.message };
  }
}

function buildScriptPrompt(context: any): string {
  // Parse the date in the user's timezone, not UTC
  console.log(`📅 Parsing date: ${context.date} in timezone: ${context.timezone}`);
  
  const dateParts = context.date.split('-').map(Number);
  console.log(`📅 Date parts: year=${dateParts[0]}, month=${dateParts[1]}, day=${dateParts[2]}`);
  
  // Validate date parts
  if (dateParts.length !== 3 || dateParts.some(part => isNaN(part))) {
    throw new Error(`Invalid date format: ${context.date}. Expected YYYY-MM-DD format.`);
  }
  
  const [year, month, day] = dateParts;
  
  // Validate date ranges
  if (year < 2020 || year > 2030) {
    throw new Error(`Invalid year: ${year}. Must be between 2020 and 2030.`);
  }
  if (month < 1 || month > 12) {
    throw new Error(`Invalid month: ${month}. Must be between 1 and 12.`);
  }
  if (day < 1 || day > 31) {
    throw new Error(`Invalid day: ${day}. Must be between 1 and 31.`);
  }
  
  // Create a date string in ISO format to use with toLocaleDateString
  // This ensures the date is interpreted correctly in the user's timezone
  const dateString = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T12:00:00`;
  console.log(`📅 Using date string: ${dateString} with timezone: ${context.timezone}`);
  
  // Parse the date in the user's timezone by using the date string directly
  const date = new Date(dateString).toLocaleDateString('en-US', { 
    weekday: 'long', 
    month: 'long', 
    day: 'numeric',
    timeZone: context.timezone
  });
  
  console.log(`📅 Formatted date: ${date}`);
  
  const duration = context.dayStartLength || 240;
  const { targetWords } = getTokenLimits(duration);
  const lowerBound = Math.round(targetWords * 0.9);
  const upperBound = Math.round(targetWords * 1.1);
  const storyLimits = getStoryLimits(duration);
  
  // Prefer compact news if available, else fall back to raw
  function collectCompactNews(cd: any): Array<{description: string, source?: string, publishedAt?: string}> {
    const out: Array<{description: string, source?: string, publishedAt?: string}> = []
    for (const src of cd?.news || []) {
      const items = src?.data?.compact?.news
      if (Array.isArray(items)) {
        for (const it of items) {
          const desc = String(it?.description || '').trim()
          if (desc) out.push({ description: desc, source: it?.source || src?.source, publishedAt: it?.publishedAt })
        }
      }
    }
    return out
  }
  const compactNews = collectCompactNews(context.contentData).slice(0, 40)

  // Parse and flatten sports from all sources, then filter for valid items
  const allSports = flattenAndParseSports(context.contentData?.sports || []);
  console.log(`[DEBUG] Parsed ${allSports.length} sports events from ${context.contentData?.sports?.length || 0} sources`);
  
  // Enforce valid, present-day sports items only
  const sportsToday = filterValidSportsItems(allSports, context.date, context.timezone).slice(0, 15);

  // Filter stocks based on market hours (exclude equities on weekends, keep crypto)
  const isWeekendDay = isWeekend(context.date, context.timezone);
  console.log(`[DEBUG] Date: ${context.date}, Timezone: ${context.timezone}, Is Weekend: ${isWeekendDay}`);
  
  // Parse and flatten stocks from all sources
  const allStocks = flattenAndParseStocks(context.contentData?.stocks || []);
  console.log(`[DEBUG] Parsed ${allStocks.length} stocks from ${context.contentData?.stocks?.length || 0} sources`);
  
  // Classify stocks by asset type using symbol patterns
  const crypto = allStocks.filter(s => {
    const symbol = String(s.symbol || '').toUpperCase();
    return symbol.includes('-USD') || symbol.includes('-USDT') || symbol.includes('-BTC') || symbol.includes('-ETH');
  });
  
  // Major ETFs that should be available even on weekends for user focus
  const majorETFs = ['SPY', 'QQQ', 'IWM', 'VTI', 'VOO', 'DIA', 'VEA', 'IEFA', 'AGG', 'LQD'];
  
  const equities = allStocks.filter(s => {
    const symbol = String(s.symbol || '').toUpperCase();
    return !(symbol.includes('-USD') || symbol.includes('-USDT') || symbol.includes('-BTC') || symbol.includes('-ETH'));
  });
  
  const alwaysAvailableETFs = equities.filter(s => {
    const symbol = String(s.symbol || '').toUpperCase();
    return majorETFs.includes(symbol);
  });
  
  // Include crypto always, equities on weekdays, major ETFs always
  const filteredStocks = isWeekendDay ? [...crypto, ...alwaysAvailableETFs] : [...equities, ...crypto];
  console.log(`[DEBUG] Total stocks: ${allStocks.length}, Equities: ${equities.length}, Crypto: ${crypto.length}, After weekend filter: ${filteredStocks.length}`);

  // Get day context for encouragements and holidays
  const dayContext = getDayContext(context.date, context.timezone);
  const encouragement = dayContext.encouragements.length > 0 
    ? randomChoice(dayContext.encouragements) 
    : "";

  // Provide machine-readable context so the model can cite specifics cleanly
  const data = {
    user: {
      preferredName: context.preferredName || "there",
      timezone: context.timezone,
      location: context.locationData || null,
    },
    date: { iso: context.date, friendly: date },
    duration: { seconds: duration, targetWords },
    limits: storyLimits,
    include: {
      weather: !!context.includeWeather,
      news: !!context.includeNews,
      sports: !!context.includeSports,
      stocks: !!context.includeStocks,
      quotes: !!context.includeQuotes,
      calendar: Array.isArray(context.calendarEvents) && context.calendarEvents.length > 0
    },
    budget: sectionBudget(duration, {
      weather: !!context.includeWeather,
      news: !!context.includeNews,
      sports: !!context.includeSports,
      stocks: !!context.includeStocks,
      quotes: !!context.includeQuotes,
      calendar: Array.isArray(context.calendarEvents) && context.calendarEvents.length > 0
    }),
    weather: context.weatherData || null,
    news: (compactNews.length > 0
      ? compactNews.map(n => ({
          title: n.description.slice(0, 160),
          description: n.description,
          source: n.source || '',
          publishedAt: n.publishedAt || ''
        }))
      : flattenAndDedupeNews(context.contentData?.news || []).map(a => compactNewsItem(a))
    ).slice(0, 40),
    sports: sportsToday,
    sportsTeamWhitelist: teamWhitelistFromSports(sportsToday),
    localityHints: localityHints(context.locationData),
    transitions: getRandomTransitions(),
    signOff: getRandomSignOff(),
    dayContext: {
      weekday: dayContext.label,
      encouragement: encouragement,
      isHoliday: dayContext.isHoliday
    },
    stocks: {
      focus: (() => {
        const userSymbols = (context.stockSymbols || []).map(normalizeSymbol);
        
        if (userSymbols.length > 0) {
          // User has specific symbols - filter for those
          return filteredStocks
            .filter(s => {
              const normalizedStockSymbol = normalizeSymbol(s.symbol || '');
              
              // Try exact symbol match first
              if (userSymbols.includes(normalizedStockSymbol)) {
                return true;
              }
              
              // Fallback: check if user symbol appears in company name
              const companyName = String(s.name || '').toUpperCase();
              return userSymbols.some(userSym => companyName.includes(userSym));
            })
            .map(s => ({
              name: s.name,
              symbol: s.symbol,
              price: s.price,
              change: s.change,
              percentChange: s.percentChange,
              timestamp: s.timestamp,
              isCrypto: crypto.some(c => c.symbol === s.symbol)
            }));
        } else {
          // No user symbols - select major indices and top movers for focus
          const majorIndices = ['SPY', 'QQQ', 'IWM', 'DIA'];
          const majorStocks = ['AAPL', 'MSFT', 'GOOGL', 'AMZN'];
          const defaultFocusSymbols = [...majorIndices, ...majorStocks];
          
          // First try to get major indices/stocks
          const focusStocks = filteredStocks
            .filter(s => defaultFocusSymbols.includes(s.symbol || ''))
            .slice(0, storyLimits.stocks);
          
          // If we don't have enough, add top movers by percent change
          if (focusStocks.length < storyLimits.stocks) {
            const topMovers = filteredStocks
              .filter(s => !focusStocks.some(f => f.symbol === s.symbol))
              .sort((a, b) => Math.abs(b.percentChange || 0) - Math.abs(a.percentChange || 0))
              .slice(0, storyLimits.stocks - focusStocks.length);
            
            focusStocks.push(...topMovers);
          }
          
          return focusStocks
            .slice(0, storyLimits.stocks)
            .map(s => ({
              name: s.name,
              symbol: s.symbol,
              price: s.price,
              change: s.change,
              percentChange: s.percentChange,
              timestamp: s.timestamp,
              isCrypto: crypto.some(c => c.symbol === s.symbol)
            }));
        }
      })(),
      others: []  // Will be populated after focus is determined
    },
    quotePreference: context.quotePreference || null,
    calendarEvents: context.calendarEvents || []
  };
  
  // Now populate others based on what's in focus
  const focusSymbols = data.stocks.focus.map(f => f.symbol);
  data.stocks.others = filteredStocks
    .filter(s => !focusSymbols.includes(s.symbol))
    .slice(0, 20)
    .map(s => ({
      name: s.name,
      symbol: s.symbol,
      price: s.price,
      change: s.change,
      percentChange: s.percentChange,
      isCrypto: crypto.some(c => c.symbol === s.symbol)
    }));
  
  // Comprehensive debug logging for content availability
  console.log('====== CONTENT AVAILABILITY DEBUG ======');
  console.log(`[DEBUG] Date: ${context.date}, Timezone: ${context.timezone}`);
  console.log(`[DEBUG] Is Weekend: ${isWeekendDay}`);
  
  // Raw content counts (before filtering)
  console.log('[DEBUG] Raw content counts:');
  console.log(`  - News sources: ${context.contentData?.news?.length || 0}`);
  console.log(`  - Total news articles: ${context.contentData?.news?.reduce((sum, src) => sum + (src?.data?.articles?.length || 0), 0) || 0}`);
  console.log(`  - Sports sources: ${context.contentData?.sports?.length || 0}`);
  console.log(`  - Total sports events: ${allSports.length} (parsed from all sources)`);
  console.log(`  - Stock sources: ${context.contentData?.stocks?.length || 0}`);
  console.log(`  - Total stock quotes: ${allStocks.length}`);
  
  // Filtered content counts (after processing)
  console.log('[DEBUG] Filtered content counts:');
  console.log(`  - News (compact): ${compactNews.length}`);
  console.log(`  - Sports today: ${sportsToday.length}`);
  console.log(`  - Stocks (filtered): ${filteredStocks.length} (${equities.length} equities, ${crypto.length} crypto)`);
  
  // Final data structure counts
  console.log('[DEBUG] Final data structure:');
  console.log(`  - News in data: ${data.news.length}`);
  console.log(`  - Sports in data: ${data.sports.length}`);
  console.log(`  - Sports teams whitelist: ${data.sportsTeamWhitelist.length}`);
  console.log(`  - Stocks focus: ${data.stocks.focus.length} - ${JSON.stringify(data.stocks.focus.map(s => s.symbol))}`);
  console.log(`  - Stocks others: ${data.stocks.others.length}`);
  console.log(`  - Calendar events: ${data.calendarEvents.length}`);
  
  // User preferences
  console.log('[DEBUG] User preferences:');
  console.log(`  - Include weather: ${context.includeWeather}`);
  console.log(`  - Include news: ${context.includeNews}`);
  console.log(`  - Include sports: ${context.includeSports}`);
  console.log(`  - Include stocks: ${context.includeStocks}`);
  console.log(`  - Include quotes: ${context.includeQuotes}`);
  console.log(`  - User stock symbols: ${JSON.stringify(context.stockSymbols || [])}`);
  console.log('========================================');

  const styleAddendum = `
PAUSING & FLOW
- Use em dashes (—) for short pauses and ellipses (…) for softer rests.
- Put a blank line between sections to create a natural breath.
- Add bracketed pauses on their own line between major sections for longer pauses using EXACTLY this format: "[1 second pause]" or "[2 second pause]"
- CRITICAL: Use the exact format with square brackets, number, "second pause" - e.g., [3 second pause]
- Start each section with a short sentence. Then continue.
- Keep sentences mostly under 18 words.
`;

  return `
You are a professional morning briefing writer for a TTS wake-up app. Your job: write a concise, warm, highly-personalized script that sounds natural when spoken aloud.

STYLE
- Warm, conversational, confident; no filler.
- Use short sentences and varied rhythm.
- Prefer specifics over generalities. If a section has no data, gracefully skip it.
- Sprinkle one light, human moment max (a nudge, not a joke barrage).
- IMPORTANT: For TTS readability:
  - Always use full company names instead of stock tickers (e.g., "Apple" not "AAPL", "Tesla" not "TSLA", "S&P 500 ETF" not "SPY")
  - Don't add "Inc" at the end of company names (use "Apple", not "Apple Inc.")
  - Spell out all numbers and prices in words (e.g., "two hundred thirty dollars and eighty-nine cents" not "$230.89", "down zero point three percent" not "down 0.3%")
${styleAddendum}
 - Use 1–2 transitions between sections. Add bracketed pauses on their own line between major sections for natural pauses using EXACTLY this format: "[1 second pause]".
 - Keep ellipses to ≤1 per paragraph within sections and em dashes to ≤2 per paragraph.
 - Stay roughly within the provided per-section word budget (±25%). If a section is omitted, redistribute its budget to News first, then Weather/Calendar.

LENGTH & PACING
  - Target ${targetWords} words total (±10%). Keep between ${lowerBound}–${upperBound} words. Duration: ${Math.round(duration/60)} minutes.
- Adjust depth based on time: shorter = headlines only, longer = more context.
  - If the draft is shorter than ${lowerBound}, expand by adding one concrete, relevant detail in the highest-priority sections (weather, calendar, top news) until within range. If longer than ${upperBound}, tighten by removing the least important detail. No filler.

CONTENT PRIORITIZATION
  - News: Use ${storyLimits.news === 1 ? '1 story' : `${storyLimits.news - 1}–${storyLimits.news} stories`}, depending on significance and space. Choose by local relevance using user.location when available; otherwise pick the most significant stories. For longer scripts, include deeper context and background for major stories.
- Sports: Include ${storyLimits.sports} update(s) max in your script. You have more options to choose from, but select only the most relevant ${storyLimits.sports} for the user based on location, significance, or excitement. If off-season or no fixtures, skip gracefully.
- Stocks: Include ${storyLimits.stocks} market point(s) max in your script. You have access to more stocks for better selection, but mention only ${storyLimits.stocks} total. Always prioritize user's focus symbols if provided.
 - Weather: If present, include high/low temperatures (from highTemperatureF/lowTemperatureF), precipitation chance (from precipitationChance), and current conditions. Spell out all temperatures and percentages in words for TTS.
 - Astronomy: If a meteor shower is present, add viewing advice tailored to the user's location (window, direction, light pollution note). Otherwise, omit.
- Calendar: Call out today's top 1–3 items with time ranges and one helpful nudge. PRIORITIZE personal/social events over routine ones: favor events with people (dinners, meetings with friends), celebrations (birthdays, parties), or unique activities (concerts, trips, appointments) over standard work meetings, commutes, or routine tasks.

FACT RULES
- Use ONLY facts present in the JSON data.
- If a desired detail is missing, omit it gracefully—do not invent.
- Do not generalize. If you have at least one company in stocks.focus, always mention it specifically by name. Avoid generic phrases like "the market is mixed."
- If today is Saturday or Sunday, omit equity updates entirely. Only mention cryptocurrencies if present.
- Never mention a team or matchup unless it appears in the sports data for today.
 - Mention ONLY teams present in sportsTeamWhitelist (exact names). If the sports array is empty, omit the sports section entirely.
 - When choosing news, prefer items that mention the user's neighborhood/city/county/adjacent areas; next, state-level; then national; then international. If user.location.neighborhood exists, use it for hyper-local references (e.g., "Mar Vista" instead of just "Los Angeles").
 - Use 1–2 transitions, choosing from data.transitions.
 - Stocks: Always mention EACH company in stocks.focus by name, one sentence each. Include price and direction (up/down, with rounded percent change). If multiple focus companies exist, weave them together (e.g., "Apple is down, while Tesla is climbing"). For cryptocurrencies, use subtle context like "crypto trades around the clock" to make weekend updates feel intentional. Mention broader indices (from stocks.others) ONLY if space allows. NEVER say "the rest of the market is mixed" unless no other data is available. Always use company names (Apple, Tesla, Bitcoin, Ethereum, etc.) not tickers. Format prices without cents (e.g., "one hundred fifty dollars" not "one hundred fifty dollars and twenty-five cents") and round percentages to nearest tenth (e.g., "up two point three percent" not "up two point three four percent").
 - Quote: If data.quotePreference is provided, generate a quote that authentically reflects that tradition/philosophy (e.g., "Buddhist" = Buddhist teaching, "Stoic" = Stoic wisdom, "Christian" = Christian scripture/teaching, etc.). Keep it genuine to the selected style. For longer scripts, add more context or a brief reflection to enrich the quote section.

CONTENT ORDER (adapt if sections are missing)
1) Standard opening: "Good morning, {user.preferredName}, it's {friendly date}. This is DayStart!" followed by a three-second pause using EXACTLY "[3 second pause]" on its own line.
1a) Day context (if dayContext.encouragement is provided): Include it naturally after the greeting, one or two sentences max. Vary tone so it doesn't feel canned.
2) Weather (only if include.weather): actionable and hyper-relevant to the user's day. Reference the specific neighborhood if available (e.g., "Mar Vista will see..." instead of "Los Angeles will see...").
3) Calendar (if present): call out today's 1–2 most important items with a helpful reminder.
4) News (if include.news): Select from the provided articles. Lead with the most locally relevant (based on user.location) or highest-impact items.
5) Sports (if include.sports): Brief, focused update. Mention major local teams or significant national stories.
6) Stocks (if include.stocks): Market pulse using company names and numbers spelled out. Call out focusSymbols prominently when present.
7) Quote (if include.quotes): Select a quote that matches the user's quotePreference (if provided in data). The quote should align with that tradition/style (e.g., Buddhist wisdom, Stoic philosophy, Christian scripture, etc.). Follow with a one-line tie-back to today's vibe.
8) Close with the provided signOff from the data — choose the one that fits the day's tone best.
9) Add a 1-second pause after the signOff using EXACTLY "[1 second pause]" on its own line.
10) Add the standardized ending phrase: "That's it for today. Have a good DayStart."
11) End the script with a final 2-second pause using EXACTLY "[2 second pause]" on its own line.

STRICT OUTPUT RULES — DO NOT BREAK
- Output: PLAIN TEXT ONLY.
- No markdown. No asterisks. No headings. No brackets. No stage directions. No emojis.
- No labels like "Weather:" or "News:". Just speak naturally.
- No meta-commentary ("here's your script", "as an AI", etc.).
  - Before returning, quickly self-check that the script is within ${lowerBound}–${upperBound} words.

DATA YOU CAN USE (JSON):
${JSON.stringify(data, null, 2)}

Write the final script now, obeying all rules above. Return ONLY the script text, nothing else.
`.trim();
}

function createResponse(success: boolean, processedCount: number, failedCount: number, message: string, requestId: string, status: number = 200): Response {
  const response: ProcessJobsResponse = {
    success,
    processed_count: processedCount,
    failed_count: failedCount,
    message,
    request_id: requestId
  };

  return new Response(JSON.stringify(response), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}