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

// Prioritize news by geography and impact
function prioritizeNews(newsData: any[]): any[] {
  if (!newsData || newsData.length === 0) return [];
  
  // Flatten all articles with source info
  const allArticles: any[] = [];
  newsData.forEach(source => {
    if (source.data?.articles) {
      source.data.articles.forEach((article: any) => {
        allArticles.push({
          ...article,
          sourceName: source.source,
          priority: calculateNewsPriority(article, source.source)
        });
      });
    }
  });
  
  // Sort by priority (higher = more important)
  return allArticles.sort((a, b) => b.priority - a.priority);
}

// Calculate news priority score
function calculateNewsPriority(article: any, source: string): number {
  let score = 0;
  const title = (article.title || '').toLowerCase();
  const content = (article.description || article.content || '').toLowerCase();
  const text = title + ' ' + content;
  
  // Geographic relevance (highest priority)
  if (containsLocalKeywords(text)) score += 100;
  else if (containsRegionalKeywords(text)) score += 80;
  else if (containsNationalKeywords(text)) score += 60;
  else score += 40; // international baseline
  
  // Breaking/urgent news boost
  if (isBreakingNews(text)) score += 50;
  
  // High-impact story boost
  if (isHighImpactStory(text)) score += 30;
  
  // Recency boost (if available)
  if (article.publishedAt) {
    const hoursOld = (Date.now() - new Date(article.publishedAt).getTime()) / (1000 * 60 * 60);
    if (hoursOld < 2) score += 20;
    else if (hoursOld < 6) score += 10;
  }
  
  return score;
}

function containsLocalKeywords(text: string): boolean {
  const localKeywords = [
    'san francisco', 'sf', 'bay area', 'oakland', 'san jose', 'silicon valley',
    'california', 'ca', 'palo alto', 'mountain view', 'berkeley', 'marin'
  ];
  return localKeywords.some(keyword => text.includes(keyword));
}

function containsRegionalKeywords(text: string): boolean {
  const regionalKeywords = [
    'california', 'west coast', 'pacific', 'los angeles', 'san diego',
    'sacramento', 'fresno', 'nevada', 'oregon', 'washington'
  ];
  return regionalKeywords.some(keyword => text.includes(keyword));
}

function containsNationalKeywords(text: string): boolean {
  const nationalKeywords = [
    'united states', 'america', 'us', 'federal', 'congress', 'senate',
    'white house', 'washington dc', 'supreme court', 'fda', 'cdc'
  ];
  return nationalKeywords.some(keyword => text.includes(keyword));
}

function isBreakingNews(text: string): boolean {
  const breakingKeywords = [
    'breaking', 'urgent', 'developing', 'just in', 'alert', 'emergency',
    'major', 'massive', 'huge', 'crisis', 'disaster', 'accident'
  ];
  return breakingKeywords.some(keyword => text.includes(keyword));
}

function isHighImpactStory(text: string): boolean {
  const impactKeywords = [
    'economy', 'market crash', 'election', 'earthquake', 'fire', 'storm',
    'security', 'data breach', 'layoffs', 'merger', 'acquisition', 'ipo',
    'inflation', 'recession', 'rate', 'tech', 'ai', 'climate'
  ];
  return impactKeywords.some(keyword => text.includes(keyword));
}

