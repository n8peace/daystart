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
  skip_tomorrow BOOLEAN DEFAULT FALSE,
  last_scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);
```

#### `user_preferences` (REMOVED - Keep Local)
```sql
-- REMOVED: User preferences stay on iOS device
-- Preferences are sent with each job creation request
-- This eliminates sync complexity and keeps the iOS app as source of truth
-- Only authentication and generated content needs backend storage
```

#### `streak_tracking`
```sql
CREATE TABLE streak_tracking (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Streak data
  same_day_completion_dates DATE[] DEFAULT ARRAY[]::DATE[],
  late_completion_dates DATE[] DEFAULT ARRAY[]::DATE[],
  current_streak INTEGER DEFAULT 0,
  best_streak INTEGER DEFAULT 0,
  
  -- Last update tracking
  last_completed_date DATE,
  last_update_at TIMESTAMPTZ DEFAULT NOW(),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Index for fast lookups
CREATE INDEX streak_tracking_user_idx ON streak_tracking(user_id);
```

#### `daystart_history`
```sql
CREATE TABLE daystart_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id UUID REFERENCES jobs(job_id) ON DELETE SET NULL,
  
  -- DayStart data
  date DATE NOT NULL,
  scheduled_time TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  
  -- Content snapshot
  weather TEXT,
  news TEXT[],
  sports TEXT[],
  stocks TEXT[],
  quote TEXT,
  custom_prompt TEXT,
  transcript TEXT NOT NULL,
  
  -- Audio info
  duration INTEGER NOT NULL, -- seconds
  audio_file_path TEXT, -- Path in storage
  is_deleted BOOLEAN DEFAULT FALSE,
  
  -- Playback tracking
  play_count INTEGER DEFAULT 0,
  last_played_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, date)
);

-- Indexes for performance
CREATE INDEX daystart_history_user_date_idx ON daystart_history(user_id, date DESC);
CREATE INDEX daystart_history_cleanup_idx ON daystart_history(created_at) WHERE is_deleted = FALSE;
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
  
  -- Job processing with priority system
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'script_processing', 'script_ready', 'audio_processing', 'ready', 'failed', 'failed_missed')),
  priority INTEGER DEFAULT 50, -- 100: Welcome/First DayStart, 75: Same-day urgent, 50: Regular, 25: Bulk/background
  attempt_count INTEGER DEFAULT 0,
  worker_id UUID, -- Which worker is processing
  lease_until TIMESTAMPTZ, -- FOR UPDATE SKIP LOCKED leasing
  
  -- DayStart context
  daystart_type TEXT DEFAULT 'regular' CHECK (daystart_type IN ('regular', 'welcome', 'makeup', 'test')),
  is_first_daystart BOOLEAN DEFAULT FALSE,
  day_of_week TEXT, -- 'Monday', 'Tuesday', etc.
  day_date DATE, -- '2025-08-09' for script context
  
  -- User preferences (captured at job creation)
  preferred_name TEXT,
  location_data JSONB, -- { "city": "San Francisco", "state": "CA", "country": "US", "zip": "94102" }
  weather_data JSONB, -- Current and forecast from WeatherKit
  encouragement_preference TEXT,
  stock_symbols TEXT[],
  include_weather BOOLEAN DEFAULT true,
  include_news BOOLEAN DEFAULT true,
  include_sports BOOLEAN DEFAULT true,
  include_stocks BOOLEAN DEFAULT true,
  include_calendar BOOLEAN DEFAULT false,
  include_quotes BOOLEAN DEFAULT true,
  calendar_events TEXT[], -- Today's calendar events if enabled
  desired_voice TEXT NOT NULL,
  desired_length INTEGER NOT NULL, -- minutes
  
  -- Generated content
  script TEXT,
  script_ready_at TIMESTAMPTZ,
  audio_path TEXT, -- Path in Supabase Storage
  audio_ready_at TIMESTAMPTZ,
  
  -- Cost tracking
  script_character_count INTEGER, -- For OpenAI cost calculation
  audio_character_count INTEGER, -- For ElevenLabs cost calculation
  estimated_openai_cost DECIMAL(10,6), -- USD cost for script generation
  estimated_elevenlabs_cost DECIMAL(10,6), -- USD cost for audio generation
  total_estimated_cost DECIMAL(10,6) GENERATED ALWAYS AS (
    COALESCE(estimated_openai_cost, 0) + COALESCE(estimated_elevenlabs_cost, 0)
  ) STORED,
  
  -- Tracking
  downloaded_at TIMESTAMPTZ, -- When app confirmed successful download
  failure_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, local_date) -- One job per user per local day
);

