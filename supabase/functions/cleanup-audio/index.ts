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

  let logId: number | null = null

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

    logId = logEntry.id

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

    // Clean up test-deploy files and folders
    try {
      console.log(`🧪 Starting test-deploy cleanup...`)
      
      // Get all folders at root level
      const { data: folders, error: listError } = await supabase.storage
        .from('daystart-audio')
        .list('', { 
          limit: 1000,
          offset: 0
        })

      if (listError) {
        console.error('Failed to list storage folders:', listError)
        result.errors.push(`Test-deploy cleanup failed: ${listError.message}`)
      } else {
        // Filter for test-deploy folders
        const testDeployFolders = folders?.filter(item => 
          item.name.startsWith('test-deploy-')
        ) || []

        console.log(`Found ${testDeployFolders.length} test-deploy folders to clean up`)

        let testDeployFilesDeleted = 0
        let testDeployFoldersDeleted = 0

        // Delete each test-deploy folder and its contents
        for (const folder of testDeployFolders) {
          try {
            // List all contents in the test-deploy folder
            const { data: datefolders } = await supabase.storage
              .from('daystart-audio')
              .list(folder.name, { limit: 1000 })

            // For each date folder within the test-deploy folder
            for (const datefolder of datefolders || []) {
              const datePath = `${folder.name}/${datefolder.name}`
              
              // List files in the date folder
              const { data: files } = await supabase.storage
                .from('daystart-audio')
                .list(datePath, { limit: 1000 })

              if (files && files.length > 0) {
                // Construct full paths for deletion
                const filePaths = files.map(file => `${datePath}/${file.name}`)
                
                // Delete all files
                const { error: deleteError } = await supabase.storage
                  .from('daystart-audio')
                  .remove(filePaths)

                if (deleteError) {
                  console.error(`Failed to delete files in ${datePath}:`, deleteError)
                  result.errors.push(`Test-deploy deletion failed for ${datePath}: ${deleteError.message}`)
                } else {
                  testDeployFilesDeleted += files.length
                  console.log(`Deleted ${files.length} files from ${datePath}`)
                }
              }
            }

            testDeployFoldersDeleted++
            console.log(`Cleaned up test-deploy folder: ${folder.name}`)

          } catch (folderError) {
            console.error(`Error processing test-deploy folder ${folder.name}:`, folderError)
            result.errors.push(`Test-deploy folder ${folder.name}: ${folderError.message}`)
          }
        }

        // Clean up test-deploy job records from database
        const { data: deletedJobs, error: dbError } = await supabase
          .from('jobs')
          .delete()
          .like('user_id', 'test-deploy-%')
          .select('job_id')

        const testDeployJobsDeleted = deletedJobs?.length || 0

        if (dbError) {
          console.error('Failed to delete test-deploy job records:', dbError)
          result.errors.push(`Test-deploy DB cleanup failed: ${dbError.message}`)
        }

        console.log(`✅ Test-deploy cleanup completed: ${testDeployFoldersDeleted} folders, ${testDeployFilesDeleted} files, ${testDeployJobsDeleted} job records`)
        
        // Update log entry with test-deploy cleanup stats
        if (logId) {
          await supabase
            .from('audio_cleanup_log')
            .update({
              error_details: result.errors.length > 0 ? 
                { 
                  errors: result.errors,
                  test_deploy_folders_deleted: testDeployFoldersDeleted,
                  test_deploy_files_deleted: testDeployFilesDeleted,
                  test_deploy_jobs_deleted: testDeployJobsDeleted
                } : 
                {
                  test_deploy_folders_deleted: testDeployFoldersDeleted,
                  test_deploy_files_deleted: testDeployFilesDeleted,
                  test_deploy_jobs_deleted: testDeployJobsDeleted
                }
            })
            .eq('id', logId)
        }
      }
    } catch (testDeployError) {
      console.error('Test-deploy cleanup failed:', testDeployError)
      result.errors.push(`Test-deploy cleanup error: ${testDeployError.message}`)
    }

  } catch (error) {
    console.error(`❌ Audio cleanup async processing failed for request ${request_id}:`, error)
    result.errors.push(error.message)
  }
}