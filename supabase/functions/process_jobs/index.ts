import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

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
    return { news: 1, sports: 1, stocks: 1 };
  } else if (seconds <= 180) {
    // 3 minutes: light coverage
    return { news: 2, sports: 1, stocks: 1 };
  } else if (seconds <= 300) {
    // 5 minutes: standard coverage
    return { news: 3, sports: 1, stocks: 2 };
  } else {
    // 5+ minutes: comprehensive coverage
    return { news: 4, sports: 2, stocks: 2 };
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

// Filter sports items to today's fixtures/results and valid statuses
function filterValidSportsItems(sports: any[] = [], dateISO: string): any[] {
  const today = new Date(dateISO).toISOString().slice(0, 10);
  return (sports || []).filter((ev: any) => {
    const d = String(ev?.date || '').slice(0, 10);
    const status = String(ev?.status || '').toUpperCase();
    return d === today && (status === 'FT' || status === 'NS' || status === 'LIVE');
  });
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
    ['news',      include.news ? 340 : 0],
    ['sports',    include.sports ? 90 : 0],
    ['stocks',    include.stocks ? 80 : 0],
    ['quote',     include.quotes ? 40 : 0],
    ['close',     40],
  ];
  const total = base.reduce((sum, [, w]) => sum + w, 0) || 1;
  const target = targetWords(seconds);
  const entries = base.map(([k, w]) => [k, Math.round((w / total) * target)] as [string, number]);
  return Object.fromEntries(entries);
}

// Extract simple locality hints (no hardcoded locales)
function localityHints(loc: any): string[] {
  const hints: string[] = [];
  if (loc?.city) hints.push(String(loc.city).toLowerCase());
  if (loc?.county) hints.push(String(loc.county).toLowerCase());
  if (loc?.metro) hints.push(String(loc.metro).toLowerCase());
  if (loc?.state) hints.push(String(loc.state).toLowerCase());
  return Array.from(new Set(hints)).filter(Boolean);
}

// Deterministic transition menu for smoother section changes
const transitions = {
  toWeather: ['A quick look outside —', 'First, the sky —', 'Step one: the weather —'],
  toCalendar: ['Before you head out —', 'On your slate —', 'Two things to timebox —'],
  toNews: ['Now to the headlines …', 'In the news —', 'Closer to home —'],
  toSports: ['One sports note —', 'Quick sports pulse —', 'Around the diamond —'],
  toStocks: ['On the tape —', 'For your watchlist —', 'Markets at the open —'],
  toQuote: ['Pocket this —', 'A line to carry —', 'One thought for the morning —']
};

// Simple retry + timeout wrapper for flaky network calls
async function withRetry<T>(fn: () => Promise<T>, tries = 3, baseMs = 600, timeoutMs = 20000): Promise<T> {
  let lastErr: any;
  for (let i = 0; i < tries; i++) {
    try {
      const result = await Promise.race([
        fn(),
        new Promise<never>((_, rej) => setTimeout(() => rej(new Error('timeout')), timeoutMs))
      ]);
      return result;
    } catch (e) {
      lastErr = e;
      if (i < tries - 1) {
        await new Promise(r => setTimeout(r, baseMs * (2 ** i)));
      }
    }
  }
  throw lastErr;
}

// Sanitize script output for TTS (preserve em-dashes, ellipses, and section breaks)
function sanitizeForTTS(raw: string): string {
  let s = raw.trim();

  // Remove bracketed stage directions but keep punctuation
  s = s.replace(/\[[^\]]*?\]/g, '');

  // Strip markdown symbols but keep dashes and ellipses
  s = s.replace(/[*_#`>]+/g, '');

  // Normalize whitespace but preserve double newlines (section breaks)
  s = s
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();

  // Remove label-y lines (e.g., "Weather:", "News:")
  s = s.replace(/^(weather|news|sports|stocks|quote|calendar)\s*:\s*/gim, '');

  // Remove any "Good morning" duplicates if model adds extras
  s = s.replace(/^(good morning[^.]*\.\s*){2,}/gi, (match, group) => group);

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
    // Only allow POST from authorized sources
    if (req.method !== 'POST') {
      return createResponse(false, 0, 0, 'Only POST method allowed', request_id);
    }

    // Basic auth check (can be enhanced with proper API keys)
    const authHeader = req.headers.get('authorization');
    const expectedToken = Deno.env.get('WORKER_AUTH_TOKEN');
    
    if (!authHeader || authHeader !== `Bearer ${expectedToken}`) {
      return createResponse(false, 0, 0, 'Unauthorized', request_id);
    }

    // Return success immediately to prevent timeout
    console.log(`Worker ${worker_id} accepted job processing request`);
    
    // Start async processing without waiting
    processJobsAsync(worker_id, request_id).catch(error => {
      console.error('Async job processing error:', error);
    });

    // Return immediate success response
    return createResponse(true, 0, 0, 'Job processing started', request_id);

  } catch (error) {
    console.error('Worker error:', error);
    return createResponse(false, 0, 0, 'Internal worker error', request_id);
  }
});

