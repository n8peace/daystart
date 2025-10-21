// supabase/functions/create_share/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// URL-safe token generation
const generateShareToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
    .substring(0, 12) // Short, URL-safe token
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // iOS app needs this
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-client-info, x-app-version'
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    const { 
      job_id, 
      duration_hours = 48,
      share_source = 'unknown', // 'completion_screen', 'audio_player', 'manual'
      // Public data fields from iOS
      audio_file_path,
      audio_duration,
      local_date,
      daystart_length,
      preferred_name
    } = await req.json()
    
    // Extract user ID from header
    const userId = req.headers.get('x-client-info')
    if (!userId) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { 
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )
    
    // Verify job belongs to user and has audio
    const { data: job } = await supabase
      .from('jobs')
      .select('user_id, audio_file_path, status')
      .eq('job_id', job_id)
      .eq('user_id', userId)
      .single()
    
    if (!job) {
      return new Response(JSON.stringify({ error: 'Job not found' }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    if (job.status !== 'ready' || !job.audio_file_path) {
      return new Response(JSON.stringify({ error: 'Audio not ready' }), { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Validate that iOS provided the required public data
    if (!audio_file_path || !audio_duration || !local_date || !daystart_length) {
      return new Response(JSON.stringify({ error: 'Missing required share data' }), { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Check rate limiting - max 5 shares per job
    const { count } = await supabase
      .from('public_daystart_shares')
      .select('*', { count: 'exact', head: true })
      .eq('job_id', job_id)
    
    if (count && count >= 5) {
      return new Response(JSON.stringify({ 
        error: 'Share limit reached for this briefing',
        code: 'RATE_LIMIT_EXCEEDED' 
      }), { 
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Check daily user limit (optional)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    
    const { count: dailyCount } = await supabase
      .from('public_daystart_shares')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .gte('created_at', today.toISOString())
    
    if (dailyCount && dailyCount >= 10) {
      return new Response(JSON.stringify({ 
        error: 'Daily share limit reached',
        code: 'DAILY_LIMIT_EXCEEDED' 
      }), { 
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Generate token and expiry
    const share_token = generateShareToken()
    const expires_at = new Date()
    expires_at.setHours(expires_at.getHours() + duration_hours)
    
    // Create share record with public data
    const { data: share, error } = await supabase
      .from('public_daystart_shares')
      .insert({
        job_id,
        user_id: userId,
        share_token,
        expires_at: expires_at.toISOString(),
        share_source,
        shares_per_job: (count || 0) + 1,
        share_metadata: {
          app_version: req.headers.get('x-app-version') || 'unknown',
          created_from: 'ios_app'
        },
        // Store public data locally to avoid JOIN on jobs table
        audio_file_path,
        audio_duration,
        local_date,
        daystart_length,
        preferred_name
      })
      .select()
      .single()
    
    if (error) {
      console.error('Share creation error:', error)
      return new Response(JSON.stringify({ error: 'Failed to create share' }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    return new Response(JSON.stringify({
      share_url: `https://daystartai.app/shared/${share_token}`,
      token: share_token,
      expires_at: expires_at.toISOString(),
      share_id: share.share_id
    }), {
      status: 201,
      headers: { 
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
      }
    })
    
  } catch (error) {
    console.error('Share creation error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), { 
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})