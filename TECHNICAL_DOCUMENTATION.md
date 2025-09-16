# DayStart Technical Documentation

This document provides comprehensive technical documentation for the DayStart application, including API usage, rate limits, scheduled jobs, and infrastructure details.

## Table of Contents
- [API Documentation & Rate Limits](#api-documentation--rate-limits)
  - [AI & Text-to-Speech APIs](#ai--text-to-speech-apis)
  - [News APIs](#news-apis)
  - [Financial Data APIs](#financial-data-apis)
  - [Sports APIs](#sports-apis)
  - [Weather APIs](#weather-apis)
  - [Backend & Infrastructure](#backend--infrastructure)
  - [Monitoring & Rate Limit Management](#monitoring--rate-limit-management)
  - [Cost Optimization Strategies](#cost-optimization-strategies)
- [Scheduled Jobs (Cron)](#scheduled-jobs-cron)
  - [Process Jobs](#1-process-jobs)
  - [Refresh Content](#2-refresh-content)
  - [Cleanup Audio](#3-cleanup-audio)
  - [Healthcheck](#4-healthcheck)
  - [Troubleshooting](#troubleshooting)
  - [Cost Considerations](#cost-considerations)

---

# API Documentation & Rate Limits

This section provides a comprehensive overview of all external APIs used in the DayStart application, including rate limits, pricing, and usage patterns.

## AI & Text-to-Speech APIs

### OpenAI API
- **Purpose**: GPT-4o-mini script generation, TTS audio synthesis
- **Endpoints Used**:
  - `/v1/chat/completions` (GPT-4o-mini script generation)
  - `/v1/audio/speech` (GPT-4o-mini-tts)
- **Models Used**:
  - **gpt-4o-mini**: Script generation and content adjustment
  - **gpt-4o-mini-tts**: Text-to-speech audio synthesis
- **Rate Limits** (Current Account):
  - **gpt-4o-mini**: 4,000,000 TPM, 5,000 RPM, 40,000,000 TPD
  - **gpt-4o-mini-tts**: 600,000 TPM, 5,000 RPM
- **Pricing**: Pay-per-use
  - gpt-4o-mini: ~$0.15/1M input tokens, ~$0.60/1M output tokens
  - gpt-4o-mini-tts: $15/1M characters
- **Usage Pattern**: 1-2 script generations + 1-2 TTS calls per job
- **Configuration**: `OPENAI_API_KEY` environment variable

### ElevenLabs API
- **Purpose**: Primary TTS provider using `eleven_flash_v2_5` model
- **Endpoint**: `/v1/text-to-speech/{voice_id}`
- **Voice IDs Used**:
  - `pNInz6obpgDQGcFmaJgB` (Adam)
  - `21m00Tcm4TlvDq8ikWAM` (Rachel)  
  - `AZnzlk1XvdvUeBnXmlld` (Domi)
- **Current Plan**: Creator Plan
- **Rate Limits**:
  - **Concurrency**: 5 concurrent requests
  - **Characters**: 100,000 characters/month
- **Pricing**: $0.30/1,000 characters (Creator Plan)
- **Usage Pattern**: ~500-1500 characters per job (fallback when OpenAI TTS fails)
- **Configuration**: `ELEVENLABS_API_KEY` environment variable

## News APIs

### NewsAPI
- **Purpose**: News content from multiple endpoints
- **Endpoints Used**:
  - `/v2/top-headlines` (general + business category)
  - `/v2/everything` (targeted keyword search)
- **Current Plan**: Business ($500/month)
- **Rate Limits**:
  - **Monthly Requests**: 250,000 requests/month
  - **Rate Limiting**: 1,000 requests/hour (no official concurrent limit)
- **Usage Pattern**: 
  - 3 calls per refresh cycle (general, business, targeted)
  - ~80 articles fetched per cycle
  - Refresh cycles: Every hour
  - **Monthly Usage**: ~2,160 requests/month (3 × 24 × 30)
- **Configuration**: `NEWSAPI_KEY` environment variable (optional)

### GNews API
- **Purpose**: Additional news source for content diversity
- **Endpoint**: `/v4/top-headlines`
- **Current Plan**: Essential ($60/month)
- **Rate Limits**:
  - **Daily Requests**: 1,000 requests/day
  - **Concurrent Requests**: 4 requests/second
  - **Articles per Request**: Up to 25 articles
- **Features**:
  - Real-time article availability
  - Access to all sources
  - Historical data from 2020
  - CORS enabled for all origins
  - No truncated content
  - Email support
- **Usage Pattern**: 1 call per refresh cycle (25 articles)
- **Configuration**: `GNEWS_API_KEY` environment variable (optional)

## Financial Data APIs

### Yahoo Finance (via RapidAPI)
- **Purpose**: Stock market data, forex, cryptocurrency prices
- **Endpoint**: `/market/v2/get-quotes` (apidojo-yahoo-finance-v1)
- **Current Plan**: Basic ($10/month)
- **Rate Limits**:
  - **Monthly Requests**: 10,000 requests/month
  - **Rate Limit**: 5 requests/second
- **Usage Pattern**: 
  - 1 call per refresh cycle
  - 50+ symbols per call (base symbols + user-requested)
  - Base symbols include: AAPL, GOOGL, MSFT, AMZN, TSLA, etc.
  - **Monthly Usage**: ~720 requests/month (1 × 24 × 30)
- **Configuration**: `RAPIDAPI_KEY` environment variable (optional)

## Sports APIs

### ESPN API
- **Purpose**: NBA scores and sports data
- **Endpoint**: `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard`
- **Rate Limits**: ✅ **Public API** - No authentication required
- **Pricing**: Free
- **Usage Pattern**: 1 call per refresh cycle
- **Configuration**: None required

### TheSportDB API
- **Purpose**: Additional sports data and scores
- **Current Plan**: Free
- **Rate Limits**: ⚠️ **Unclear/Undocumented**
  - Free tier has informal limits but no official documentation
  - Generally allows reasonable usage for small applications
  - May implement throttling during high traffic periods
- **Pricing**: Free (no cost)
- **Usage Pattern**: 1 call per refresh cycle
- **Risk Assessment**: Low priority API - graceful degradation if limits hit
- **Configuration**: None required for free tier

## Weather APIs

### Apple WeatherKit
- **Purpose**: Local weather data and forecasts
- **Integration**: Native iOS CoreLocation + WeatherKit
- **Rate Limits**: ✅ **500,000 calls/month free**, then $0.50/1K calls
- **Pricing**: 
  - Free: 500,000 calls/month
  - Paid: $0.50 per 1,000 calls above free tier
- **Usage Pattern**: 1-2 calls per job (current + forecast)
- **Configuration**: Apple Developer Program membership required

## Backend & Infrastructure

### Supabase
- **Purpose**: Database, functions, storage, authentication
- **Services Used**:
  - PostgreSQL database
  - Edge functions
  - Storage buckets
  - Real-time subscriptions
- **Current Plan**: Pro ($25/month base)
- **Included Resources**:
  - **Monthly Active Users**: 100,000 (then $0.00325/MAU)
  - **Database Storage**: 8 GB (then $0.125/GB)
  - **Egress**: 250 GB (then $0.09/GB)
  - **Cached Egress**: 250 GB (then $0.03/GB)
  - **File Storage**: 100 GB (then $0.021/GB)
  - **Edge Functions**: 2M invocations/month
- **Features**:
  - Email support
  - Daily backups (7-day retention)
  - 7-day log retention
- **Usage Pattern**: Continuous usage for all app operations
- **Configuration**: Multiple environment variables in iOS app

### Cron-job.org
- **Purpose**: Scheduled content refresh triggers
- **Rate Limits**: ✅ **Free tier supports basic cron jobs**
- **Pricing**: Free for basic usage
- **Usage Pattern**: Hourly triggers for content refresh
- **Configuration**: Web-based cron job setup

## Monitoring & Rate Limit Management

### Current Rate Limiting Strategy
1. **API Key Validation**: All APIs check for required keys before making calls
2. **Graceful Degradation**: Missing APIs are logged but don't break the system
3. **Content Caching**: 168-hour TTL reduces API calls
4. **Request Bundling**: Multiple data points per API call when possible

### Usage Tracking
- **Cost Tracking**: OpenAI and ElevenLabs usage logged in database
- **Request Logging**: All API calls logged with timestamps
- **Error Monitoring**: Failed API calls tracked for rate limit detection

### Rate Limit Handling
```typescript
// Example from refresh_content function
const missingEnvs: string[] = []
if (Deno.env.get('NEWSAPI_KEY')) {
  // Include NewsAPI sources
} else { 
  missingEnvs.push('NEWSAPI_KEY') 
}
```

## Cost Optimization Strategies

### Current Optimizations
1. **Content Caching**: 7-day cache reduces API calls by ~95%
2. **Conditional API Usage**: Only enabled APIs are called
3. **Batch Processing**: Multiple symbols per Yahoo Finance call
4. **Fallback Providers**: ElevenLabs as TTS fallback to OpenAI

### Recommended Monitoring
1. **Set up billing alerts** for all paid APIs
2. **Monitor monthly usage** against plan limits
3. **Track cost per user** for scaling projections
4. **Implement circuit breakers** for expensive APIs

## Action Items

⚠️ **MISSING INFORMATION NEEDED**:

Please provide the following plan details to complete this documentation:

1. **ElevenLabs Plan**: Free/Starter/Creator/Pro?
2. **NewsAPI Plan**: Developer (Free)/Business?
3. **GNews Plan**: Free/Basic/Professional?
4. **RapidAPI Plan**: Free/Basic/Pro?
5. **TheSportDB Plan**: Free/Patreon?
6. **Supabase Plan**: Free/Pro?

Once provided, this document will be updated with exact rate limits and monthly costs.

---

# Scheduled Jobs (Cron)

This section outlines all scheduled tasks (cron jobs) used by the DayStart application. All cron jobs are managed through external services (e.g., cron-job.org) and call Supabase Edge Functions.

## Overview

| Job Name | Schedule | Frequency | Purpose |
|----------|----------|-----------|---------|
| Process Jobs | `*/1 * * * *` | Every 1 minute | Process audio generation queue |
| Refresh Content | `0 * * * *` | Every hour | Refresh news, stocks, sports cache |
| Cleanup Audio | `5 1 * * *` | Daily at 1:05 AM UTC | Delete old audio files |
| Healthcheck | `5 2 * * *` | Daily at 2:05 AM UTC | Run system health checks and email report |
| Daily Generic DayStart | `45 4 * * *` | Daily at 4:45 AM ET | Generate generic audio briefing |

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

## 5. Daily Generic DayStart

### Purpose
Creates a generic, non-personalized DayStart audio briefing for general distribution or testing purposes.

### Configuration
- **URL**: `https://[PROJECT_REF].supabase.co/functions/v1/create_job`
- **Method**: POST
- **Schedule**: `45 4 * * *` (daily at 4:45 AM ET)
- **Headers**:
  ```json
  {
    "Authorization": "Bearer [SERVICE_ROLE_KEY]",
    "x-client-info": "DAILY_GENERIC",
    "Content-Type": "application/json"
  }
  ```
- **Body**:
  ```json
  {
    "local_date": "{{CURRENT_DATE}}",
    "scheduled_at": "{{NOW_PLUS_2MIN}}",
    "preferred_name": null,
    "include_weather": false,
    "include_news": true,
    "include_sports": true,
    "include_stocks": true,
    "stock_symbols": ["AAPL", "BTC-USD", "TSLA", "SPY", "QQQ"],
    "include_calendar": false,
    "include_quotes": true,
    "quote_preference": "good_feelings",
    "voice_option": "voice2",
    "daystart_length": 180,
    "timezone": "America/New_York"
  }
  ```

### Monitoring
- Check `jobs` table for entries with `user_id = "DAILY_GENERIC"`
- Verify audio generation completes within expected time
- Monitor storage for generated audio files

### Notes
- Creates a 3-minute briefing without personalization
- Uses Rachel voice (voice2) from ElevenLabs
- Includes market-focused stock symbols including crypto (BTC-USD)
- Generates uplifting/positive quotes with "good_feelings" preference
- No weather or calendar data included
- Can be used for distribution, testing, or as a sample

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

---

**Last Updated**: January 2025  
**Maintained By**: Development Team  
**Review Schedule**: Monthly or when API plans change