async function processJobsAsync(worker_id: string, request_id: string): Promise<void> {
  try {
    // Initialize Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Release any expired leases first
    await supabase.rpc('release_expired_leases');

    let processedCount = 0;
    let failedCount = 0;
    const maxJobs = 5; // Process up to 5 jobs per run

    // Process jobs in batches
    for (let i = 0; i < maxJobs; i++) {
      // Lease next available job
      const { data: jobId, error } = await supabase.rpc('lease_next_job', {
        worker_id,
        lease_duration_minutes: 15
      });

      if (error || !jobId) {
        console.log('No more jobs to process:', error);
        break;
      }

      console.log(`Processing job: ${jobId}`);

      try {
        const success = await processJob(supabase, jobId, worker_id);
        if (success) {
          processedCount++;
        } else {
          failedCount++;
        }
      } catch (error) {
        console.error(`Failed to process job ${jobId}:`, error);
        failedCount++;
        
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

  // Generate audio and track costs
  const audioResult = await generateAudio(scriptResult.content, job);
  
  if (!audioResult.success) {
    throw new Error(audioResult.error || 'Audio generation failed');
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

  // Mark job as complete with all costs
  await supabase
    .from('jobs')
    .update({
      status: 'ready',
      audio_file_path: audioPath,
      audio_duration: audioResult.duration ?? 0,
      transcript: scriptResult.content,
      script_cost: scriptResult.cost,
      tts_cost: audioResult.cost ?? 0,
      total_cost: totalCost,
      completed_at: new Date().toISOString(),
      worker_id: null,
      lease_until: null,
      updated_at: new Date().toISOString()
    })
    .eq('job_id', jobId);

  console.log(`Completed job ${jobId} - audio saved to ${audioPath}`);
  console.log(`Costs: Script=$${scriptResult.cost}, TTS=$${audioResult.cost}, Total=$${totalCost}`);
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
    const { data: freshContent, error: contentError } = await supabase.rpc('get_fresh_content', {
      requested_types: contentTypes
    });
    
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
  const { maxTokens } = getTokenLimits(duration);
  
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
    content: `EXAMPLE OF CORRECT STYLE (for a random user, do not copy facts):
Good morning, Sam. Happy Tuesday. Skies are clear and you'll hit the mid-70s by lunch, so a light layer is perfect.
Your 9 a.m. product sync has shifted to 9:15—worth skimming the brief on the train.
Overnight, regulators approved the chip deal; markets are cautious, but futures are flat. Keep an eye on NVDA and your QQQ position after the open.
The Sparks edged Phoenix by two; Dodgers host the Giants tonight.
"Discipline is remembering what you want." One focused block this morning will carry the day.
You've got this.`
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
      model: 'gpt-4o', // High-quality script generation
      messages: [fewShotExample, systemMessage, userMessage],
      max_tokens: maxTokens,    // Dynamic based on user's duration
      temperature: 0.5,         // tighter adherence
      top_p: 1,
    }),
  }));

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status}`);
  }

  const data = await response.json();
  
  // Log the response for debugging
  console.log('[DEBUG] GPT-4 Response:', {
    model: data.model,
    usage: data.usage,
    finish_reason: data.choices?.[0]?.finish_reason
  });
  
  const rawScript = data.choices?.[0]?.message?.content;

  if (!rawScript) {
    console.error('[DEBUG] No script in response. Full response:', JSON.stringify(data, null, 2));
    throw new Error('No script generated by OpenAI');
  }
  
  console.log('[DEBUG] Raw script from GPT-4:');
  console.log('================== RAW SCRIPT START ==================');
  console.log(rawScript);
  console.log('================== RAW SCRIPT END ==================');

  // Sanitize the script for TTS
  let script = sanitizeForTTS(rawScript);
  
  if (!script) {
    throw new Error('Script was empty after sanitization');
  }

  // Post-process: adjust to target band if outside bounds, without inventing new facts
  try {
    const target = getTokenLimits(duration).targetWords;
    const band = { min: Math.round(target * 0.9), max: Math.round(target * 1.1) };

    // Build a conservative context JSON for the adjust step
    const storyLimits = getStoryLimits(duration);
    const flattenedNews = flattenAndDedupeNews(context.contentData?.news || []).slice(0, 80);
    const sportsToday = filterValidSportsItems(context.contentData?.sports || [], context.date).slice(0, storyLimits.sports);
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
        sources: (context.contentData?.stocks || []).slice(0, storyLimits.stocks),
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

  // Calculate cost based on token usage
  const usage = data.usage;
  const inputCost = (usage.prompt_tokens / 1_000_000) * 30.00;  // $30.00 per 1M input tokens
  const outputCost = (usage.completion_tokens / 1_000_000) * 60.00;  // $60.00 per 1M output tokens
  const totalCost = Number((inputCost + outputCost).toFixed(5));

  console.log(`[DEBUG] OpenAI usage: ${usage.prompt_tokens} input + ${usage.completion_tokens} output tokens = $${totalCost}`);
  const words = script.trim().split(/\s+/).length;
  const estimatedDurationSec = Math.round((words / 145) * 60);
  console.log(`[DEBUG] Script length: ${words} words (sanitized from ${rawScript.split(' ').length} words)`);
  console.log(`[DEBUG] Estimated duration: ${estimatedDurationSec}s at 145 wpm`);
  console.log(`[DEBUG] Dynamic scaling: ${Math.round(context.dayStartLength/60)}min → ${getTokenLimits(context.dayStartLength).targetWords} word target, ${maxTokens} max tokens`);
  
  // Alert if script is too short
  const expectedWords = getTokenLimits(context.dayStartLength).targetWords;
  const actualWords = script.split(' ').length;
  if (actualWords < expectedWords * 0.5) {
    console.warn(`[DEBUG] ⚠️ Script is significantly shorter than expected! Expected ~${expectedWords} words, got ${actualWords} words`);
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
- If expanding: add one concrete detail in weather, the first news item, and calendar (if present).
- If tightening: remove the least important detail from stocks or the last news item.
- Preserve the pausing style (—, …, blank lines) and tone.
Return ONLY the revised script.
DATA YOU CAN USE (JSON):
${contextJSON}
`;

  const resp = await withRetry(() => fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${openaiApiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o',
      messages: [
        { role: 'user', content: instruction },
        { role: 'assistant', content: text }
      ],
      temperature: 0.2,
      max_tokens: 900
    })
  }));

  const j = await resp.json();
  return j?.choices?.[0]?.message?.content?.trim() || text;
}

