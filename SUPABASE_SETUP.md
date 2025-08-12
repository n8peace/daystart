# DayStart Supabase Backend Setup

Complete setup guide for the DayStart backend infrastructure supporting instant audio streaming and offline replay.

## 📋 Prerequisites

- Supabase account
- OpenAI API key (for content generation)
- ElevenLabs API key (for text-to-speech)
- GitHub repository access
- Supabase CLI installed locally

## 🚀 Quick Setup

### 1. Create Supabase Project

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Click "New Project" 
3. Choose organization and name: `daystart-backend`
4. Set database password (save securely)
5. Choose region closest to your users
6. Wait for project initialization (~5 minutes)

### 2. Configure Database

```bash
# Install Supabase CLI
npm install -g supabase

# Login to Supabase
supabase login

# Link your project (get PROJECT_REF from dashboard URL)
supabase link --project-ref YOUR_PROJECT_REF

# Run initial migration
supabase db push
```

### 3. Set Up Storage

1. Go to Storage in Supabase Dashboard
2. Create new bucket: `daystart-audio`
3. Set as **Private** (no public access)
4. File size limit: 50MB
5. Allowed MIME types: `audio/mpeg, audio/mp4, audio/wav`

### 4. Deploy Edge Functions

```bash
# Deploy all functions
supabase functions deploy --no-verify-jwt

# Set environment secrets
supabase secrets set OPENAI_API_KEY="your-openai-key"
supabase secrets set ELEVENLABS_API_KEY="your-elevenlabs-key"  
supabase secrets set WORKER_AUTH_TOKEN="$(openssl rand -base64 32)"
```

### 5. Configure iOS App

Update your `Info.plist`:

```xml
<key>SupabaseBaseURL</key>
<string>https://YOUR_PROJECT_REF.supabase.co/functions/v1</string>
<key>SupabaseAnonKey</key>
<string>YOUR_ANON_KEY</string>
```

Get your keys from: **Settings → API** in Supabase Dashboard

## 🔧 Detailed Configuration

### Database Schema

The migration creates these main tables:

- **`jobs`** - Job queue for DayStart generation
- **`daystart_history`** - Completed DayStarts for replay  
- **`request_logs`** - API analytics and rate limiting

### API Endpoints

#### POST /create_job
Creates a new DayStart generation job.

**Request:**
```json
{
  "local_date": "2025-08-12",
  "scheduled_at": "2025-08-12T07:00:00Z", 
  "preferred_name": "Alex",
  "include_weather": true,
  "include_news": true,
  "include_sports": false,
  "include_stocks": true,
  "stock_symbols": ["AAPL", "GOOGL"],
  "include_calendar": false,
  "include_quotes": true,
  "quote_preference": "motivational",
  "voice_option": "voice1",
  "daystart_length": 180,
  "timezone": "America/New_York"
}
```

**Response:**
```json
{
  "success": true,
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "estimated_ready_time": "2025-08-12T06:58:00Z",
  "request_id": "req-123"
}
```

#### GET /get_audio_status?date=YYYY-MM-DD
Returns status and signed URL for audio.

**Response:**
```json
{
  "success": true,
  "status": "ready",
  "job_id": "550e8400-e29b-41d4-a716-446655440000", 
  "audio_url": "https://storage.supabase.co/...",
  "duration": 185,
  "transcript": "Good morning Alex...",
  "request_id": "req-456"
}
```

### Job Processing

Jobs are processed by the `process_jobs` worker function:

1. **Script Generation**: Uses GPT-4 to create personalized content
2. **Audio Generation**: ElevenLabs text-to-speech conversion  
3. **Storage**: Upload to private bucket with signed URL access
4. **Status Update**: Mark job as ready for iOS streaming

### Security

- **Anonymous Authentication**: Uses client-provided `user_id`
- **Private Storage**: Audio files not publicly accessible
- **Signed URLs**: 30-minute expiry for streaming
- **Rate Limiting**: Request logging for abuse prevention
- **RLS Policies**: Row-level security on all tables

## 🔄 GitHub Actions Deployment

### Required Secrets

Add these to your GitHub repository secrets:

```
SUPABASE_PROJECT_REF=your-project-ref
SUPABASE_ACCESS_TOKEN=your-access-token
SUPABASE_ANON_KEY=your-anon-key
OPENAI_API_KEY=your-openai-key
ELEVENLABS_API_KEY=your-elevenlabs-key
WORKER_AUTH_TOKEN=random-secure-token
```

