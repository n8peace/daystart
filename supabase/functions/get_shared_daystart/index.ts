// supabase/functions/get_shared_daystart/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://daystartai.app',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, authorization'
}

serve(async (req) => {
  const startTime = Date.now()
  console.log(`[SHARE] Request started at ${new Date().toISOString()}`)
  
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    console.log('[SHARE] CORS preflight request')
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    const { token } = await req.json()
    console.log(`[SHARE] Received token request: ${token?.substring(0, 4)}...${token?.substring(-2)} (length: ${token?.length})`)
    
    if (!token || typeof token !== 'string' || token.length < 8) {
      console.log(`[SHARE] Invalid token format - type: ${typeof token}, length: ${token?.length}`)
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
    console.log(`[SHARE] Supabase client created`)
    
    // 1. Validate token and get share data (no JOIN needed - all data is local)
    const currentTime = new Date().toISOString()
    console.log(`[SHARE] Querying for token: ${token}, expires_at > ${currentTime}`)
    
    const { data: share, error: shareError } = await supabase
      .from('public_daystart_shares')
      .select(`
        share_id,
        job_id,
        view_count,
        expires_at,
        audio_file_path,
        audio_duration,
        local_date,
        daystart_length,
        preferred_name
      `)
      .eq('share_token', token)
      .gt('expires_at', currentTime)
      .single()
    
    console.log(`[SHARE] Database query result - Error: ${shareError?.message}, Data: ${share ? 'found' : 'null'}`)
    if (share) {
      console.log(`[SHARE] Share details - ID: ${share.share_id}, Job ID: ${share.job_id}, Expires: ${share.expires_at}`)
      console.log(`[SHARE] Audio path: ${share.audio_file_path}`)
      console.log(`[SHARE] Duration: ${share.audio_duration}s, Length: ${share.daystart_length}s`)
    }
    
    if (shareError) {
      console.log(`[SHARE] Database error: ${shareError.message}`)
      return new Response(JSON.stringify({ 
        error: 'Database query failed',
        code: 'DATABASE_ERROR',
        details: shareError.message
      }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    if (!share || !share.audio_file_path) {
      console.log(`[SHARE] Share not found or expired - Share exists: ${!!share}, Audio path: ${share?.audio_file_path}`)
      return new Response(JSON.stringify({ 
        error: 'This briefing has expired or is no longer available',
        code: 'SHARE_EXPIRED' 
      }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 2. Skip file existence check and try to generate URL directly
    // The list() operation might fail with certain path formats or permissions
    console.log(`[SHARE] Attempting to generate signed URL directly for: ${share.audio_file_path}`)
    
    // 3. Generate signed URL for audio
    console.log(`[SHARE] Generating signed URL for: ${share.audio_file_path}`)
    const { data: audioUrl, error: urlError } = await supabase.storage
      .from('daystart-audio')
      .createSignedUrl(share.audio_file_path, 3600) // 1 hour
    
    console.log(`[SHARE] Signed URL result - Error: ${urlError?.message}, URL generated: ${!!audioUrl?.signedUrl}`)
    
    if (urlError || !audioUrl?.signedUrl) {
      console.log(`[SHARE] Failed to create signed URL: ${urlError?.message}`)
      return new Response(JSON.stringify({ 
        error: 'Failed to load audio',
        code: 'URL_GENERATION_FAILED' 
      }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 4. Update view count and analytics
    console.log(`[SHARE] Updating view count from ${share.view_count} to ${share.view_count + 1}`)
    const { error: updateError } = await supabase
      .from('public_daystart_shares')
      .update({ 
        view_count: share.view_count + 1,
        last_accessed_at: new Date().toISOString()
      })
      .eq('share_id', share.share_id)
    
    if (updateError) {
      console.log(`[SHARE] Failed to update view count: ${updateError.message}`)
      // Non-blocking error - continue with response
    }
    
    // 5. Return sanitized data
    const responseData = {
      audio_url: audioUrl.signedUrl,
      duration: share.audio_duration,
      date: share.local_date,
      length_minutes: Math.round(share.daystart_length / 60),
      user_name: share.preferred_name || null
    }
    
    const processingTime = Date.now() - startTime
    console.log(`[SHARE] Success! Processing time: ${processingTime}ms`)
    console.log(`[SHARE] Response data: duration=${responseData.duration}, date=${responseData.date}, length=${responseData.length_minutes}min`)
    
    return new Response(JSON.stringify(responseData), {
      status: 200,
      headers: { 
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'private, max-age=300' // 5 min cache
      }
    })
    
  } catch (error) {
    const processingTime = Date.now() - startTime
    console.log(`[SHARE] ERROR after ${processingTime}ms: ${error.message}`)
    console.log(`[SHARE] Error stack: ${error.stack}`)
    
    return new Response(JSON.stringify({ 
      error: 'Something went wrong',
      code: 'INTERNAL_ERROR',
      details: error.message
    }), { 
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})