async function generateAudio(script: string, job: any): Promise<{success: boolean, audioData?: Uint8Array, duration?: number, cost?: number, error?: string}> {
  const elevenlabsApiKey = Deno.env.get('ELEVENLABS_API_KEY');
  if (!elevenlabsApiKey) {
    throw new Error('ElevenLabs API key not configured');
  }

  // Map voice option to ElevenLabs voice ID
  const voiceMap: Record<string, string> = {
    // Numbered keys
    'voice1': 'pNInz6obpgDQGcFmaJgB',
    'voice2': '21m00Tcm4TlvDq8ikWAM',
    'voice3': 'ErXwobaYiN019PkySvjV',
    // Name keys (accepted for compatibility)
    'grace': 'pNInz6obpgDQGcFmaJgB',
    'rachel': '21m00Tcm4TlvDq8ikWAM',
    'matthew': 'ErXwobaYiN019PkySvjV',
  };

  const normalizedVoiceKey = String(job.voice_option || '').toLowerCase();
  const voiceId = voiceMap[normalizedVoiceKey] || voiceMap['voice1'];

  const response = await withRetry(() => fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: 'POST',
    headers: {
      'Accept': 'audio/aac',
      'Content-Type': 'application/json',
      'xi-api-key': elevenlabsApiKey,
    },
    body: JSON.stringify({
      text: script,
      model_id: 'eleven_monolingual_v1',
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.7,
        style: 0.3,
        use_speaker_boost: true
      }
    }),
  }));

  if (!response.ok) {
    const errorText = await response.text();
    return { success: false, error: `ElevenLabs API error: ${response.status} - ${errorText}` };
  }

  const audioData = new Uint8Array(await response.arrayBuffer());
  
  // Estimate duration based on script length (rough approximation)
  const estimatedDuration = Math.ceil(script.length / 15); // ~15 chars per second

  // Calculate cost: $0.10 per 1,000 characters
  const characterCount = script.length;
  const cost = Number(((characterCount / 1000) * 0.10).toFixed(5));
  
  console.log(`ElevenLabs usage: ${characterCount} characters = $${cost}`);

  return {
    success: true,
    audioData,
    duration: estimatedDuration,
    cost
  };
}

