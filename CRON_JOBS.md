# DayStart Cron Jobs Documentation

This document outlines all scheduled tasks (cron jobs) used by the DayStart application. All cron jobs are managed through external services (e.g., cron-job.org) and call Supabase Edge Functions.

## Overview

| Job Name | Schedule | Frequency | Purpose |
|----------|----------|-----------|---------|
| Process Jobs | `*/1 * * * *` | Every 1 minute | Process audio generation queue |
| Refresh Content | `0 * * * *` | Every hour | Refresh news, stocks, sports cache |
| Cleanup Audio | `5 1 * * *` | Daily at 1:05 AM UTC | Delete old audio files |
| Healthcheck | `5 2 * * *` | Daily at 2:05 AM UTC | Run system health checks and email report |

## 1. Process Jobs

### Purpose
Processes the job queue for audio generation. Picks up queued jobs, generates audio content, and updates job status.

### Configuration
- **URL**: `https://[PROJECT_REF].supabase.co/functions/v1/process_jobs`
- **Method**: POST
- **Schedule**: `*/1 * * * *` (every minute)
- **Headers**: 
  ```
  Authorization: Bearer [WORKER_AUTH_TOKEN]
  ```

### Monitoring
- Check `jobs` table for stuck jobs (status='processing' for >10 minutes)
- Monitor Edge Function logs in Supabase Dashboard
- Alert if queue depth exceeds 100 jobs

### Notes
- Processes up to 5 jobs per execution
- Implements lease-based locking to prevent duplicate processing
- Welcome DayStarts are prioritized

## 2. Refresh Content

### Purpose
Refreshes cached content from external APIs (news, stocks, sports) to ensure fresh data for DayStart generation.

### Configuration
- **URL**: `https://[PROJECT_REF].supabase.co/functions/v1/refresh_content`
- **Method**: POST
- **Schedule**: `0 * * * *` (top of every hour)
- **Headers**:
  ```
  Authorization: Bearer [WORKER_AUTH_TOKEN]
  ```

### Monitoring
- Check `content_cache` table for recent entries
- Monitor API rate limits in Edge Function logs
- Verify content freshness (should be <2 hours old)

### Notes
- Caches content for 12 hours with graceful fallback
- Automatically cleans up expired cache entries
- Respects API rate limits for external services

## 3. Cleanup Audio

### Purpose
Deletes audio files from storage that are older than 10 days to manage storage costs and comply with data retention policies.

### Configuration
- **URL**: `https://[PROJECT_REF].supabase.co/functions/v1/cleanup-audio`
- **Method**: POST
- **Schedule**: `5 1 * * *` (daily at 1:05 AM UTC)
- **Headers**:
  ```
  Authorization: Bearer [WORKER_AUTH_TOKEN]
  ```

### Monitoring
- Check `audio_cleanup_log` table for execution history
- Monitor storage usage in Supabase Dashboard
- Alert if cleanup fails for 3 consecutive days

### Security Notes
- This job requires SERVICE_ROLE_KEY for storage access
- Store the key securely in cron service
- Consider IP whitelisting if supported

### Notes
- Deletes files older than 10 days by default
- Prevents running more than once per 20 hours
- Logs all operations for audit trail

## 4. Healthcheck

### Purpose
Runs a comprehensive application healthcheck across DB, cache freshness, job queue, storage, internal endpoints, and error logs, then emails a summary via Resend.

### Configuration
- **URL**: `https://[PROJECT_REF].supabase.co/functions/v1/healthcheck`
- **Method**: POST
- **Schedule**: `5 2 * * *` (daily at 2:05 AM UTC)
- **Headers**:
  ```
  Authorization: Bearer [WORKER_AUTH_TOKEN]
  Content-Type: application/json
  ```

### Monitoring
- Check `request_logs` for `/healthcheck` entries
- Verify healthcheck email is received daily

### Notes
- The function returns 200 immediately and executes asynchronously
- Ensure Resend env vars are configured in Supabase secrets

## Troubleshooting

### Common Issues

1. **Job not running**
   - Verify cron service is active
   - Check authorization headers are correct
   - Ensure Supabase project is not paused

2. **Authentication errors**
   - Regenerate and update API keys if needed
   - Verify correct key type (anon vs service role)

3. **Performance issues**
   - Check Supabase Edge Function logs
   - Monitor execution time trends
   - Consider adjusting batch sizes

### Useful Queries

```sql
-- Check recent job processing
SELECT status, COUNT(*), MAX(updated_at) as last_update
FROM jobs
GROUP BY status;

-- View content cache status
SELECT * FROM get_content_stats();

-- Check cleanup history
SELECT * FROM audio_cleanup_log
ORDER BY started_at DESC
LIMIT 10;

-- Get cleanup statistics
SELECT * FROM get_audio_cleanup_stats();
```

## Cost Considerations

- **Process Jobs**: ~43,200 invocations/month
- **Refresh Content**: ~720 invocations/month  
- **Cleanup Audio**: ~30 invocations/month

Total: ~44,000 Edge Function invocations/month

## Future Improvements

1. Consider moving to Supabase native cron when available
2. Add webhook notifications for failures
3. Implement more granular scheduling based on usage patterns
4. Add automated backup before cleanup operations