-- Indexes for performance
CREATE INDEX jobs_worker_queue_idx ON jobs(priority DESC, status, scheduled_at) WHERE status IN ('queued', 'script_ready');
CREATE INDEX jobs_user_date_idx ON jobs(user_id, local_date);
CREATE INDEX jobs_cleanup_idx ON jobs(audio_ready_at) WHERE audio_path IS NOT NULL;
CREATE INDEX jobs_priority_created_idx ON jobs(priority DESC, created_at ASC);
CREATE INDEX jobs_cost_tracking_idx ON jobs(created_at, total_estimated_cost) WHERE total_estimated_cost IS NOT NULL;
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
-- ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY; -- REMOVED
ALTER TABLE streak_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE daystart_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs ENABLE ROW LEVEL SECURITY;

-- User access policies
-- CREATE POLICY "Users can manage their own devices" ON user_devices -- Removed

CREATE POLICY "Users can manage their own schedule" ON user_schedule
  FOR ALL USING (auth.uid() = user_id);

-- CREATE POLICY "Users can manage their own preferences" ON user_preferences -- REMOVED

CREATE POLICY "Users can manage their own streaks" ON streak_tracking
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own daystart history" ON daystart_history
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

-- CREATE POLICY "Service role full access preferences" ON user_preferences -- REMOVED

CREATE POLICY "Service role full access streaks" ON streak_tracking
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access history" ON daystart_history
  FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access schedule" ON user_schedule
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
// Called by: iOS app 2 hours before scheduled time OR immediately for welcome DayStart
// Purpose: Create or update job with user preferences
// Scheduling: Only creates jobs within 48-hour rolling window (except welcome DayStart)

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
  include_weather: boolean;
  include_news: boolean;
  include_sports: boolean;
  include_stocks: boolean;
  include_calendar: boolean;
  include_quotes: boolean;
  calendar_events?: string[]; // Today's events if calendar enabled
  desired_voice: string; // "grace", "rachel", "matthew"
  desired_length: number; // minutes
  scheduled_at: string; // ISO timestamp
  local_date: string; // YYYY-MM-DD
  timezone: string; // IANA timezone
  
  // New fields for enhanced context
  daystart_type?: 'regular' | 'welcome' | 'makeup' | 'test'; // Default: 'regular'
  is_first_daystart?: boolean; // Default: false
  priority?: number; // Default: 50, Welcome: 100
  day_context: {
    day_of_week: string; // 'Monday', 'Tuesday', etc.
    date: string; // '2025-08-09'
    is_today: boolean;
    is_tomorrow: boolean;
  };
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

**Example Request (Regular DayStart):**
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
  "timezone": "America/Los_Angeles",
  "day_context": {
    "day_of_week": "Friday",
    "date": "2024-08-09",
    "is_today": false,
    "is_tomorrow": true
  }
}
```

**Example Request (Welcome DayStart):**
```bash
POST https://your-project.supabase.co/functions/v1/job_upsert_next_run

Body:
{
  "preferred_name": "Sarah",
  "location": { /* ... */ },
  "weather_current": { /* ... */ },
  "weather_forecast": { /* ... */ },
  "encouragement_preference": "inspirational",
  "stock_symbols": ["AAPL", "TSLA", "SPY"],
  "include_news": true,
  "include_sports": true,
  "include_calendar": false,
  "desired_voice": "voice1",
  "desired_length": 5,
  "scheduled_at": "2024-08-09T10:15:00-07:00", // +10 minutes from onboarding
  "local_date": "2024-08-09",
  "timezone": "America/Los_Angeles",
  
  // Welcome DayStart specific fields
  "daystart_type": "welcome",
  "is_first_daystart": true,
  "priority": 100,
  "day_context": {
    "day_of_week": "Friday",
    "date": "2024-08-09",
    "is_today": true,
    "is_tomorrow": false
  }
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
  total_cost: number; // Total OpenAI costs for this batch
  average_cost_per_job: number;
}

// Implementation includes cost tracking:
// 1. After successful OpenAI API call, calculate cost based on token usage
// 2. Call calculate_job_costs function to store cost data
// 3. Update job record with script_character_count and estimated_openai_cost
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
  total_cost: number; // Total ElevenLabs costs for this batch
  average_cost_per_audio: number;
}

// Implementation includes cost tracking:
// 1. Count characters in script before sending to ElevenLabs
// 2. After successful ElevenLabs API call, calculate cost based on character count
// 3. Call calculate_job_costs function to store cost data
// 4. Update job record with audio_character_count and estimated_elevenlabs_cost
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

