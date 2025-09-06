# DayStart Deployment Scripts

This directory contains deployment and maintenance scripts for DayStart's Supabase backend.

## Scripts

### deploy-supabase.sh
The main deployment script that:
1. Deploys database migrations and Edge Functions to Supabase
2. Creates a test job to validate the `process_jobs` function
3. Monitors the test job for successful completion
4. Automatically rolls back on failure
5. Generates comprehensive debug logs

**Usage:**
```bash
# Set required environment variables
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_ACCESS_TOKEN="your-access-token"
export SUPABASE_ANON_KEY="your-anon-key"
export SUPABASE_DB_PASSWORD="your-db-password"

# Optional API keys for full functionality
export OPENAI_API_KEY="your-openai-key"
export ELEVENLABS_API_KEY="your-elevenlabs-key"
export WORKER_AUTH_TOKEN="your-worker-token"
export NEWSAPI_KEY="your-newsapi-key"
export GNEWS_API_KEY="your-gnews-key"
export RAPIDAPI_KEY="your-rapidapi-key"

# Run deployment
./deploy-supabase.sh
```

**Features:**
- Validates deployment with a real test job
- 30-second test DayStart generation
- Automatic rollback on failure
- Detailed logging to timestamped log files
- Cleans up test data after validation

### rollback-functions.sh
Git-based rollback script for Edge Functions:
- Finds the previous commit that modified Edge Functions
- Shows what will be reverted
- Creates a backup branch before rollback
- Redeploys the previous version
- Commits the rollback for audit trail

**Usage:**
```bash
# Ensure environment variables are set
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_ACCESS_TOKEN="your-access-token"

# Run rollback
./scripts/rollback-functions.sh
```

### debug-process-jobs.sh
Comprehensive debugging tool for failed jobs:
- Fetches detailed job information
- Collects function logs
- Checks content cache status
- Verifies environment configuration
- Generates timestamped debug reports

**Usage:**
```bash
# Debug a specific job
./scripts/debug-process-jobs.sh <job-id>

# Output: debug-job-<job-id>-<timestamp>.log
```

## Deployment Workflow

1. **Normal Deployment:**
   ```bash
   git commit -m "Update Edge Functions"
   ./deploy-supabase.sh
   ```

2. **If Test Fails:**
   - Script automatically runs debug collection
   - Generates detailed error report
   - Rolls back to previous version
   - Provides debug log for investigation

3. **Manual Rollback:**
   ```bash
   ./scripts/rollback-functions.sh
   ```

4. **Debug Failed Job:**
   ```bash
   ./scripts/debug-process-jobs.sh abc-123-def
   ```

## Test Job Details

The deployment test job:
- Uses receipt ID: `test-deploy-<timestamp>`
- Duration: 30 seconds (minimal)
- Content: News + Quotes only
- Voice: voice1 (default)
- Scheduled for tomorrow at 7 AM

## Environment Variables

Required:
- `SUPABASE_PROJECT_REF`: Your Supabase project reference
- `SUPABASE_ACCESS_TOKEN`: Supabase access token for CLI
- `SUPABASE_ANON_KEY`: Anonymous key for API calls
- `SUPABASE_DB_PASSWORD`: Database password for migrations

Optional (for full functionality):
- `OPENAI_API_KEY`: OpenAI API key for content generation
- `ELEVENLABS_API_KEY`: ElevenLabs API key for TTS
- `WORKER_AUTH_TOKEN`: Authentication token for worker functions
- `NEWSAPI_KEY`: NewsAPI key for news content
- `GNEWS_API_KEY`: GNews API key for additional news
- `RAPIDAPI_KEY`: RapidAPI key for sports/stocks data

## Logs

All scripts generate detailed logs:
- Deployment logs: `deploy-<timestamp>.log`
- Debug reports: `debug-job-<job-id>-<timestamp>.log`

Logs include:
- Timestamp of all operations
- Full command outputs
- API responses
- Error messages
- Function logs from Supabase

## Troubleshooting

1. **Test job creation fails:**
   - Check SUPABASE_ANON_KEY is correct
   - Verify create_job function is deployed
   - Check debug log for API response

2. **Process jobs timeout:**
   - Verify all API keys are set in Supabase secrets
   - Check content cache has fresh data
   - Review function logs for errors

3. **Rollback fails:**
   - Ensure you're in the git repository root
   - Check for uncommitted changes
   - Verify SUPABASE_ACCESS_TOKEN is valid

4. **Debug script errors:**
   - Confirm job ID exists
   - Check network connectivity to Supabase
   - Verify authentication credentials