### Automatic Deployment

The workflow deploys on:
- Push to `main` branch (changes to `supabase/` folder)
- Pull requests (with testing)
- Manual trigger

## 🔧 Background Processing

### Cron Jobs Setup

Set up external cron job at [cron-job.org](https://cron-job.org) to trigger job processing:

**URL:** `https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_jobs`
**Method:** POST
**Headers:** 
```
Authorization: Bearer YOUR_WORKER_AUTH_TOKEN
Content-Type: application/json
```
**Schedule:** Every 1 minute (`*/1 * * * *`)
**Body:** `{}`

### Manual Job Processing

Trigger job processing manually:

```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_WORKER_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  "https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_jobs"
```

## 📊 Monitoring & Analytics

### Request Logging

All API calls are logged in `request_logs` table for:
- Rate limiting enforcement
- Usage analytics  
- Error debugging
- Performance monitoring

### Job Status Tracking

Monitor job processing through database queries:

```sql
-- Current queue status
SELECT status, COUNT(*) 
FROM jobs 
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY status;

-- Failed jobs needing attention  
SELECT job_id, user_id, local_date, error_message
FROM jobs 
WHERE status = 'failed' 
AND created_at > NOW() - INTERVAL '1 day';
```

## 🧹 Maintenance

### Cleanup Old Data

Automatic cleanup via scheduled function:

```sql
-- Run weekly to cleanup old data
SELECT cleanup_old_data(30); -- Keep 30 days
```

### Storage Management

Monitor storage usage in Supabase Dashboard:
- Audio files are automatically cleaned up after 30 days
- Average file size: ~5MB per DayStart
- Estimate: 150MB per user per month

## 🚨 Troubleshooting

### Common Issues

**1. Functions not deploying:**
```bash
# Check function logs
supabase functions logs --function-name create_job

# Redeploy specific function
supabase functions deploy create_job --no-verify-jwt
```

**2. Storage permissions:**
- Verify bucket is private
- Check RLS policies are active
- Test signed URL generation

**3. API key issues:**
```bash
# Verify secrets are set
supabase secrets list

# Update individual secret  
supabase secrets set OPENAI_API_KEY="new-key"
```

**4. Job processing stuck:**
```sql
-- Release stuck jobs
SELECT release_expired_leases();

-- Check worker logs
```

### Testing Endpoints

Test your deployment:

```bash
# Test job creation
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-client-info: test-ios-device" \
  -d '{"local_date":"2025-08-12","scheduled_at":"2025-08-12T07:00:00Z","preferred_name":"Test","include_weather":true,"include_news":true,"include_sports":false,"include_stocks":false,"stock_symbols":[],"include_calendar":false,"include_quotes":true,"quote_preference":"motivational","voice_option":"voice1","daystart_length":180,"timezone":"America/New_York"}' \
  "https://YOUR_PROJECT_REF.supabase.co/functions/v1/create_job"

# Test status check
curl -H "x-client-info: test-ios-device" \
  "https://YOUR_PROJECT_REF.supabase.co/functions/v1/get_audio_status?date=2025-08-12"
```

## ✅ Production Checklist

- [ ] Supabase project created and configured
- [ ] Database migration applied successfully
- [ ] Storage bucket created as private
- [ ] Edge Functions deployed without errors
- [ ] Environment secrets configured
- [ ] iOS app Info.plist updated with correct URLs
- [ ] GitHub Actions secrets configured
- [ ] Cron job set up for background processing
- [ ] Test API endpoints working
- [ ] Monitoring and logging active

## 🔗 Resources

- [Supabase Documentation](https://supabase.com/docs)
- [Edge Functions Guide](https://supabase.com/docs/guides/functions)
- [Storage Documentation](https://supabase.com/docs/guides/storage)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [ElevenLabs API Docs](https://elevenlabs.io/docs/api-reference)

---

## Support

For issues with the backend setup:
1. Check function logs in Supabase Dashboard
2. Verify all environment variables are set
3. Test API endpoints individually
4. Review database migrations for conflicts

The backend is designed to handle iOS's streaming requirements with automatic fallback to cached content for reliable offline replay.