#### `calculate_job_costs`
```typescript
// Endpoint: POST /functions/v1/calculate_job_costs
// Called by: Script and audio generation workers after API calls
// Purpose: Calculate and store cost estimates for COGS tracking

interface CostCalculationRequest {
  job_id: string;
  script_text?: string; // For OpenAI cost calculation
  audio_character_count?: number; // For ElevenLabs cost calculation
  voice_model?: string; // ElevenLabs voice model used
}

interface CostCalculationResponse {
  success: boolean;
  costs: {
    openai_cost: number;
    elevenlabs_cost: number;
    total_cost: number;
  };
  updated_at: string;
}

// Cost calculation logic
const OPENAI_GPT4_COST_PER_1K_TOKENS = 0.03; // Input tokens
const OPENAI_GPT4_OUTPUT_COST_PER_1K_TOKENS = 0.06; // Output tokens

// ElevenLabs pricing (as of 2024)
const ELEVENLABS_COST_PER_1K_CHARS = {
  'starter': 0.18, // $0.18 per 1K characters
  'creator': 0.18,
  'pro': 0.18,
  'scale': 0.18,
  'business': 0.16
};

function calculateOpenAICost(inputText: string, outputText: string): number {
  const inputTokens = estimateTokenCount(inputText);
  const outputTokens = estimateTokenCount(outputText);
  
  const inputCost = (inputTokens / 1000) * OPENAI_GPT4_COST_PER_1K_TOKENS;
  const outputCost = (outputTokens / 1000) * OPENAI_GPT4_OUTPUT_COST_PER_1K_TOKENS;
  
  return inputCost + outputCost;
}

function calculateElevenLabsCost(characterCount: number, plan: string = 'starter'): number {
  const costPer1K = ELEVENLABS_COST_PER_1K_CHARS[plan] || ELEVENLABS_COST_PER_1K_CHARS.starter;
  return (characterCount / 1000) * costPer1K;
}

function estimateTokenCount(text: string): number {
  // Rough estimation: ~4 characters per token for English text
  return Math.ceil(text.length / 4);
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

#### `update_user_preferences` (REMOVED - Keep Local)
```typescript
// REMOVED: User preferences stay on iOS device
// No need for separate preferences API - all preferences sent with job creation
// This simplifies the architecture and eliminates sync issues
```

#### `update_user_schedule`
```typescript
// Endpoint: POST /functions/v1/update_user_schedule
// Called by: iOS app when user changes schedule
// Purpose: Update wake time and repeat days

interface ScheduleRequest {
  wake_time_local: string; // "HH:MM" format
  repeat_days: number[]; // [1-7] where 1=Sunday
  timezone: string; // IANA timezone
  skip_tomorrow?: boolean;
}

interface ScheduleResponse {
  success: boolean;
  updated_at: string;
  next_scheduled_date?: string;
}
```

#### `get_daystart_history`
```typescript
// Endpoint: GET /functions/v1/get_daystart_history?limit=10&offset=0
// Called by: iOS app history view
// Purpose: Get paginated history of completed DayStarts

interface HistoryResponse {
  success: boolean;
  dayStarts: DayStartHistoryItem[];
  total_count: number;
  has_more: boolean;
}

interface DayStartHistoryItem {
  id: string;
  date: string;
  scheduled_time?: string;
  weather: string;
  news: string[];
  sports: string[];
  stocks: string[];
  quote: string;
  transcript: string;
  duration: number;
  audio_url?: string; // Signed URL if audio exists
  is_deleted: boolean;
}
```

#### `update_streak_tracking`
```typescript
// Endpoint: POST /functions/v1/update_streak_tracking
// Called by: iOS app when DayStart is played
// Purpose: Update streak data

interface StreakUpdateRequest {
  date: string; // YYYY-MM-DD
  completed_at: string; // ISO timestamp
  is_same_day: boolean; // Whether completed on scheduled day
}

interface StreakUpdateResponse {
  success: boolean;
  current_streak: number;
  best_streak: number;
  status: 'same_day' | 'late' | 'already_completed';
}
```

#### `mark_audio_downloaded`
```typescript
// Endpoint: POST /functions/v1/mark_audio_downloaded
// Called by: iOS app after successful prefetch/download
// Purpose: Track successful downloads for analytics

interface DownloadRequest {
  job_id: string;
  downloaded_at: string; // ISO timestamp
}

interface DownloadResponse {
  success: boolean;
}
```

#### `get_cost_analytics`
```typescript
// Endpoint: GET /functions/v1/get_cost_analytics?period=daily&start_date=2024-01-01&end_date=2024-01-31
// Called by: Admin dashboard or monitoring tools
// Purpose: Retrieve cost analytics for COGS monitoring

