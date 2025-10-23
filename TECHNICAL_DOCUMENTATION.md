# DayStart Technical Documentation

This document provides comprehensive technical documentation for the DayStart application, including API usage, rate limits, scheduled jobs, and infrastructure details.

## Table of Contents
- [System Architecture](#system-architecture)
  - [iOS Frontend](#ios-frontend)
  - [Backend Services](#backend-services)
  - [Database Schema](#database-schema)
  - [Authentication](#authentication)
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

# System Architecture

## iOS Frontend

### Architecture Patterns
- **Language**: Swift 5.9+ with SwiftUI
- **Minimum iOS Version**: iOS 17.0+
- **Architecture**: MVVM + Combine with lazy service loading
- **Service Pattern**: 5-tier lazy loading system inspired by Spotify
  - Tier 1: Essential services (UserPreferences, ThemeManager)
  - Tier 2: Core UI services (AudioPlayerManager, HapticManager)
  - Tier 3: User feature services (NotificationScheduler, StreakManager)
  - Tier 4: Content generation services (SupabaseClient, AudioDownloader)
  - Tier 5: Platform integration services (LocationManager, WeatherService)

### Key Components
- **ServiceRegistry**: Centralized lazy loading system for all services
- **PurchaseManager**: StoreKit 2 integration for subscriptions ($4.99/month, $39.99/year)
- **AudioPlayerManager**: AVFoundation-based audio playback with background support
- **HomeViewModel**: Main app state management with 1,858 lines of complex logic
- **OnboardingView**: 2,350-line comprehensive welcome flow

### Performance Optimizations
- **Startup Time**: Sub-100ms app launch with minimal service loading
- **Background Tasks**: BGTaskScheduler for audio prefetching and snapshot updates
- **Memory Management**: Aggressive service unloading when not needed
- **Caching**: Three-tier caching (memory → local file → background downloads)

## Backend Services

### Supabase Edge Functions
- **create_job**: Job creation with receipt-based auth, priority handling
- **process_jobs**: Core AI script generation + TTS synthesis pipeline
- **get_audio_status**: Audio status checking with completion tracking
- **refresh_content**: Hourly content cache updates from multiple APIs
- **cleanup-audio**: Daily/weekly storage cleanup with orphan detection
- **create_share**: Public share link generation with rate limiting
- **get_shared_daystart**: Public endpoint for web player access
- **submit_feedback**: User feedback collection
- **update_jobs**: Bulk job updates for schedule changes
- **update_job_snapshots**: Location/weather/calendar data updates

### Content Generation Pipeline
1. **Job Creation**: User preferences captured, job queued with priority
2. **Content Aggregation**: News, sports, stocks fetched from cache
3. **AI Script Generation**: GPT-4o-mini creates personalized script
4. **TTS Synthesis**: OpenAI TTS (primary) or ElevenLabs (fallback)
5. **Audio Storage**: M4A files stored in Supabase with 10-day retention

## Database Schema

### Core Tables
- **jobs**: Main job queue with user preferences and generation status
  - Unique constraint on (user_id, local_date)
  - Priority system: 100 (welcome), 75 (urgent), 50 (regular), 25 (background)
  - Lease-based processing with FOR UPDATE SKIP LOCKED
- **content_cache**: 12-hour cached content from external APIs
- **daystart_history**: Completed DayStarts for replay (deprecated)
- **purchase_users**: Receipt ID tracking for analytics
- **public_daystart_shares**: Shareable links with analytics
- **app_feedback**: User feedback with optional email
- **request_logs**: API request logging for debugging
- **audio_cleanup_log**: Cleanup operation history

### Recent Schema Evolution
- Migration 022: Transitioned from JWT to receipt-based auth
- Migration 028: Added is_welcome flag for onboarding DayStarts  
- Migration 029: Added social_daystart flag for non-app content
- Migration 032: Introduced share functionality
- Migration 034-035: Added orphan audio cleanup functions

## Authentication

### Receipt-Based System
- **User Identifier**: StoreKit transaction receipt ID
- **Headers**:
  - `x-client-info`: Receipt ID (user identifier)
  - `x-auth-type`: "purchase" or "anonymous"
- **Test Support**: Test receipts prefixed with "tx_" accepted
- **No User Accounts**: Privacy-first design with no email/password

### RLS Policies
- Users can only access their own data based on receipt ID
- Service role has full access for background jobs
- Public access allowed for share functionality

---

# API Documentation & Rate Limits

This section provides a comprehensive overview of all external APIs used in the DayStart application, including rate limits, pricing, and usage patterns.

## AI & Text-to-Speech APIs

### OpenAI API
- **Purpose**: GPT-4o-mini script generation, TTS audio synthesis (primary provider)
- **Endpoints Used**:
  - `/v1/chat/completions` (GPT-4o-mini script generation)
  - `/v1/audio/speech` (TTS-1 model with alloy voice)
- **Models Used**:
  - **gpt-4o-mini**: Script generation with dynamic token allocation
  - **tts-1**: High-quality text-to-speech (alloy voice)
- **Rate Limits** (Current Account):
  - **gpt-4o-mini**: 4,000,000 TPM, 5,000 RPM, 40,000,000 TPD
  - **tts-1**: Standard OpenAI TTS limits
- **Pricing**: Pay-per-use
  - gpt-4o-mini: ~$0.15/1M input tokens, ~$0.60/1M output tokens
  - tts-1: $15/1M characters
- **Usage Pattern**: 
  - 1 script generation per job (800-2000 tokens based on duration)
  - 1 TTS call per job (500-1500 characters)
- **Configuration**: `OPENAI_API_KEY` environment variable

### ElevenLabs API
- **Purpose**: Fallback TTS provider with voice variety
- **Endpoint**: `/v1/text-to-speech/{voice_id}/stream`
- **Voice IDs Used**:
  - `cgSgspJ2msm6clMCkdW9` (Jessica - voice1/Grace)
  - `21m00Tcm4TlvDq8ikWAM` (Rachel - voice2)  
  - `TxGEqnHWrfWFTfGW9XjX` (Josh - voice3/Matthew)
- **Model**: `eleven_turbo_v2_5` (fastest model)
- **Current Plan**: Unknown (needs clarification)
- **Rate Limits**: Depends on plan
- **Usage Pattern**: 
  - Fallback when OpenAI TTS fails
  - Voice variety for user preference
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
- **Usage Pattern**: 1 call per refresh cycle (10 articles max)
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
- **Purpose**: Sports scores and data (multiple leagues)
- **Endpoints**: 
  - `/apis/site/v2/sports/football/nfl/scoreboard`
  - `/apis/site/v2/sports/basketball/nba/scoreboard`
  - `/apis/site/v2/sports/baseball/mlb/scoreboard`
  - `/apis/site/v2/sports/hockey/nhl/scoreboard`
- **Rate Limits**: ✅ **Public API** - No authentication required
- **Pricing**: Free
- **Usage Pattern**: 4 calls per refresh cycle (one per major sport)
- **Configuration**: None required

### TheSportDB API
- **Purpose**: Additional sports data and scores
- **Current Plan**: Free
- **Rate Limits**: ⚠️ **Unclear/Undocumented**
  - Free tier has informal limits but no official documentation
  - Generally allows reasonable usage for small applications
  - May implement throttling during high traffic periods
- **Pricing**: Free (no cost)
- **Usage Pattern**: Multiple endpoints called per refresh cycle
- **Endpoints Used**:
  - `/eventsbyleague.php?id=4387` (NBA)
  - `/eventsbyleague.php?id=4391` (NFL)  
  - `/eventsbyleague.php?id=4424` (MLB)
  - `/eventsbyleague.php?id=4380` (NHL)
- **Risk Assessment**: Low priority API - graceful degradation if limits hit
- **Configuration**: None required for free tier

## Weather APIs

### Apple WeatherKit
- **Purpose**: Local weather data and forecasts
- **Integration**: Native iOS WeatherKit framework
- **Rate Limits**: ✅ **500,000 calls/month free**, then $0.50/1K calls
- **Pricing**: 
  - Free: 500,000 calls/month
  - Paid: $0.50 per 1,000 calls above free tier
- **Usage Pattern**: 
  - 1 call per job for current conditions
  - Data included in job snapshot for backend use
- **Privacy**: Location permission required ("When In Use")
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

## Current Service Status

### Confirmed Active Services
- **OpenAI**: Active (usage tracked in database)
- **Supabase**: Pro Plan ($25/month base)
- **Apple WeatherKit**: Active (via iOS app)
- **ESPN API**: Active (free public API)
- **Cron-job.org**: Active (free tier)

### Services Requiring Confirmation
- **ElevenLabs**: API key exists, plan unknown
- **NewsAPI**: Business plan likely ($500/month)
- **GNews**: Essential plan likely ($60/month)
- **Yahoo Finance**: Basic plan likely ($10/month)
- **TheSportDB**: Free tier assumed

---

# Scheduled Jobs (Cron)

This section outlines all scheduled tasks (cron jobs) used by the DayStart application. All cron jobs are managed through external services (e.g., cron-job.org) and call Supabase Edge Functions.

## Overview

| Job Name | Schedule | Frequency | Purpose |
|----------|----------|-----------|---------|
| Process Jobs | `*/1 * * * *` | Every 1 minute | Process audio generation queue |
| Refresh Content | `0 * * * *` | Every hour | Refresh news, stocks, sports cache |
| Cleanup Audio | `5 1 * * *` | Daily at 1:05 AM UTC | Delete old audio files |
| Weekly Orphan Cleanup | `5 2 * * 0` | Weekly at 2:05 AM UTC (Sunday) | Deep scan for orphaned audio files |
| Healthcheck | `5 2 * * *` | Daily at 2:05 AM UTC | Run system health checks |

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

### Implementation Details
- **Worker Pattern**: Leases jobs with 15-minute timeout
- **Priority System**: 
  - 100: Welcome/immediate jobs
  - 75: Same-day urgent (<4 hours)
  - 50: Regular (4-24 hours)
  - 25: Background (>24 hours)
- **Retry Logic**: 3 attempts before marking failed
- **Content Sources**: Uses cached data from content_cache table
- **Script Generation**: GPT-4o-mini with dynamic token limits
- **TTS Providers**: OpenAI (primary), ElevenLabs (fallback)

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

### Implementation Details
- **Cache Duration**: 168 hours (7 days) with stale content fallback
- **Refresh Lock**: Prevents concurrent refreshes (5-minute timeout)
- **Content Sources**:
  - News: NewsAPI (3 categories) + GNews
  - Sports: ESPN (4 leagues) + TheSportDB (4 leagues)
  - Stocks: Yahoo Finance (batch requests)
- **Deduplication**: Removes duplicate news articles across sources
- **Error Handling**: Continues if individual APIs fail

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

### Implementation Details
- **Retention Period**: 10 days for all audio files
- **Cleanup Modes**:
  - `database`: Delete files based on job records
  - `storage`: Scan storage for old files
  - `hybrid`: Both database and storage cleanup
- **Rate Limiting**: 20-hour cooldown between runs
- **Batch Processing**: 100 files per batch
- **Special Handling**: Cleans test-* folders immediately

## 4. Weekly Orphan Audio Cleanup

### Purpose
Performs a deep storage scan to identify and remove orphaned audio files that have no corresponding job records in the database. This catches files that may have been missed by the regular cleanup process.

### Configuration
- **URL**: `https://[PROJECT_REF].supabase.co/functions/v1/cleanup-audio`
- **Method**: POST
- **Schedule**: `5 2 * * 0` (weekly on Sunday at 2:05 AM UTC)
- **Headers**:
  ```
  Authorization: Bearer [SERVICE_ROLE_KEY]
  Content-Type: application/json
  ```
- **Body**:
  ```json
  {
    "mode": "hybrid",
    "days_to_keep": 10
  }
  ```

### Monitoring
- Check `audio_cleanup_log` table for execution history with orphan statistics
- Look for `orphans_deleted` and `orphans_failed` in the `error_details` JSON
- Monitor Edge Function logs for orphan detection details
- Alert if orphan count exceeds expected threshold

### Notes
- Uses hybrid mode to run both database-based and storage-based cleanup
- Scans only date folders older than retention period for performance
- Processes files in batches to avoid timeouts
- Requires SERVICE_ROLE_KEY for full storage access
- Complements daily cleanup by catching edge cases

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

### Implementation Details
- **Health Checks**:
  - Database connectivity and job queue status
  - Content cache freshness (warns if >3 hours old)
  - Storage bucket accessibility
  - Recent error patterns in logs
  - Audio file integrity
- **Email Report**: Sends summary via Resend API
- **Async Execution**: Returns immediately, processes in background


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
- **Weekly Orphan Audio Cleanup**: ~4 invocations/month
- **Healthcheck**: ~30 invocations/month

Total: ~44,000 Edge Function invocations/month

## Future Improvements

1. Consider moving to Supabase native cron when available
2. Add webhook notifications for failures
3. Implement more granular scheduling based on usage patterns
4. Add automated backup before cleanup operations

---

# Share System Documentation

This section provides comprehensive documentation for the DayStart share functionality, which allows users to create and share public links to their audio briefings via a branded web player hosted at `daystartai.app/shared/{token}`.

## Table of Contents
- [System Overview](#system-overview)
- [Share API Endpoints](#share-api-endpoints)
- [Database Schema](#database-schema)
- [Web Player Infrastructure](#web-player-infrastructure)
- [iOS Integration](#ios-integration)
- [Security & Rate Limiting](#security--rate-limiting)
- [Analytics & Monitoring](#analytics--monitoring)

## System Overview

The share system enables users to:
- Create time-limited shareable links for completed DayStart briefings
- Share their audio content via a branded web player
- Track views and engagement analytics
- Provide a conversion funnel to drive app downloads

### Architecture Components

1. **iOS App**: Initiates share creation via API calls
2. **Supabase Edge Functions**: Handle share creation and retrieval
3. **PostgreSQL Database**: Stores share metadata and analytics
4. **Netlify Web Player**: Serves branded audio player at `daystartai.app`
5. **Supabase Storage**: Hosts audio files with signed URL access

### Key Features
- **Time-limited shares**: 48-hour default expiration
- **Rate limiting**: Max 5 shares per DayStart, 10 per user per day
- **Analytics tracking**: Views, engagement, conversion metrics
- **Privacy-preserving**: No user data exposed in public shares

### User Flow

1. User completes a DayStart briefing in iOS app
2. User taps share button in completion screen or audio player
3. iOS app calls `create_share` API with job data
4. Backend creates share record with URL-safe token
5. iOS app presents system share sheet with branded message
6. Recipients visit `daystartai.app/shared/{token}`
7. Web player calls `get_shared_daystart` API to load audio
8. Analytics track views and conversion events

## Share API Endpoints

### 1. Create Share (`create_share`)

Creates a shareable link for a completed DayStart briefing.

**Endpoint**: `/functions/v1/create_share`
**Method**: POST
**Authentication**: Receipt-based via `x-client-info` header

#### Request Headers
```
Content-Type: application/json
x-client-info: [receipt_id]
x-app-version: [app_version] (optional)
```

#### Request Body
```json
{
  "job_id": "uuid",
  "share_source": "completion_screen|audio_player|manual",
  "duration_hours": 48,
  "audio_file_path": "/path/to/audio.m4a",
  "audio_duration": 180,
  "local_date": "2025-01-20",
  "daystart_length": 180,
  "preferred_name": "John"
}
```

#### Response (201 Created)
```json
{
  "share_url": "https://daystartai.app/shared/abc123def456",
  "token": "abc123def456",
  "expires_at": "2025-01-22T14:30:00Z",
  "share_id": "uuid"
}
```

#### Rate Limits
- **Per Job**: Maximum 5 shares per DayStart briefing
- **Per User**: Maximum 10 shares per day
- **Error Codes**: `RATE_LIMIT_EXCEEDED`, `DAILY_LIMIT_EXCEEDED`

### 2. Get Shared DayStart (`get_shared_daystart`)

Retrieves shared DayStart data for web player consumption.

**Endpoint**: `/functions/v1/get_shared_daystart`
**Method**: POST
**Authentication**: None (public endpoint)

#### Request Headers
```
Content-Type: application/json
Origin: https://daystartai.app
```

#### Request Body
```json
{
  "token": "abc123def456"
}
```

#### Response (200 OK)
```json
{
  "audio_url": "https://[project].supabase.co/storage/v1/s3/[signed_url]",
  "duration": 180,
  "date": "2025-01-20",
  "length_minutes": 3,
  "user_name": "John"
}
```

#### Error Responses
- **400**: `INVALID_TOKEN` - Token format invalid
- **404**: `SHARE_EXPIRED` - Share link expired or not found
- **404**: `AUDIO_NOT_FOUND` - Audio file no longer available
- **500**: `URL_GENERATION_FAILED` - Cannot create signed URL

## Database Schema

### `public_daystart_shares` Table

The share system uses a dedicated table that stores all necessary data locally to avoid expensive JOINs with the jobs table during public access.

```sql
CREATE TABLE public_daystart_shares (
  share_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES jobs(job_id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  share_token TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  view_count INTEGER DEFAULT 0,
  last_accessed_at TIMESTAMPTZ,
  
  -- Analytics fields
  share_source TEXT, -- 'completion_screen', 'audio_player', 'manual'
  share_metadata JSONB DEFAULT '{}'::jsonb,
  clicked_cta BOOLEAN DEFAULT FALSE,
  converted_to_user BOOLEAN DEFAULT FALSE,
  shares_per_job INTEGER DEFAULT 1,
  
  -- Denormalized job data for performance
  audio_file_path TEXT NOT NULL,
  audio_duration INTEGER NOT NULL,
  local_date TEXT NOT NULL,
  daystart_length INTEGER NOT NULL,
  preferred_name TEXT
);
```

#### Indexes
```sql
CREATE UNIQUE INDEX shares_token_idx ON public_daystart_shares(share_token);
CREATE INDEX shares_expiry_idx ON public_daystart_shares(expires_at);
CREATE INDEX shares_user_idx ON public_daystart_shares(user_id);
CREATE INDEX shares_job_idx ON public_daystart_shares(job_id);
```

#### Row Level Security (RLS)

```sql
-- Public read for valid shares (anonymous access)
CREATE POLICY "Public read for valid shares" ON public_daystart_shares
  FOR SELECT TO anon, authenticated
  USING (expires_at > NOW());

-- Users can see their own shares
CREATE POLICY "Users can view own shares" ON public_daystart_shares
  FOR SELECT TO anon, authenticated
  USING (user_id = current_setting('request.headers', true)::json->>'x-client-info');

-- Service role full access
CREATE POLICY "Service role full access shares" ON public_daystart_shares
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);
```

## Web Player Infrastructure

### Netlify Site Structure

The web player is hosted on Netlify at the existing `daystartai.app` domain and is currently deployed manually.

```
netlify-site/
├── index.html              # Root redirect to App Store
├── shared/
│   └── index.html          # Branded audio player page
├── _redirects              # Netlify routing rules
├── netlify.toml            # Build and security config
├── assets/
│   ├── css/
│   │   └── daystart-player.css  # DayStart themed styles
│   ├── js/
│   │   └── audio-player.js      # JavaScript player logic
│   └── images/
│       └── daystart-icon-large.jpeg
```

### Routing Configuration

**`_redirects` file:**
```
# Shared DayStart player - capture token parameter
/shared/:token /shared/index.html 200

# Root and other paths -> App Store
/ https://apps.apple.com/app/apple-store/id6751055528?pt=128010523&ct=daystartai.app&mt=8 302
/* https://apps.apple.com/app/apple-store/id6751055528?pt=128010523&ct=daystartai.app&mt=8 302
```

### Security Headers

**`netlify.toml`:**
```toml
[[headers]]
  for = "/shared/*"
  [headers.values]
    X-Frame-Options = "DENY"
    X-Content-Type-Options = "nosniff"
    Referrer-Policy = "strict-origin-when-cross-origin"
    Cache-Control = "public, max-age=300"
```

### Player Features

- **Progressive Loading**: Shows spinner while fetching share data
- **Audio Controls**: Play/pause, skip forward/back (10s), progress scrubbing
- **Responsive Design**: Works on mobile and desktop
- **Error Handling**: Graceful fallback for expired/invalid shares
- **App Promotion**: Download banner and CTA section
- **Analytics**: Google Analytics (G-RN79S5YCEN) tracking
- **App Store Integration**: Smart banner for iOS users

## iOS Integration

### Share Creation Flow

1. **Data Validation**: Ensures `jobId` and `audioStoragePath` are available
2. **API Request**: Calls `SupabaseClient.createShare()` with full DayStart data
3. **Share Message**: Generates leadership-focused marketing copy
4. **System Share**: Presents `UIActivityViewController` with share URL
5. **Analytics**: Tracks share events and conversion metrics

### Share Message Template

```swift
let shareText = """
🎯 Just got my Morning Intelligence Brief

\(duration) minutes of curated insights delivered like my own Chief of Staff prepared it.

Stop reacting. Start leading.

Listen: \(shareResponse.shareUrl)

Join the leaders who start ahead: https://daystartai.app

#MorningIntelligence #Leadership #DayStart
"""
```

### Error Handling

- **Missing Data**: Attempts to fetch `audioStoragePath` from API if missing
- **API Errors**: Shows user-friendly error messages
- **Rate Limiting**: Handles `RATE_LIMIT_EXCEEDED` and `DAILY_LIMIT_EXCEEDED`
- **Loading States**: Visual feedback during share creation

## Security & Rate Limiting

### Token Generation

```typescript
const generateShareToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
    .substring(0, 12) // 12-character URL-safe token
}
```

### Rate Limiting Strategy

1. **Per-Job Limits**: Maximum 5 shares per DayStart briefing
2. **Daily User Limits**: Maximum 10 shares per user per day
3. **Expiration**: Default 48-hour share lifetime
4. **Cleanup**: Automatic deletion of expired shares

### Storage Security

- **Signed URLs**: 1-hour expiration for audio access
- **File Verification**: Downloads file to verify existence before sharing
- **Service Role**: Uses elevated permissions for storage operations
- **CORS**: Restricts access to `daystartai.app` domain

## Analytics & Monitoring

### Tracked Metrics

1. **Share Creation**: Source, timestamp, user demographics
2. **View Tracking**: Unique views, repeat visits, geographic data
3. **Engagement**: Audio play duration, completion rates
4. **Conversion**: CTA clicks, app downloads, user registrations

### Monitoring Queries

```sql
-- Daily share creation stats
SELECT 
  DATE(created_at) as date,
  COUNT(*) as shares_created,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT job_id) as unique_briefings
FROM public_daystart_shares
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Conversion funnel analysis
SELECT 
  COUNT(*) as total_shares,
  COUNT(*) FILTER (WHERE view_count > 0) as viewed_shares,
  COUNT(*) FILTER (WHERE clicked_cta = true) as cta_clicks,
  COUNT(*) FILTER (WHERE converted_to_user = true) as conversions,
  ROUND(100.0 * COUNT(*) FILTER (WHERE view_count > 0) / COUNT(*), 2) as view_rate,
  ROUND(100.0 * COUNT(*) FILTER (WHERE clicked_cta = true) / COUNT(*), 2) as cta_rate,
  ROUND(100.0 * COUNT(*) FILTER (WHERE converted_to_user = true) / COUNT(*), 2) as conversion_rate
FROM public_daystart_shares
WHERE created_at >= NOW() - INTERVAL '30 days';

-- Share system health check
SELECT 
  COUNT(*) FILTER (WHERE expires_at > NOW()) as active_shares,
  COUNT(*) FILTER (WHERE expires_at <= NOW()) as expired_shares,
  MAX(view_count) as most_viewed_share,
  AVG(view_count) as avg_views_per_share
FROM public_daystart_shares;
```

### Cleanup Operations

Automated cleanup runs as part of the existing `cleanup-audio` scheduled job:

```typescript
// Clean up expired shares (7+ days old)
const { error: shareCleanupError } = await supabase
  .from('public_daystart_shares')
  .delete()
  .lt('expires_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
```

### Cost Considerations

- **Edge Function Calls**: ~2 calls per share (create + view)
- **Storage**: Signed URL generation per audio access
- **Bandwidth**: Audio file delivery via CDN
- **Database**: Minimal storage impact with automatic cleanup

---

---

# Development & Deployment

## iOS App

### Build Configuration
- **Bundle ID**: `ai.bananaintelligence.DayStart`
- **Team ID**: `ZH33WS872M`
- **Deployment Target**: iOS 17.0+
- **Xcode Version**: 15.0+
- **Swift Version**: 5.9+

### Environment Configuration
Stored in Info.plist:
- `SupabaseBaseURL`
- `SupabaseRestURL`
- `SupabaseFunctionsURL`
- `SupabaseAnonKey`

### Background Modes
- Audio playback
- Background fetch
- Background processing

## Supabase Backend

### Environment Variables
```
OPENAI_API_KEY
ELEVENLABS_API_KEY
NEWSAPI_KEY
GNEWS_API_KEY
RAPIDAPI_KEY
WORKER_AUTH_TOKEN
RESEND_API_KEY
RESEND_FROM_EMAIL
RESEND_TO_EMAIL
```

### Database Migrations
- **Current Version**: 035 (fix_orphan_cleanup_function)
- **Migration Strategy**: Forward-only, no breaking changes
- **RLS**: Enabled on all user-facing tables

### Edge Function Deployment
```bash
supabase functions deploy [function-name]
```

## Monitoring & Debugging

### Key Metrics
- **Job Success Rate**: Target >95%
- **Audio Generation Time**: Target <2 minutes
- **API Error Rate**: Target <1%
- **Storage Usage**: Monitor growth rate

### Debug Queries
```sql
-- Check job processing status
SELECT status, COUNT(*), MAX(updated_at)
FROM jobs
WHERE created_at > NOW() - INTERVAL '1 day'
GROUP BY status;

-- Monitor API costs
SELECT DATE(created_at), 
       SUM(script_cost) as ai_cost,
       SUM(tts_cost) as tts_cost,
       COUNT(*) as jobs
FROM jobs
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY DATE(created_at) DESC;

-- Check share system health
SELECT COUNT(*) as total_shares,
       COUNT(*) FILTER (WHERE view_count > 0) as viewed,
       AVG(view_count) as avg_views
FROM public_daystart_shares
WHERE created_at > NOW() - INTERVAL '30 days';
```

---

**Technical Documentation Status**: ✅ **UPDATED**
**Last Updated**: October 2025  
**Version**: 2.0 (Complete rewrite with current architecture)
**Review Schedule**: Monthly or when architecture changes