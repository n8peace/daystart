# DayStart Supabase Backend Implementation Plan

## Architecture Overview

**Production-ready backend** for DayStart morning briefing app with proper job queues, security hardening, and prefetch strategy for instant playback UX.

## Core Flow
1. **Job Creation**: App calls function 2hrs before scheduled time → creates job with user prefs
2. **Script Generation**: Workers lease jobs via `FOR UPDATE SKIP LOCKED`, call GPT-4o with fresh content
3. **Audio Generation**: Workers lease script-ready jobs, call ElevenLabs, store in private bucket  
4. **Hybrid Prefetch Strategy**: 
   - **Primary**: App schedules local silent notification at T-30m → triggers download
   - **Backup**: Local background refresh checks at T-20m, T-10m, T-5m
   - **Fallback**: On-demand download at T-0 if no cached audio
5. **Rolling Window**: App maintains 48-hour scheduling window locally (no server cron needed)
6. **Background**: Hourly cron jobs keep content fresh, cleanup removes old files

## Database Schema

### Tables

#### `users` (Supabase Auth managed)
```sql
-- Handled by Supabase Auth
-- Additional columns can be added via profiles table if needed
```

#### `user_devices` (Optional - for future features)
```sql
-- Removed: No longer needed for prefetch system
-- Push notifications are now handled locally by iOS app
-- This table can be added later if needed for other features
```

#### `user_schedule`
```sql
CREATE TABLE user_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  repeat_days INTEGER[] NOT NULL, -- Array of weekday numbers [1-7]
  wake_time_local TIME NOT NULL,
  timezone TEXT NOT NULL, -- IANA timezone (e.g., 'America/New_York')
  last_scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);
```

#### `jobs` (Main job queue)
```sql
CREATE TABLE jobs (
  job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  local_date DATE NOT NULL, -- User's local date
  scheduled_at TIMESTAMPTZ NOT NULL, -- When DayStart should play
  window_start TIMESTAMPTZ NOT NULL, -- When job can start processing (2hrs before)
  window_end TIMESTAMPTZ NOT NULL, -- Latest acceptable completion time
  
  -- Job processing
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'script_processing', 'script_ready', 'audio_processing', 'ready', 'failed', 'failed_missed')),
  attempt_count INTEGER DEFAULT 0,
  worker_id UUID, -- Which worker is processing
  lease_until TIMESTAMPTZ, -- FOR UPDATE SKIP LOCKED leasing
  
  -- User preferences (captured at job creation)
  preferred_name TEXT,
  location_data JSONB, -- { "city": "San Francisco", "state": "CA", "country": "US", "zip": "94102" }
  weather_data JSONB, -- Current and forecast from WeatherKit
  encouragement_preference TEXT,
  stock_symbols TEXT[],
  include_news BOOLEAN DEFAULT true,
  include_sports BOOLEAN DEFAULT true,
  desired_voice TEXT NOT NULL,
  desired_length INTEGER NOT NULL, -- minutes
  
  -- Generated content
  script TEXT,
  script_ready_at TIMESTAMPTZ,
  audio_path TEXT, -- Path in Supabase Storage
  audio_ready_at TIMESTAMPTZ,
  
  -- Tracking
  downloaded_at TIMESTAMPTZ, -- When app confirmed successful download
  failure_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, local_date) -- One job per user per local day
);

-- Indexes for performance
CREATE INDEX jobs_worker_queue_idx ON jobs(status, scheduled_at) WHERE status IN ('queued', 'script_ready');
CREATE INDEX jobs_user_date_idx ON jobs(user_id, local_date);
CREATE INDEX jobs_cleanup_idx ON jobs(audio_ready_at) WHERE audio_path IS NOT NULL;
```