interface CostAnalyticsResponse {
  success: boolean;
  period: 'daily' | 'weekly' | 'monthly';
  date_range: {
    start: string;
    end: string;
  };
  summary: {
    total_jobs: number;
    total_cost: number;
    average_cost_per_job: number;
    openai_cost: number;
    elevenlabs_cost: number;
  };
  breakdown: {
    date: string;
    jobs_count: number;
    total_cost: number;
    openai_cost: number;
    elevenlabs_cost: number;
    average_script_length: number;
    average_audio_length: number;
  }[];
  cost_per_user_metrics: {
    average_monthly_cost_per_user: number;
    median_monthly_cost_per_user: number;
    high_usage_users: number; // Users above 90th percentile
  };
}
```

## API Integrations

### Required API Keys
- **OpenAI**: GPT-4o for script generation
- **ElevenLabs**: Voice synthesis  
- **Yahoo Finance RapidAPI**: Primary stock market data (replaces Alpha Vantage)
- **NewsAPI**: Primary news source
- **GenNews**: Backup news source
- **TheSportsDB**: Sports data (free tier)
- **ESPN API**: Additional sports data
- **Resend**: Email alerts for health monitoring

### Rate Limits & Batching
- **GPT-4o**: Batch up to 50 script generations
- **ElevenLabs**: Batch up to 5 audio generations (rate limit concern)
- **Yahoo Finance RapidAPI**: 500 requests/month on free tier, upgrade to higher limits
- **News APIs**: Hourly fetches, cache for 12 hours
- **Stock API**: Real-time market data during market hours, cached otherwise

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

### Privacy Compliance & Enhanced Security

#### GDPR/Privacy Compliance
- **Data Minimization**: Only store essential data for functionality (no user preferences server-side)
- **Data Retention Policies**:
  - Audio files: 3 days (aligned with 48hr window + 24hr grace period)
  - User history: 30 days for active engagement, archived after 90 days
  - Analytics data: Aggregated only, no personally identifiable information
  - Logs: 7 days for debugging, automatically purged
- **User Rights**:
  - **Right to Access**: API endpoint to export all user data
  - **Right to Deletion**: Cascade deletes via foreign keys + manual cleanup process
  - **Right to Rectification**: User can update schedule and delete history items
  - **Data Portability**: JSON export format for all user data

#### Enhanced Data Protection
```sql
-- Add data retention policies
CREATE OR REPLACE FUNCTION cleanup_expired_data()
RETURNS void AS $$
BEGIN
  -- Delete old audio files (3 days)
  DELETE FROM jobs 
  WHERE audio_ready_at < NOW() - INTERVAL '3 days' 
  AND audio_path IS NOT NULL;
  
  -- Archive old history (30 days active, 90 days total)
  UPDATE daystart_history 
  SET is_deleted = true 
  WHERE created_at < NOW() - INTERVAL '90 days';
  
  -- Purge old logs (7 days)
  DELETE FROM logs 
  WHERE created_at < NOW() - INTERVAL '7 days';
  
  -- Clean expired content blocks (12 hours)
  DELETE FROM content_blocks 
  WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Schedule cleanup function
SELECT cron.schedule('cleanup-expired-data', '0 2 * * *', 'SELECT cleanup_expired_data();');
```

#### User Data Export (GDPR Article 15)
```typescript
// get_user_data_export
interface DataExportResponse {
  user_id: string;
  export_date: string;
  schedule: UserScheduleData;
  history: DayStartHistoryItem[];
  streak_data: StreakData;
  preferences_note: "Preferences stored locally on device only";
}
```

#### User Data Deletion (GDPR Article 17)
```typescript
// delete_user_account
async function deleteUserAccount(userId: string): Promise<void> {
  // 1. Delete all user data (cascade handles most)
  await supabase.from('user_schedule').delete().eq('user_id', userId);
  
  // 2. Remove audio files from storage
  const { data: jobs } = await supabase
    .from('jobs')
    .select('audio_path')
    .eq('user_id', userId);
    
  for (const job of jobs) {
    if (job.audio_path) {
      await supabase.storage.from('audio-files').remove([job.audio_path]);
    }
  }
  
  // 3. Delete auth user (triggers CASCADE deletes)
  await supabase.auth.admin.deleteUser(userId);
  
  // 4. Log deletion for compliance
  await supabase.from('logs').insert({
    event: 'user_deleted',
    level: 'info',
    message: `User account deleted: ${userId}`,
    meta: { compliance: 'gdpr_article_17', timestamp: new Date().toISOString() }
  });
}
```

#### Additional Security Measures
- **API Rate Limiting**: Implement per-user rate limits to prevent abuse
- **Request Signing**: HMAC signatures for critical API endpoints
- **Audit Logging**: All data modifications logged with timestamps
- **Data Encryption**: All sensitive fields encrypted at rest
- **Network Security**: HTTPS only, HSTS headers, CSP policies

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

### GitHub Actions Workflow & Deployment Safety

#### Multi-Environment Deployment Pipeline
```yaml
# .github/workflows/deploy-backend.yml
name: Deploy Backend
on:
  push:
    branches: [develop, staging, main]
    paths: ['supabase/**']

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Test Edge Functions
        run: |
          # Unit tests for Edge Functions
          deno test supabase/functions/
      
  deploy-develop:
    if: github.ref == 'refs/heads/develop'
    needs: test
    runs-on: ubuntu-latest
    environment: develop
    steps:
      - uses: actions/checkout@v3
      - uses: supabase/setup-cli@v1
      - name: Deploy to Development
        run: |
          supabase link --project-ref ${{ secrets.SUPABASE_DEV_PROJECT_REF }}
          supabase db push --dry-run  # Validate migrations first
          supabase db push
          supabase functions deploy
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
  
  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    needs: test
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v3
      - uses: supabase/setup-cli@v1
      - name: Deploy to Staging
        run: |
          supabase link --project-ref ${{ secrets.SUPABASE_STAGING_PROJECT_REF }}
          supabase db push --dry-run
          supabase db push
          supabase functions deploy
          
          # Run health checks
          curl -f "${{ secrets.STAGING_HEALTH_CHECK_URL }}" || exit 1
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          
  deploy-production:
    if: github.ref == 'refs/heads/main'
    needs: test
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v3
      - uses: supabase/setup-cli@v1
      - name: Deploy to Production
        run: |
          supabase link --project-ref ${{ secrets.SUPABASE_PROD_PROJECT_REF }}
          
          # Create backup before deployment
          pg_dump ${{ secrets.PROD_DATABASE_URL }} > backup_$(date +%Y%m%d_%H%M%S).sql
          
          supabase db push --dry-run
          supabase db push
          supabase functions deploy
          
          # Comprehensive health checks
          ./scripts/production-health-check.sh
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

