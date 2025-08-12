# Cron Schedule Update Instructions

## Overview
This update changes the `process_jobs` cron schedule from running every 5 minutes to every 1 minute, reducing the maximum wait time for welcome DayStarts from 5 minutes to 1 minute.

## Changes Made

### 1. Database Migration
- Created migration file: `supabase/migrations/005_update_process_jobs_cron_schedule.sql`
- This migration documents the schedule change and creates a system configuration log

### 2. Code Updates
- Updated `supabase/functions/process_jobs/index.ts` comment to reflect 1-minute schedule
- Updated `supabase/functions/create_job/index.ts` to calculate estimated ready time as 1-2 minutes (was 2-5 minutes)

### 3. Documentation Updates
- Updated `SUPABASE_SETUP.md` to show the new schedule: `*/1 * * * *`

## Steps to Apply the Change

### 1. Run the Database Migration
```bash
# Push the migration to your Supabase project
supabase db push
```

### 2. Update External Cron Service
Since Supabase uses an external cron service, you must manually update the schedule:

1. Log into your cron service (e.g., [cron-job.org](https://cron-job.org))
2. Find the job that calls: `https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_jobs`
3. Update the schedule from `*/5 * * * *` to `*/1 * * * *`
4. Save the changes

### 3. Deploy Updated Edge Functions
```bash
# Deploy the updated functions
supabase functions deploy process_jobs --no-verify-jwt
supabase functions deploy create_job --no-verify-jwt
```

## Important Considerations

### Performance Impact
- **5x increase in function invocations**: The function will run 60 times per hour instead of 12 times
- **Cost implications**: Monitor your Supabase Edge Function usage to ensure you stay within plan limits
- **Database load**: More frequent job processing may increase database queries

### Monitoring
After applying the change, monitor:
- Edge Function invocation count and duration
- Database query performance
- Job processing latency
- Error rates

### Rollback Plan
If issues arise, you can quickly revert:
1. Change the cron schedule back to `*/5 * * * *` in your external cron service
2. Update the estimated ready time calculation back to 3 minutes
3. Document the rollback in the system_config_log table

## Verification
To verify the change is working:
1. Create a new job and check the `estimated_ready_time` is ~1.5 minutes in the future
2. Monitor the `process_jobs` function logs to confirm it's running every minute
3. Track actual job processing times for welcome DayStarts