#### `content_blocks`
```sql
CREATE TABLE content_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL CHECK (content_type IN ('news', 'sports', 'stocks')),
  region TEXT, -- For news/sports: 'US-CA-SF', 'US-NY', 'US', 'INTL'
  league TEXT, -- For sports: 'NFL', 'NBA', 'MLB', etc.
  
  -- Raw content from APIs
  raw_payload JSONB NOT NULL,
  
  -- Processed for GPT-4o
  processed_content JSONB, -- Summarized/formatted for script generation
  
  importance_score INTEGER DEFAULT 5, -- 1-10, for breaking news priority
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '12 hours')
);

-- Indexes
CREATE INDEX content_blocks_lookup_idx ON content_blocks(content_type, region, created_at DESC);
CREATE INDEX content_blocks_sports_idx ON content_blocks(content_type, league, created_at DESC) WHERE content_type = 'sports';
CREATE INDEX content_blocks_cleanup_idx ON content_blocks(expires_at);
```

#### `quote_history`
```sql
CREATE TABLE quote_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  quote_hash TEXT NOT NULL, -- SHA256 of quote content
  quote_content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for deduplication lookups
CREATE INDEX quote_history_user_recent_idx ON quote_history(user_id, created_at DESC);
```

#### `logs`
```sql
CREATE TABLE logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES jobs(job_id) ON DELETE CASCADE,
  event TEXT NOT NULL, -- 'job_created', 'script_started', 'api_call', 'error', etc.
  level TEXT NOT NULL DEFAULT 'info' CHECK (level IN ('debug', 'info', 'warn', 'error')),
  
  -- Structured metadata
  meta JSONB, -- { "function": "worker_generate_script", "api": "openai", "latency_ms": 1500, "user_id_hash": "abc123" }
  
  message TEXT,
  error_details JSONB, -- Stack trace, error codes, etc.
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX logs_job_idx ON logs(job_id, created_at DESC);
CREATE INDEX logs_level_time_idx ON logs(level, created_at DESC) WHERE level IN ('warn', 'error');
CREATE INDEX logs_event_idx ON logs(event, created_at DESC);
```

### Row Level Security (RLS)

```sql
-- Enable RLS on all tables
-- ALTER TABLE user_devices ENABLE ROW LEVEL SECURITY; -- Removed
ALTER TABLE user_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs ENABLE ROW LEVEL SECURITY;

-- User access policies
-- CREATE POLICY "Users can manage their own devices" ON user_devices -- Removed

CREATE POLICY "Users can manage their own schedule" ON user_schedule
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own jobs" ON jobs
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view their quote history" ON quote_history
  FOR ALL USING (auth.uid() = user_id);

-- Service role can access everything (for workers)
CREATE POLICY "Service role full access jobs" ON jobs
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access content" ON content_blocks
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access logs" ON logs
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access quotes" ON quote_history
  FOR ALL TO service_role USING (true);
```

## Supabase Storage

### Buckets

```sql
-- Create private bucket for audio files
INSERT INTO storage.buckets (id, name, public) VALUES ('audio-files', 'audio-files', false);

-- Storage policy - only service role can manage files
CREATE POLICY "Service role can manage audio files" ON storage.objects
  FOR ALL TO service_role USING (bucket_id = 'audio-files');

-- Users can read their own audio files with signed URLs only
-- (Handled via Edge Functions with signed URL generation)
```

### File Naming Convention
```
audio-files/
  └── {yyyy}/
      └── {mm}/
          └── {dd}/
              └── {user_id}/
                  └── {job_id}.m4a
```

## Edge Functions

### 1. Content Fetchers

#### `cron_fetch_news`
```typescript
// Endpoint: POST /functions/v1/cron_fetch_news
// Called by: cron-job.org hourly
// Purpose: Fetch news from NewsAPI + GenNews, store in content_blocks

interface NewsResponse {
  success: boolean;
  articles_processed: number;
  errors: string[];
}
```

#### `cron_fetch_sports`
```typescript
// Endpoint: POST /functions/v1/cron_fetch_sports  
// Called by: cron-job.org hourly
// Purpose: Fetch sports from TheSportsDB + ESPN, store in content_blocks

interface SportsResponse {
  success: boolean;
  events_processed: number;
  leagues: string[];
  errors: string[];
}
```