#### Rollback Procedures
```bash
#!/bin/bash
# scripts/rollback.sh

ENVIRONMENT=$1
BACKUP_TIMESTAMP=$2

if [ "$ENVIRONMENT" = "production" ]; then
    echo "Rolling back production to backup: $BACKUP_TIMESTAMP"
    
    # 1. Restore database from backup
    psql $PROD_DATABASE_URL < backup_${BACKUP_TIMESTAMP}.sql
    
    # 2. Redeploy previous function versions
    git checkout HEAD~1 -- supabase/functions/
    supabase functions deploy
    
    # 3. Update DNS to maintenance page if needed
    # curl -X POST "$CLOUDFLARE_API/maintenance-mode/enable"
    
    echo "Rollback completed. Run health checks."
fi
```

#### Health Check Endpoints
```typescript
// supabase/functions/health-check/index.ts
export async function handler() {
  const checks = {
    database: await checkDatabase(),
    jobQueue: await checkJobQueue(),
    externalAPIs: await checkExternalAPIs(),
    storage: await checkStorage()
  };
  
  const allHealthy = Object.values(checks).every(check => check.healthy);
  
  return new Response(JSON.stringify({
    status: allHealthy ? 'healthy' : 'unhealthy',
    timestamp: new Date().toISOString(),
    checks
  }), {
    status: allHealthy ? 200 : 503,
    headers: { 'Content-Type': 'application/json' }
  });
}

async function checkJobQueue() {
  const { data, error } = await supabase
    .from('jobs')
    .select('status')
    .in('status', ['queued', 'script_processing', 'audio_processing']);
    
  const queueDepth = data?.length || 0;
  
  return {
    healthy: queueDepth < 100 && !error,
    queueDepth,
    error: error?.message
  };
}
```

#### Staged Deployment Strategy
1. **Development**: Automatic deployment from `develop` branch
2. **Staging**: Manual promotion from develop, runs integration tests
3. **Production**: Manual promotion from staging, includes:
   - Database backup creation
   - Canary deployment (10% traffic initially)
   - Full health check suite
   - Gradual traffic increase (10% → 50% → 100%)
   - Automatic rollback on failure

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

### API Costs (10K users/day) - With Cost Tracking
- **OpenAI GPT-4o**: ~$150/month (50K requests)
  - Tracked via: `script_character_count` and `estimated_openai_cost`
  - Real-time cost calculation based on input/output tokens
- **ElevenLabs**: ~$200/month (10K audio generations)
  - Tracked via: `audio_character_count` and `estimated_elevenlabs_cost`
  - Cost calculated per character based on subscription plan
- **NewsAPI**: $450/month (Business plan)
- **Yahoo Finance RapidAPI**: $25/month (Pro plan) - significantly cheaper than Alpha Vantage

### **Total Estimated**: ~$875/month for 10K daily active users (reduced by $25 with Yahoo Finance API)

### Cost Monitoring Benefits
- **Real-time COGS tracking**: Know exact per-user generation costs
- **Usage optimization**: Identify high-cost users or content patterns
- **Budget alerts**: Set spending limits and get notifications
- **Pricing strategy**: Data-driven pricing based on actual costs
- **A/B testing**: Compare cost impact of different content lengths or features

