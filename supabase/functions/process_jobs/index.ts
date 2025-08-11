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
    console.log(message);

    return createResponse(true, processedCount, failedCount, message, request_id);

  } catch (error) {
    console.error('Worker error:', error);
    return createResponse(false, 0, 0, 'Internal worker error', request_id, 500);
  }
});

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

  // Generate script content
  const scriptContent = await generateScript(job);
  
  // Update job with script
  await supabase
    .from('jobs')
    .update({
      script_content: scriptContent,
      updated_at: new Date().toISOString()
    })
    .eq('job_id', jobId);

  // Generate audio
  const audioResult = await generateAudio(scriptContent, job);
  
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

  // Mark job as complete
  await supabase
    .from('jobs')
    .update({
      status: 'ready',
      audio_file_path: audioPath,
      audio_duration: audioResult.duration,
      transcript: scriptContent,
      completed_at: new Date().toISOString(),
      worker_id: null,
      lease_until: null,
      updated_at: new Date().toISOString()
    })
    .eq('job_id', jobId);

  console.log(`Completed job ${jobId} - audio saved to ${audioPath}`);
  return true;
}

async function generateScript(job: any): Promise<string> {
  const openaiApiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openaiApiKey) {
    throw new Error('OpenAI API key not configured');
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
    locationData: job.location_data,
    weatherData: job.weather_data,
    calendarEvents: job.calendar_events
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

  return script.trim();
}

async function generateAudio(script: string, job: any): Promise<{success: boolean, audioData?: Uint8Array, duration?: number, error?: string}> {
  const elevenlabsApiKey = Deno.env.get('ELEVENLABS_API_KEY');
  if (!elevenlabsApiKey) {
    throw new Error('ElevenLabs API key not configured');
  }

  // Map voice option to ElevenLabs voice ID
  const voiceMap: Record<string, string> = {
    'voice1': 'pNInz6obpgDQGcFmaJgB', // Adam
    'voice2': '21m00Tcm4TlvDq8ikWAM', // Rachel  
    'voice3': 'ErXwobaYiN019PkySvjV', // Antoni
  };

  const voiceId = voiceMap[job.voice_option] || voiceMap['voice1'];

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

  return {
    success: true,
    audioData,
    duration: estimatedDuration
  };
}

function buildScriptPrompt(context: any): string {
  const date = new Date(context.date).toLocaleDateString('en-US', { 
    weekday: 'long', 
    month: 'long', 
    day: 'numeric' 
  });

  let prompt = `Create a personalized morning briefing script for ${context.preferredName} for ${date}.\n\n`;
  
  prompt += `Requirements:
- 2-3 minutes when spoken naturally
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
    prompt += `- News: 2-3 top headlines (focus on business/tech if possible)\n`;
  }
  
  if (context.includeSports) {
    prompt += `- Sports: Brief update on major sports news\n`;
  }
  
  if (context.includeStocks && context.stockSymbols?.length > 0) {
    prompt += `- Stocks: Brief update on these symbols: ${context.stockSymbols.join(', ')}\n`;
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