#### `cron_fetch_stocks`
```typescript
// Endpoint: POST /functions/v1/cron_fetch_stocks
// Called by: cron-job.org hourly  
// Purpose: Fetch market data from Alpha Vantage, store in content_blocks

interface StocksResponse {
  success: boolean;
  symbols_processed: string[];
  market_status: string;
  errors: string[];
}
```

### 2. Job Management

#### `job_upsert_next_run`
```typescript
// Endpoint: POST /functions/v1/job_upsert_next_run
// Called by: iOS app 2 hours before scheduled time
// Purpose: Create or update job with user preferences
// Scheduling: Only creates jobs within 48-hour rolling window

interface JobRequest {
  preferred_name: string;
  location: {
    city: string;
    state: string;
    country: string;
    zip: string;
  };
  weather_current: object;
  weather_forecast: object;
  encouragement_preference: string; // QuotePreference enum
  stock_symbols: string[];
  include_news: boolean;
  include_sports: boolean;
  include_calendar: boolean;
  calendar_events?: string[]; // Today's events if calendar enabled
  desired_voice: string; // "voice1", "voice2", "voice3"
  desired_length: number; // minutes
  scheduled_at: string; // ISO timestamp
  local_date: string; // YYYY-MM-DD
  timezone: string; // IANA timezone
}

interface JobResponse {
  success: boolean;
  job_id: string;
  status: string;
  estimated_ready_time: string;
}
```

**Implementation Logic:**
```typescript
// Validate scheduling is within 48-hour window
const scheduledAt = new Date(request.scheduled_at);
const now = new Date();
const maxScheduleTime = new Date(now.getTime() + (48 * 60 * 60 * 1000));

if (scheduledAt > maxScheduleTime) {
  return { 
    success: false, 
    error: "Cannot schedule beyond 48-hour window" 
  };
}

// Upsert job (create or update existing for same user/date)
const job = await supabase.from('jobs').upsert({
  user_id: user.id,
  local_date: request.local_date,
  scheduled_at: request.scheduled_at,
  window_start: new Date(scheduledAt.getTime() - (2 * 60 * 60 * 1000)), // 2hrs before
  window_end: scheduledAt,
  // ... user preferences
}).select().single();
```

**Example Request:**
```bash
POST https://your-project.supabase.co/functions/v1/job_upsert_next_run

Headers:
{
  "Authorization": "Bearer YOUR_ANON_KEY",
  "Content-Type": "application/json"
}

Body:
{
  "preferred_name": "Sarah",
  "location": {
    "city": "San Francisco", 
    "state": "CA",
    "country": "US",
    "zip": "94102"
  },
  "weather_current": {
    "temperature": 68,
    "condition": "partly_cloudy",
    "humidity": 65
  },
  "weather_forecast": {
    "high": 75,
    "low": 58,
    "precipitation_chance": 10
  },
  "encouragement_preference": "inspirational",
  "stock_symbols": ["AAPL", "TSLA", "SPY"],
  "include_news": true,
  "include_sports": false,
  "include_calendar": true,
  "calendar_events": ["9 AM Team standup", "2 PM Client call"],
  "desired_voice": "voice1",
  "desired_length": 5,
  "scheduled_at": "2024-08-09T07:00:00-07:00",
  "local_date": "2024-08-09",
  "timezone": "America/Los_Angeles"
}
```

**Example Response:**
```json
{
  "success": true,
  "job_id": "job_abc123",
  "status": "queued",
  "estimated_ready_time": "2024-08-09T06:45:00Z"
}
```

### 3. Workers

#### `worker_generate_script`
```typescript
// Endpoint: POST /functions/v1/worker_generate_script
// Called by: Scheduled worker (every 2-5 minutes)
// Purpose: Process queued jobs, generate scripts with GPT-4o

interface ScriptWorkerResponse {
  success: boolean;
  jobs_processed: number;
  jobs_failed: number;
  processing_time_ms: number;
}
```