## iOS App Integration

### Authentication Setup
The iOS app currently uses local UserDefaults for data storage. Backend integration will require:

1. **Supabase Auth SDK Integration**
   ```swift
   import Supabase
   
   let supabase = SupabaseClient(
     supabaseURL: URL(string: "YOUR_SUPABASE_URL")!,
     supabaseKey: "YOUR_ANON_KEY"
   )
   ```

2. **Data Architecture Decision**
   - **Keep user preferences LOCAL** on iOS device (simpler!)
   - Only migrate DayStart history to backend
   - Only migrate streak data to server  
   - No preferences sync needed - sent with each job request

3. **API Service Layer**
   ```swift
   class DayStartAPIService {
     static let shared = DayStartAPIService()
     
     func createJob(request: JobRequest) async throws -> JobResponse
     func getUserAudio(date: Date) async throws -> AudioResponse
     // No updatePreferences needed - preferences stay local
     func updateSchedule(_ schedule: ScheduleRequest) async throws
     func getHistory(limit: Int, offset: Int) async throws -> HistoryResponse
     func updateStreak(_ update: StreakUpdateRequest) async throws
   }
   ```

### Data Sync Strategy & Offline-First Architecture

#### Core Principle: App Works Offline Always
The iOS app is designed to function completely offline, with backend integration adding enhanced personalization rather than replacing core functionality.

#### Offline-First Implementation:
1. **Local Data Persistence**: All user preferences, schedules, and history remain stored locally in UserDefaults/CoreData
2. **Mock Data Fallback**: If backend is unavailable, app seamlessly falls back to existing mock data service
3. **Background Sync**: When available, upload changes and sync additional data (streaks, enhanced history)
4. **Graceful Degradation Scenarios**:
   - **Backend Completely Down**: App continues with mock data, all features functional
   - **Slow Network**: Local notifications and scheduling continue, backend sync queued for later
   - **Auth Failure**: App reverts to local-only mode, no feature loss
   - **Partial API Failure**: Missing stock data doesn't prevent news/weather DayStart generation

#### Conflict Resolution Strategy:
1. **User Preferences**: iOS app is always source of truth (no server sync needed)
2. **Schedule Changes**: Local changes take precedence, server only provides job creation
3. **History Data**: Server provides enhanced data, local provides fallback
4. **Streak Data**: Server is source of truth (but app calculates locally as backup)

### Audio Prefetch Integration
The iOS app already has sophisticated prefetch logic. Backend integration:

1. **Job Creation**: Call `job_upsert_next_run` 2 hours before scheduled time
2. **Status Polling**: Check job status via `get_user_audio` endpoint
3. **Download**: Use signed URLs to download audio files
4. **Caching**: Store in iOS app's Documents directory
5. **Cleanup**: Remove old files after 7 days

### Voice Selection Mapping
iOS app uses different voice names than ElevenLabs:

```typescript
// Voice mapping in backend
const VOICE_MAPPING = {
  'grace': 'ELEVENLABS_VOICE_ID_1',
  'rachel': 'ELEVENLABS_VOICE_ID_2', 
  'matthew': 'ELEVENLABS_VOICE_ID_3'
};
```

### Stock Symbol Validation
The iOS app's updated stock validation supports crypto and longer symbols:

```swift
// iOS validation (already implemented)
static func isValidStockSymbol(_ symbol: String) -> Bool {
  let trimmed = symbol.trimmingCharacters(in: .whitespaces).uppercased()
  let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-.$"))
  return trimmed.count >= 1 && 
         trimmed.count <= 10 && 
         trimmed.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
}
```

Backend should use similar validation in API endpoints.

### Error Handling & Retry Logic
iOS app should implement exponential backoff for API calls:

```swift
class APIRetryManager {
  func retryWithBackoff<T>(
    maxAttempts: Int = 3,
    operation: @escaping () async throws -> T
  ) async throws -> T {
    // Implement exponential backoff with jitter
  }
}
```

### Notification Integration
The iOS app handles notifications locally. Backend should:
1. Not send push notifications (iOS handles scheduling)
2. Provide job status API for iOS to check readiness
3. Support immediate job creation for Welcome DayStarts

### Development Phases

#### Phase 1: Backend Setup (No iOS Changes)
- Set up Supabase project and database
- Implement Edge Functions for job processing
- Test with Postman/curl

#### Phase 2: iOS Integration Layer
- Add Supabase SDK to iOS project
- Create API service layer
- Implement authentication flow

#### Phase 3: Feature Migration
- **Keep user preferences on iOS** (no migration needed!)
- Implement job creation API calls with preferences payload
- Add audio download logic

