import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// This is a background job processor that can be triggered by:
// 1. Cron job every 5 minutes
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
  const audioPath = `${job.user_id}/${job.local_date}/${jobId}.mp3`;
  
  const { error: uploadError } = await supabase.storage
    .from('daystart-audio')
    .upload(audioPath, audioResult.audioData, {
      contentType: 'audio/mpeg',
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
    const { data: freshContent } = await supabase.rpc('get_fresh_content', {
      requested_types: contentTypes
    });
    contentData = freshContent || {};
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

  // Create prompt for GPT-4
  const prompt = buildScriptPrompt(context);

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openaiApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini', // Cost-effective for script generation
      messages: [
        {
          role: 'system',
          content: 'You are a professional morning briefing writer. Create engaging, personalized audio scripts for busy professionals.'
        },
        {
          role: 'user',
          content: prompt
        }
      ],
      max_tokens: 1500,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status}`);
  }

  const data = await response.json();
  const script = data.choices?.[0]?.message?.content;

  if (!script) {
    throw new Error('No script generated by OpenAI');
  }

  // Calculate cost based on token usage
  const usage = data.usage;
  const inputCost = (usage.prompt_tokens / 1_000_000) * 0.15;  // $0.15 per 1M input tokens
  const outputCost = (usage.completion_tokens / 1_000_000) * 0.60;  // $0.60 per 1M output tokens
  const totalCost = Number((inputCost + outputCost).toFixed(5));

  console.log(`OpenAI usage: ${usage.prompt_tokens} input + ${usage.completion_tokens} output tokens = $${totalCost}`);

  return {
    content: script.trim(),
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
      'Accept': 'audio/mpeg',
      'Content-Type': 'application/json',
      'xi-api-key': elevenlabsApiKey,
    },
    body: JSON.stringify({
      text: script,
      model_id: 'eleven_monolingual_v1',
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.5,
        style: 0.0,
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

  let prompt = `Create a personalized morning briefing script for ${context.preferredName} for ${date}.\n\n`;
  
  const durationMinutes = Math.round(context.dayStartLength / 60);
  
  prompt += `Requirements:
- ${durationMinutes} minutes when spoken naturally
- Warm, conversational tone
- Start with a personal greeting
- Include relevant sections based on preferences
- End with motivation for the day
- Write for audio delivery (no visual elements)\n\n`;

  prompt += `Include these sections if requested:\n`;
  
  if (context.includeWeather) {
    prompt += `- Weather: ${context.weatherData ? JSON.stringify(context.weatherData) : 'Current weather and forecast'}\n`;
  }
  
  if (context.includeNews) {
    const newsContent = context.contentData?.news;
    if (newsContent && newsContent.length > 0) {
      prompt += `- News: Use these current headlines and summarize the top 2-3:\n`;
      newsContent.forEach((source: any, index: number) => {
        prompt += `  ${source.source.toUpperCase()}: ${JSON.stringify(source.data.articles?.slice(0, 3))}\n`;
      });
    } else {
      prompt += `- News: General news summary (content cache unavailable)\n`;
    }
  }
  
  if (context.includeSports) {
    const sportsContent = context.contentData?.sports;
    if (sportsContent && sportsContent.length > 0) {
      prompt += `- Sports: Use this current sports data:\n`;
      sportsContent.forEach((source: any) => {
        prompt += `  ${source.source.toUpperCase()}: ${JSON.stringify(source.data)}\n`;
      });
    } else {
      prompt += `- Sports: General sports update (content cache unavailable)\n`;
    }
  }
  
  if (context.includeStocks) {
    const stocksContent = context.contentData?.stocks;
    if (stocksContent && stocksContent.length > 0) {
      prompt += `- Stocks: Use this current market data:\n`;
      stocksContent.forEach((source: any) => {
        prompt += `  ${source.source.toUpperCase()}: ${JSON.stringify(source.data)}\n`;
      });
      if (context.stockSymbols?.length > 0) {
        prompt += `  Focus on these symbols if available: ${context.stockSymbols.join(', ')}\n`;
      }
    } else if (context.stockSymbols?.length > 0) {
      prompt += `- Stocks: Brief update on these symbols: ${context.stockSymbols.join(', ')} (live data unavailable)\n`;
    } else {
      prompt += `- Stocks: General market update (content cache unavailable)\n`;
    }
  }
  
  if (context.includeQuotes) {
    prompt += `- Quote: ${context.quotePreference} quote to inspire the day\n`;
  }

  if (context.calendarEvents?.length > 0) {
    prompt += `- Calendar: Mention these upcoming events: ${JSON.stringify(context.calendarEvents)}\n`;
  }

  prompt += `\nLocation context: ${context.locationData ? JSON.stringify(context.locationData) : 'General'}\n`;
  prompt += `Timezone: ${context.timezone}\n\n`;
  prompt += `Write the complete script ready for text-to-speech conversion.`;

  return prompt;
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