#### `worker_generate_audio`
```typescript
// Endpoint: POST /functions/v1/worker_generate_audio
// Called by: Scheduled worker (every 2-5 minutes)  
// Purpose: Process script-ready jobs, generate audio with ElevenLabs

interface AudioWorkerResponse {
  success: boolean;
  audio_files_generated: number;
  audio_files_failed: number;
  total_duration_seconds: number;
}
```

### 4. Maintenance

#### `cron_extend_scheduling_window`
```typescript
// REMOVED: No longer needed
// Push notifications are now scheduled locally by the iOS app
// The 48-hour rolling window is maintained automatically by the app
// when it schedules notifications upon opening or schedule changes
```

#### `cron_cleanup_storage`
```typescript
// Endpoint: POST /functions/v1/cron_cleanup_storage
// Called by: cron-job.org daily at 2 AM UTC
// Purpose: Remove audio files older than 3 days (reduced from 7 for 48hr window)

interface CleanupResponse {
  success: boolean;
  files_deleted: number;
  storage_freed_mb: number;
}
```

#### `cron_health_check`
```typescript
// Endpoint: POST /functions/v1/cron_health_check  
// Called by: cron-job.org every 15 minutes
// Purpose: Monitor system health, send alerts via Resend

interface HealthResponse {
  success: boolean;
  system_status: 'healthy' | 'degraded' | 'down';
  alerts_sent: number;
  checks_performed: {
    job_queue_health: boolean;
    content_freshness: boolean;
    error_rate: number;
    worker_performance: boolean;
  };
}
```

### 5. Local Prefetch System (iOS Only)

**Note**: Prefetch notifications are now handled entirely within the iOS app using local `UNNotificationRequest` scheduling. No server-side push infrastructure required.

**iOS Implementation in NotificationScheduler.swift:**
```swift
// Schedule prefetch notification 30 minutes before main notification
private func schedulePrefetchNotification(for date: Date, dayOffset: Int) async {
    let prefetchTime = date.addingTimeInterval(-30 * 60) // 30 minutes before
    
    // Only schedule if prefetch time is in the future
    guard prefetchTime > Date() else { return }
    
    let content = UNMutableNotificationContent()
    content.title = "" // Silent notification
    content.body = ""
    content.sound = nil
    
    // This triggers background app refresh for audio download
    let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: prefetchTime.timeIntervalSinceNow, 
        repeats: false
    )
    
    let identifier = "prefetch_\(dayOffset)"
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    
    try await notificationCenter.add(request)
    DebugLogger.shared.log("Scheduled prefetch notification for \(prefetchTime)", level: .info)
}

// Add to scheduleMainNotification function:
await schedulePrefetchNotification(for: notificationDate, dayOffset: dayOffset)
```

**Background App Refresh (Backup Strategy):**
```swift
// BackgroundAudioFetcher.swift - same as before
class BackgroundAudioFetcher {
    static let shared = BackgroundAudioFetcher()
    
    func scheduleBackgroundChecks(for scheduledTime: Date) {
        let checkTimes = [
            scheduledTime.addingTimeInterval(-20 * 60), // T-20m
            scheduledTime.addingTimeInterval(-10 * 60), // T-10m  
            scheduledTime.addingTimeInterval(-5 * 60)   // T-5m
        ]
        
        for checkTime in checkTimes {
            scheduleBackgroundTask(at: checkTime)
        }
    }
    
    private func scheduleBackgroundTask(at date: Date) {
        let identifier = "audio-check-\(date.timeIntervalSince1970)"
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

### 6. Client API

#### `get_user_audio`
```typescript
// Endpoint: GET /functions/v1/get_user_audio?date=YYYY-MM-DD
// Called by: iOS app when user taps play
// Purpose: Return signed URL for user's audio file

