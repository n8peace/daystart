// supabase/functions/get_shared_daystart/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://daystartai.app',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type'
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    const { token } = await req.json()
    
    if (!token || typeof token !== 'string' || token.length < 8) {
      return new Response(JSON.stringify({ 
        error: 'Invalid share link',
        code: 'INVALID_TOKEN' 
      }), { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!
    )
    
    // 1. Validate token and get job data
    const { data: share } = await supabase
      .from('public_daystart_shares')
      .select(`
        share_id,
        job_id,
        view_count,
        jobs (
          audio_file_path,
          audio_duration,
          local_date,
          script_content,
          daystart_length,
          preferred_name
        )
      `)
      .eq('share_token', token)
      .gt('expires_at', new Date().toISOString())
      .single()
    
    if (!share || !share.jobs) {
      return new Response(JSON.stringify({ 
        error: 'This briefing has expired or is no longer available',
        code: 'SHARE_EXPIRED' 
      }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 2. Verify audio file exists
    const audioFileName = share.jobs.audio_file_path.split('/').pop()
    const audioPath = share.jobs.audio_file_path.split('/').slice(0, -1).join('/')
    
    const { data: files } = await supabase.storage
      .from('daystart-audio')
      .list(audioPath)
    
    if (!files?.find(f => f.name === audioFileName)) {
      console.error(`Audio file not found: ${share.jobs.audio_file_path}`)
      return new Response(JSON.stringify({ 
        error: 'Audio file no longer available',
        code: 'AUDIO_NOT_FOUND' 
      }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 3. Generate signed URL for audio
    const { data: audioUrl, error: urlError } = await supabase.storage
      .from('daystart-audio')
      .createSignedUrl(share.jobs.audio_file_path, 3600) // 1 hour
    
    if (urlError || !audioUrl?.signedUrl) {
      console.error('Failed to create signed URL:', urlError)
      return new Response(JSON.stringify({ 
        error: 'Failed to load audio',
        code: 'URL_GENERATION_FAILED' 
      }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 4. Update view count and analytics
    await supabase
      .from('public_daystart_shares')
      .update({ 
        view_count: share.view_count + 1,
        last_accessed_at: new Date().toISOString()
      })
      .eq('share_id', share.share_id)
    
    // 5. Return sanitized data
    return new Response(JSON.stringify({
      audio_url: audioUrl.signedUrl,
      duration: share.jobs.audio_duration,
      date: share.jobs.local_date,
      length_minutes: Math.round(share.jobs.daystart_length / 60),
      // Optional: Include name for personalized greeting
      user_name: share.jobs.preferred_name || null
    }), {
      status: 200,
      headers: { 
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'private, max-age=300' // 5 min cache
      }
    })
    
  } catch (error) {
    console.error('Share retrieval error:', error)
    return new Response(JSON.stringify({ 
      error: 'Something went wrong',
      code: 'INTERNAL_ERROR' 
    }), { 
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})