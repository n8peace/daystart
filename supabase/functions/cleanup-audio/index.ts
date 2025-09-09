import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

interface CleanupResult {
  success: boolean
  started_at: string
  completed_at?: string
  files_found: number
  files_deleted: number
  files_failed: number
  errors: string[]
  runtime_seconds?: number
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const request_id = crypto.randomUUID()

  try {
    // Verify authorization - service role key only
    const authHeader = req.headers.get('authorization')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !supabaseServiceKey || authHeader !== `Bearer ${supabaseServiceKey}`) {
      throw new Error('Unauthorized')
    }

    // Check if cleanup should run (prevents too frequent runs)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      }
    })

    const { data: shouldRun, error: checkError } = await supabase
      .rpc('should_run_audio_cleanup')
    
    if (checkError) {
      throw new Error(`Failed to check cleanup status: ${checkError.message}`)
    }

    if (!shouldRun) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Cleanup skipped - ran too recently',
          last_run_within_hours: 20,
          request_id
        }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200
        }
      )
    }

    console.log(`🧹 Audio cleanup accepted with request_id: ${request_id}`)
    
    // Start async processing without waiting
    cleanupAudioAsync(request_id).catch(error => {
      console.error('Async audio cleanup error:', error)
    })

    // Return immediate success response
    return new Response(
      JSON.stringify({
        success: true,
        message: 'Audio cleanup started',
        request_id,
        started_at: new Date().toISOString()
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    )

  } catch (error) {
    console.error('❌ Audio cleanup startup failed:', error)
    
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        message: 'Audio cleanup failed to start',
        request_id
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    )
  }
})

async function cleanupAudioAsync(request_id: string): Promise<void> {
  const startTime = Date.now()
  const result: CleanupResult = {
    success: false,
    started_at: new Date().toISOString(),
    files_found: 0,
    files_deleted: 0,
    files_failed: 0,
    errors: []
  }

  try {
    // Create Supabase client with service role for full access
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      }
    })

    console.log(`🧹 Starting audio cleanup for request ${request_id}`)

    // Create cleanup log entry
    const { data: logEntry, error: logError } = await supabase
      .from('audio_cleanup_log')
      .insert({
        cleanup_type: 'scheduled',
        initiated_by: 'cron'
      })
      .select()
      .single()

    if (logError) {
      throw new Error(`Failed to create log entry: ${logError.message}`)
    }

    const logId = logEntry.id

    // Get list of files to cleanup (default 10 days)
    const daysToKeep = 10
    const { data: filesToDelete, error: filesError } = await supabase
      .rpc('get_audio_files_to_cleanup', { days_to_keep: daysToKeep })

    if (filesError) {
      throw new Error(`Failed to get files list: ${filesError.message}`)
    }

    result.files_found = filesToDelete?.length || 0
    console.log(`Found ${result.files_found} audio files older than ${daysToKeep} days`)

    if (result.files_found === 0) {
      // Update log entry with results
      await supabase
        .from('audio_cleanup_log')
        .update({
          completed_at: new Date().toISOString(),
          files_found: 0,
          files_deleted: 0,
          files_failed: 0,
          runtime_seconds: (Date.now() - startTime) / 1000
        })
        .eq('id', logId)

      result.success = true
      result.completed_at = new Date().toISOString()
      result.runtime_seconds = (Date.now() - startTime) / 1000

      console.log(`✅ Audio cleanup completed for request ${request_id}: No files to delete`)
      return
    }

    // Delete files from storage in batches
    const batchSize = 50
    const deletedJobIds: string[] = []
    
    for (let i = 0; i < filesToDelete.length; i += batchSize) {
      const batch = filesToDelete.slice(i, i + batchSize)
      
      for (const file of batch) {
        try {
          // Delete from storage bucket
          const { error: deleteError } = await supabase.storage
            .from('daystart-audio')
            .remove([file.audio_file_path])

          if (deleteError) {
            console.error(`Failed to delete ${file.audio_file_path}: ${deleteError.message}`)
            result.files_failed++
            result.errors.push(`${file.audio_file_path}: ${deleteError.message}`)
          } else {
            result.files_deleted++
            deletedJobIds.push(file.job_id)
            console.log(`Deleted: ${file.audio_file_path} (${file.days_old} days old)`)
          }
        } catch (error) {
          console.error(`Error deleting ${file.audio_file_path}:`, error)
          result.files_failed++
          result.errors.push(`${file.audio_file_path}: ${error.message}`)
        }
      }

      // Update database records for successfully deleted files
      if (deletedJobIds.length > 0) {
        const { error: updateError } = await supabase
          .rpc('mark_audio_files_deleted', { job_ids: deletedJobIds })

        if (updateError) {
          console.error('Failed to update database records:', updateError)
          result.errors.push(`Database update failed: ${updateError.message}`)
        }
      }
    }

    // Update log entry with results
    const runtime = (Date.now() - startTime) / 1000
    await supabase
      .from('audio_cleanup_log')
      .update({
        completed_at: new Date().toISOString(),
        files_found: result.files_found,
        files_deleted: result.files_deleted,
        files_failed: result.files_failed,
        error_details: result.errors.length > 0 ? { errors: result.errors } : null,
        runtime_seconds: runtime
      })
      .eq('id', logId)

    result.success = true
    result.completed_at = new Date().toISOString()
    result.runtime_seconds = runtime

    console.log(`✅ Audio cleanup completed for request ${request_id}: ${result.files_deleted} deleted, ${result.files_failed} failed`)

  } catch (error) {
    console.error(`❌ Audio cleanup async processing failed for request ${request_id}:`, error)
    result.errors.push(error.message)
  }
}