interface AudioResponse {
  success: boolean;
  audio_url?: string; // Signed URL, valid for 30 minutes
  status: 'ready' | 'processing' | 'failed' | 'not_found';
  estimated_ready_time?: string;
  error_message?: string;
}
```

## API Integrations

### Required API Keys
- **OpenAI**: GPT-4o for script generation
- **ElevenLabs**: Voice synthesis  
- **NewsAPI**: Primary news source
- **GenNews**: Backup news source
- **TheSportsDB**: Sports data (free tier)
- **ESPN API**: Additional sports data
- **Alpha Vantage**: Stock market data
- **Resend**: Email alerts for health monitoring

### Rate Limits & Batching
- **GPT-4o**: Batch up to 50 script generations
- **ElevenLabs**: Batch up to 5 audio generations (rate limit concern)
- **News APIs**: Hourly fetches, cache for 12 hours
- **Stock API**: Hourly fetches during market hours, daily otherwise

## Error Handling Strategy

### Retry Logic
- **3 attempts max** with exponential backoff (1s, 4s, 16s)
- **Jittered backoff** to prevent thundering herd
- **Dead letter handling**: Mark as failed after max attempts

### Graceful Degradation
- **Missing news**: Generate script with sports + stocks only
- **Missing sports**: Generate script with news + stocks only  
- **Missing stocks**: Generate script with news + sports only
- **All content missing**: Generate encouragement + weather only
- **GPT-4o failure**: Use fallback template script
- **ElevenLabs failure**: Keep job as `script_ready` for manual retry

### Status Tracking
```
queued → script_processing → script_ready → audio_processing → ready
                   ↓                ↓               ↓
                failed            failed          failed
                   ↓                ↓               ↓
              failed_missed   failed_missed   failed_missed
```

## Security Implementation

### Authentication & Authorization
- **Supabase Auth**: Email, Apple ID, Google Sign-In
- **JWT tokens**: For API authentication from app
- **Service role key**: For worker functions only
- **RLS policies**: Strict user data isolation

### Data Protection  
- **Private storage bucket**: All audio files private
- **Signed URLs**: 30-minute expiration max
- **User data hashing**: Log user_id hashes, not actual IDs
- **API key rotation**: Quarterly rotation schedule

### Privacy Compliance
- **Data retention**: 3 days for audio (aligned with 48hr window), permanent for analytics
- **User deletion**: CASCADE deletes via foreign keys
- **GDPR compliance**: Manual deletion process via Supabase dashboard

## Deployment Strategy

### GitHub Repository Structure
```
daystart-backend/
├── supabase/
│   ├── functions/           # Edge Functions
│   ├── migrations/          # Database schema migrations  
│   └── seed.sql            # Initial data
├── .github/
│   └── workflows/
│       ├── deploy-functions.yml
│       └── deploy-migrations.yml
├── scripts/
│   ├── setup-env.sh
│   └── test-functions.sh
└── README.md
```

### GitHub Actions Workflow
1. **On push to main**: Deploy functions + run migrations
2. **Environment variables**: Stored in GitHub Secrets
3. **Supabase CLI**: Automated deployments
4. **Testing**: Function tests before deployment

### Environment Variables
```bash
# Supabase
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# AI APIs  
OPENAI_API_KEY=
ELEVENLABS_API_KEY=

# Content APIs
NEWSAPI_KEY=
GENNEWS_API_KEY=
ALPHA_VANTAGE_KEY=
ESPN_API_KEY=

# Utilities
RESEND_API_KEY=
HEALTH_CHECK_EMAIL=

# External
CRON_JOB_SECRET= # For webhook authentication
```

## Manual Supabase Setup Steps

### 1. Project Creation
1. Go to [supabase.com](https://supabase.com)
2. Create new project: "daystart-backend"  
3. Choose region closest to primary users
4. Note down Project URL and API keys

### 2. Database Setup
1. Run all table creation SQL from schema section
2. Enable RLS policies
3. Create storage bucket
4. Set up indexes for performance

### 3. Auth Configuration
1. Enable Email auth
2. Enable Apple Sign-In (requires Apple Developer setup)
3. Enable Google Sign-In (requires Google OAuth setup)
4. Configure redirect URLs for iOS app

### 4. Edge Functions Setup
1. Install Supabase CLI locally
2. Link to project: `supabase link --project-ref YOUR_PROJECT_ID`
3. Deploy functions: `supabase functions deploy`

### 5. Storage Configuration
1. Create `audio-files` bucket (private)
2. Set up CORS policies for signed URLs
3. Configure file size limits (50MB max per audio file)

## Cron Job Setup (cron-job.org)

### Content Fetchers (Hourly)
- **URL**: `https://YOUR_PROJECT.supabase.co/functions/v1/cron_fetch_news`
- **Schedule**: `0 * * * *` (every hour)
- **Headers**: `Authorization: Bearer SERVICE_ROLE_KEY`