// Sanitize script output for TTS
function sanitizeForTTS(raw: string): string {
  let s = raw.trim();

  // Remove obvious stage directions / markdown
  s = s.replace(/\[.*?\]/g, '');       // [INTRO MUSIC], [OUTRO], etc.
  s = s.replace(/[*_#`>]+/g, '');      // markdown artifacts
  s = s.replace(/\s{2,}/g, ' ');       // collapse whitespace

  // Remove label-y lines (e.g., "Weather:", "News:")
  s = s.replace(/^(weather|news|sports|stocks|quote|calendar)\s*:\s*/gim, '');
  
  // Remove any "Good morning" duplicates if model adds extras
  s = s.replace(/^(good morning[^.]*\.\s*){2,}/gi, (match, group) => group);

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
      return createResponse(false, 0, 0, 'Only POST method allowed', request_id, 405);
    }

    // Basic auth check (can be enhanced with proper API keys)
    const authHeader = req.headers.get('authorization');
    const expectedToken = Deno.env.get('WORKER_AUTH_TOKEN');
    
    if (!authHeader || authHeader !== `Bearer ${expectedToken}`) {
      return createResponse(false, 0, 0, 'Unauthorized', request_id, 401);
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
    return createResponse(false, 0, 0, 'Internal worker error', request_id, 500);
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
  const totalCost = Number((scriptResult.cost + audioResult.cost).toFixed(5));

  // Mark job as complete with all costs
  await supabase
    .from('jobs')
    .update({
      status: 'ready',
      audio_file_path: audioPath,
      audio_duration: audioResult.duration,
      transcript: scriptResult.content,
      script_cost: scriptResult.cost,
      tts_cost: audioResult.cost,
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
  const contentTypes = [];
  if (job.include_news) contentTypes.push('news');
  if (job.include_stocks) contentTypes.push('stocks');
  if (job.include_sports) contentTypes.push('sports');

  let contentData = {};
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
  const duration = context.dayStartLength || 90;
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

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openaiApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4', // High-quality script generation
      messages: [fewShotExample, systemMessage, userMessage],
      max_tokens: maxTokens,    // Dynamic based on user's duration
      temperature: 0.5,         // tighter adherence
      top_p: 1,
    }),
  });

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
  const script = sanitizeForTTS(rawScript);
  
  if (!script) {
    throw new Error('Script was empty after sanitization');
  }

  // Calculate cost based on token usage
  const usage = data.usage;
  const inputCost = (usage.prompt_tokens / 1_000_000) * 30.00;  // $30.00 per 1M input tokens
  const outputCost = (usage.completion_tokens / 1_000_000) * 60.00;  // $60.00 per 1M output tokens
  const totalCost = Number((inputCost + outputCost).toFixed(5));

  console.log(`[DEBUG] OpenAI usage: ${usage.prompt_tokens} input + ${usage.completion_tokens} output tokens = $${totalCost}`);
  console.log(`[DEBUG] Script length: ${script.split(' ').length} words (sanitized from ${rawScript.split(' ').length} words)`);
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

  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
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
  });

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
  
  const duration = context.dayStartLength || 90;
  const { targetWords } = getTokenLimits(duration);
  const lowerBound = Math.round(targetWords * 0.9);
  const upperBound = Math.round(targetWords * 1.1);
  const storyLimits = getStoryLimits(duration);
  
  // Prioritize and limit news based on duration
  const prioritizedNews = prioritizeNews(context.contentData?.news || []);
  const topNews = prioritizedNews.slice(0, storyLimits.news);

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
    weather: context.weatherData || null,
    news: topNews,
    sports: (context.contentData?.sports || []).slice(0, storyLimits.sports),
    stocks: {
      sources: (context.contentData?.stocks || []).slice(0, storyLimits.stocks),
      focusSymbols: context.stockSymbols || []
    },
    quotePreference: context.quotePreference || null,
    calendarEvents: context.calendarEvents || []
  };

  return `
You are a professional morning briefing writer for a TTS wake-up app. Your job: write a concise, warm, highly-personalized script that sounds natural when spoken aloud.

STYLE
- Warm, conversational, confident; no filler.
- Use short sentences and varied rhythm.
- Prefer specifics over generalities. If a section has no data, gracefully skip it.
- Sprinkle one light, human moment max (a nudge, not a joke barrage).

LENGTH & PACING
  - Target ${targetWords} words total (±10%). Keep between ${lowerBound}–${upperBound} words. Duration: ${Math.round(duration/60)} minutes.
- Adjust depth based on time: shorter = headlines only, longer = more context.
  - If the draft is shorter than ${lowerBound}, expand by adding one concrete, relevant detail in the highest-priority sections (weather, calendar, top news) until within range. If longer than ${upperBound}, tighten by removing the least important detail. No filler.

CONTENT PRIORITIZATION
- News: Use exactly ${storyLimits.news} stories max. The provided news is pre-sorted by relevance (local > regional > national > international, with breaking news boosted).
- Sports: ${storyLimits.sports} update(s) max. Focus on local/regional teams when possible.
- Stocks: ${storyLimits.stocks} market point(s) max. Prioritize user's focus symbols if provided.

CONTENT ORDER (adapt if sections are missing)
1) One-line greeting using the user's name and day (no headings).
2) Weather (only if include.weather): actionable and hyper-relevant to the user's day.
3) Calendar (if present): call out today's 1–2 most important items with a helpful reminder.
4) News (if include.news): Use the prioritized news provided. Lead with most relevant (local/breaking first).
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