function buildScriptPrompt(context: any): string {
  const date = new Date(context.date).toLocaleDateString('en-US', { 
    weekday: 'long', 
    month: 'long', 
    day: 'numeric' 
  });
  
  const duration = context.dayStartLength || 240;
  const { targetWords } = getTokenLimits(duration);
  const lowerBound = Math.round(targetWords * 0.9);
  const upperBound = Math.round(targetWords * 1.1);
  const storyLimits = getStoryLimits(duration);
  
  // Flatten news; the model will choose relevance based on user.location
  const flattenedNews: any[] = [];
  (context.contentData?.news || []).forEach((source: any) => {
    if (source.data?.articles) {
      source.data.articles.forEach((article: any) => {
        flattenedNews.push({ ...article, sourceName: source.source });
      });
    }
  });

  // Enforce valid, present-day sports items only
  const sportsToday = filterValidSportsItems(context.contentData?.sports || [], context.date).slice(0, storyLimits.sports);

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
    news: flattenAndDedupeNews(context.contentData?.news || []).slice(0, 80),
    sports: sportsToday,
    sportsTeamWhitelist: teamWhitelistFromSports(sportsToday),
    localityHints: localityHints(context.locationData),
    transitions,
    stocks: {
      sources: (context.contentData?.stocks || []).slice(0, storyLimits.stocks),
      focusSymbols: context.stockSymbols || []
    },
    quotePreference: context.quotePreference || null,
    calendarEvents: context.calendarEvents || []
  };

  const styleAddendum = `
PAUSING & FLOW
- Use em dashes (—) for short pauses and ellipses (…) for softer rests.
- Put a blank line between sections to create a natural breath.
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
${styleAddendum}
 - Use 1–2 transitions between sections. Keep ellipses to ≤1 per paragraph and em dashes to ≤2 per paragraph.
 - Stay roughly within the provided per-section word budget (±25%). If a section is omitted, redistribute its budget to News first, then Weather/Calendar.

LENGTH & PACING
  - Target ${targetWords} words total (±10%). Keep between ${lowerBound}–${upperBound} words. Duration: ${Math.round(duration/60)} minutes.
- Adjust depth based on time: shorter = headlines only, longer = more context.
  - If the draft is shorter than ${lowerBound}, expand by adding one concrete, relevant detail in the highest-priority sections (weather, calendar, top news) until within range. If longer than ${upperBound}, tighten by removing the least important detail. No filler.

CONTENT PRIORITIZATION
  - News: Use up to ${storyLimits.news} stories. Choose by local relevance using user.location when available; otherwise pick the most significant stories.
- Sports: ${storyLimits.sports} update(s) max. Only mention teams/matchups present in the sports data for today. If off-season or no fixtures, skip gracefully.
- Stocks: ${storyLimits.stocks} market point(s) max. Prioritize user's focus symbols if provided.
 - Weather: If present, include min/max, rain chance, and wind details for the user's location.
 - Astronomy: If a meteor shower is present, add viewing advice tailored to the user's location (window, direction, light pollution note). Otherwise, omit.
- Calendar: Call out today's top 1–2 items with time ranges and one helpful nudge.

FACT RULES
- Use ONLY facts present in the JSON data.
- If a desired detail is missing, omit it gracefully—do not invent.
- Never mention a team or matchup unless it appears in the sports data for today.
 - Mention ONLY teams present in sportsTeamWhitelist (exact names). If the sports array is empty, omit the sports section entirely.
 - When choosing news, prefer items that mention the user's city/county/adjacent areas; next, state-level; then national; then international.
 - Use 1–2 transitions, choosing from data.transitions.
 - Stocks: Lead with focusSymbols (if present) in one sentence. Add one broader market line only if space allows.

CONTENT ORDER (adapt if sections are missing)
1) One-line greeting using the user's name and day (no headings).
2) Weather (only if include.weather): actionable and hyper-relevant to the user's day.
3) Calendar (if present): call out today's 1–2 most important items with a helpful reminder.
4) News (if include.news): Select from the provided articles. Lead with the most locally relevant (based on user.location) or highest-impact items.
5) Sports (if include.sports): Brief, focused update. Mention major local teams or significant national stories.
6) Stocks (if include.stocks): Market pulse. Call out focusSymbols prominently when present.
7) Quote (if include.quotes): 1 line, then a one-line tie-back to today's vibe.
8) Close with a crisp, motivating line.

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