### Health Check (Every 15 minutes)  
- **URL**: `https://YOUR_PROJECT.supabase.co/functions/v1/cron_health_check`
- **Schedule**: `*/15 * * * *`
- **Headers**: `Authorization: Bearer SERVICE_ROLE_KEY`

### Cleanup (Daily at 2 AM UTC)
- **URL**: `https://YOUR_PROJECT.supabase.co/functions/v1/cron_cleanup_storage`  
- **Schedule**: `0 2 * * *`
- **Headers**: `Authorization: Bearer SERVICE_ROLE_KEY`

## Performance Optimizations

### Database
- **Connection pooling**: Supabase handles automatically
- **Query optimization**: Strategic indexes on job queue lookups
- **Batch operations**: Process multiple jobs per function call

### Content Delivery
- **Regional content caching**: Store content by geographic region
- **Compression**: AAC audio at 96-128kbps for balance of quality/size
- **CDN**: Supabase Storage includes CDN for signed URLs

### Worker Efficiency
- **Batch API calls**: 50 scripts to GPT-4o, 5 audio to ElevenLabs
- **Parallel processing**: Multiple workers can run simultaneously  
- **Smart scheduling**: Prioritize jobs closest to scheduled_at time

## Monitoring & Observability

### Health Checks
- **Job queue depth**: Alert if >100 pending jobs
- **Worker performance**: Alert if avg processing time >5 minutes
- **Error rates**: Alert if >5% failure rate in last hour
- **Content freshness**: Alert if no new content in 2+ hours

### Key Metrics
- **Jobs processed per hour**
- **Average script generation time**  
- **Average audio generation time**
- **User engagement**: Downloads per job created
- **System uptime**: Function availability

### Alerting
- **Email alerts**: Via Resend for critical issues
- **Escalation**: Multiple severity levels
- **Recovery**: Automatic retry mechanisms where possible

## Cost Estimation

### Supabase (10K users/day)
- **Database**: ~$25/month (Pro plan)
- **Storage**: ~$10/month (500GB audio files)
- **Bandwidth**: ~$15/month (file downloads)

### API Costs (10K users/day)
- **OpenAI GPT-4o**: ~$150/month (50K requests)
- **ElevenLabs**: ~$200/month (10K audio generations)  
- **NewsAPI**: $450/month (Business plan)
- **Alpha Vantage**: $50/month (Standard plan)

### **Total Estimated**: ~$900/month for 10K daily active users

## Implementation Timeline

### Phase 1 (Week 1-2): Core Infrastructure
- [ ] Supabase project setup
- [ ] Database schema migration
- [ ] Basic Edge Functions structure  
- [ ] GitHub Actions deployment pipeline

### Phase 2 (Week 2-3): Content Pipeline
- [ ] News/Sports/Stocks fetcher functions
- [ ] Content processing and storage
- [ ] Basic job queue implementation

### Phase 3 (Week 3-4): Job Processing  
- [ ] Script generation worker (GPT-4o integration)
- [ ] Audio generation worker (ElevenLabs integration)
- [ ] Job status tracking and error handling

### Phase 4 (Week 4-5): Client Integration
- [ ] iOS app API integration
- [ ] User authentication flow
- [ ] Audio download and caching

### Phase 5 (Week 5-6): Production Readiness
- [ ] Health monitoring and alerting
- [ ] Performance optimization
- [ ] Security hardening and testing
- [ ] Load testing with simulated users

This comprehensive plan provides a production-ready backend architecture that can scale to thousands of users while maintaining excellent performance and reliability.