#### Phase 4: Data Sync & Polish
- Implement history sync
- Add streak tracking sync
- Performance optimization

## Key Implementation Recommendations

### **IMPORTANT: iOS App Status**

The **current iOS app requires NO changes** until Phase 4 (Client Integration). The app is fully functional with:
- ✅ Complete scheduling and notification system
- ✅ Audio playback with pause/resume functionality
- ✅ User preferences and history management
- ✅ Mock data that provides realistic experience
- ✅ Offline-first architecture ready for backend integration

**Backend development can proceed independently** while iOS app remains unchanged.

### Background Task Integration (Critical for "Personalized Audio on Time")

When implementing Phase 4, the iOS app will need **BGTaskScheduler** implementation for reliable background audio preparation:

#### 1. Background App Refresh Setup
```swift
// AppDelegate.swift or App.swift
import BackgroundTasks

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Register background task identifier
    BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.daystart.audio-prep", using: nil) { task in
        handleAudioPreparationTask(task as! BGAppRefreshTask)
    }
    return true
}

func handleAudioPreparationTask(_ task: BGAppRefreshTask) {
    task.expirationHandler = {
        task.setTaskCompleted(success: false)
    }
    
    Task {
        let success = await downloadPendingAudio()
        task.setTaskCompleted(success: success)
        
        // Schedule next background task
        scheduleAudioPreparationTask()
    }
}

func scheduleAudioPreparationTask() {
    let request = BGAppRefreshTaskRequest(identifier: "com.daystart.audio-prep")
    
    // Schedule 30 minutes before next DayStart
    if let nextDayStartTime = UserPreferences.shared.schedule.nextOccurrence {
        request.earliestBeginDate = nextDayStartTime.addingTimeInterval(-30 * 60)
    }
    
    try? BGTaskScheduler.shared.submit(request)
}
```

#### 2. Network Download Logic
```swift
class AudioDownloadManager {
    static let shared = AudioDownloadManager()
    
    func downloadPendingAudio() async -> Bool {
        guard let nextOccurrence = UserPreferences.shared.schedule.nextOccurrence else { return false }
        
        // Check if audio is already cached locally
        let cacheKey = "daystart_\(nextOccurrence.iso8601String)"
        if AudioCache.shared.hasAudio(for: cacheKey) { return true }
        
        do {
            // Call backend API to get signed URL
            let response = try await DayStartAPIService.shared.getUserAudio(date: nextOccurrence)
            
            guard response.status == "ready", let audioURL = response.audio_url else {
                // Audio not ready yet, will retry on next background task
                return false
            }
            
            // Download and cache audio file
            let audioData = try await URLSession.shared.data(from: URL(string: audioURL)!)
            AudioCache.shared.store(audioData.0, for: cacheKey)
            
            return true
        } catch {
            DebugLogger.shared.logError(error, context: "Background audio download failed")
            return false
        }
    }
}
```

### Deployment Strategy (Develop-Only)

Based on the assessment, implement **develop branch-only deployments** to minimize production risk during integration:

#### GitHub Actions Workflow
```yaml
# .github/workflows/deploy-backend.yml
name: Deploy Backend
on:
  push:
    branches: [develop]  # Only deploy from develop branch
    paths: ['supabase/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: develop  # Use develop environment secrets
    steps:
      - uses: actions/checkout@v3
      - uses: supabase/setup-cli@v1
      - name: Deploy to Develop Environment
        run: |
          supabase link --project-ref ${{ secrets.SUPABASE_DEV_PROJECT_REF }}
          supabase db push
          supabase functions deploy
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

### Repository Migration Plan

The assessment mentions "repo migrations 2,3,4" - here's the recommended approach:

#### Migration 1: API Integration Layer (No Supabase yet)
- Add Yahoo Finance RapidAPI integration to replace mock stock data
- Keep all data local, only fetch real-time stock prices
- Test API reliability and rate limits

#### Migration 2: Backend Infrastructure Setup
- Set up Supabase develop environment
- Deploy Edge Functions and database schema
- Test job processing pipeline with synthetic data

#### Migration 3: iOS Background Tasks
- Implement BGTaskScheduler for audio preparation
- Add network download logic for audio files
- Test background execution reliability

#### Migration 4: Full Integration
- Connect iOS app to Supabase backend
- Migrate from mock data to real personalized content
- Implement fallback mechanisms for offline operation

### Yahoo Finance RapidAPI Integration Specifics

#### API Response Format
```json
{
  "body": [
    {
      "symbol": "AAPL",
      "shortName": "Apple Inc.",
      "regularMarketPrice": 150.25,
      "regularMarketChange": 2.15,
      "regularMarketChangePercent": 1.45,
      "regularMarketVolume": 45234567,
      "marketCap": 2456789012345,
      "fiftyTwoWeekLow": 124.17,
      "fiftyTwoWeekHigh": 182.94
    }
  ]
}
```

#### iOS Implementation (Phase 4)
```swift
// YahooFinanceService.swift
class YahooFinanceService {
    private let rapidAPIKey = Config.yahooFinanceAPIKey
    private let baseURL = "https://yahoo-finance15.p.rapidapi.com"
    private let cache = StockQuoteCache()
    
    func fetchQuotes(symbols: [String]) async throws -> [StockQuote] {
        // Check cache first (5-minute expiry during market hours)
        if let cachedQuotes = cache.getQuotes(for: symbols) {
            return cachedQuotes
        }
        
        let symbolsString = symbols.joined(separator: ",")
        let url = URL(string: "\(baseURL)/api/yahoo/qu/quote/\(symbolsString)")!
        
        var request = URLRequest(url: url)
        request.setValue(rapidAPIKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue("yahoo-finance15.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        let apiResponse = try JSONDecoder().decode(YahooFinanceResponse.self, from: data)
        let quotes = apiResponse.body.map { quote in
            StockQuote(
                symbol: quote.symbol,
                name: quote.shortName,
                price: quote.regularMarketPrice,
                change: quote.regularMarketChange,
                changePercent: quote.regularMarketChangePercent,
                volume: quote.regularMarketVolume,
                marketCap: quote.marketCap
            )
        }
        
        // Cache results
        cache.store(quotes: quotes)
        
        return quotes
    }
}

// Error handling
enum APIError: Error, LocalizedError {
    case invalidResponse
    case rateLimited
    case serverError(Int)
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkUnavailable:
            return "Network unavailable"
        default:
            return "API request failed"
        }
    }
}

// Caching strategy
class StockQuoteCache {
    private var cache: [String: (quotes: [StockQuote], timestamp: Date)] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes
    
    func getQuotes(for symbols: [String]) -> [StockQuote]? {
        let key = symbols.sorted().joined()
        guard let cached = cache[key],
              Date().timeIntervalSince(cached.timestamp) < cacheExpiry else {
            return nil
        }
        return cached.quotes
    }
    
    func store(quotes: [StockQuote]) {
        let symbols = quotes.map { $0.symbol }.sorted()
        let key = symbols.joined()
        cache[key] = (quotes: quotes, timestamp: Date())
    }
}
```

#### Fallback Strategy
```swift
// Integration with existing MockDataService
extension MockDataService {
    func fetchStockData(for symbols: [String]) async -> [String] {
        do {
            let quotes = try await YahooFinanceService().fetchQuotes(symbols: symbols)
            return quotes.map { quote in
                let changeDirection = quote.change >= 0 ? "📈" : "📉"
                let changePercent = String(format: "%.2f%%", abs(quote.changePercent))
                return "\(quote.symbol): $\(String(format: "%.2f", quote.price)) \(changeDirection) \(changePercent)"
            }
        } catch {
            DebugLogger.shared.logError(error, context: "Yahoo Finance API failed, using mock data")
            // Fallback to existing mock stock data
            return generateMockStockData(for: symbols)
        }
    }
}
```

### Environment Configuration Details

#### iOS App Configuration (Phase 4 Only)

**Info.plist Setup:**
```xml
<!-- DayStart-Info.plist -->
<dict>
    <key>YAHOO_FINANCE_API_KEY</key>
    <string>$(YAHOO_FINANCE_API_KEY)</string>
    <key>SUPABASE_URL</key>
    <string>$(SUPABASE_URL)</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>$(SUPABASE_ANON_KEY)</string>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.daystart.audio-prep</string>
    </array>
</dict>
```

**Config.swift:**
```swift
enum Config {
    static let yahooFinanceAPIKey = Bundle.main.infoDictionary?["YAHOO_FINANCE_API_KEY"] as? String ?? ""
    static let supabaseURL = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
    static let supabaseAnonKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
    
    #if DEBUG
    static let isDevelopment = true
    #else
    static let isDevelopment = false
    #endif
}
```

**Xcode Build Configuration:**
```bash
# Development.xcconfig
YAHOO_FINANCE_API_KEY = your_dev_api_key_here
SUPABASE_URL = https://your-dev-project.supabase.co
SUPABASE_ANON_KEY = your_dev_anon_key_here

# Production.xcconfig  
YAHOO_FINANCE_API_KEY = your_prod_api_key_here
SUPABASE_URL = https://your-prod-project.supabase.co
SUPABASE_ANON_KEY = your_prod_anon_key_here
```

**Security - .gitignore additions:**
```gitignore
# API Keys and Environment Files
*.xcconfig
Config/Keys.plist
DayStart-Info-Keys.plist

# Development only
.env
.env.local
.env.development
```

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