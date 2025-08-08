# DayStart Backend Setup Guide

Complete step-by-step guide to set up the DayStart backend infrastructure.

## Prerequisites

- **Node.js 18+** installed
- **GitHub account** with access to create repositories
- **Apple Developer Account** (for Apple Sign-In)
- **Google Cloud Console access** (for Google Sign-In)

## Step 1: Create Supabase Project

### 1.1 Create Account & Project
1. Go to [supabase.com](https://supabase.com)
2. Sign up/sign in with GitHub
3. Click **"New Project"**
4. Fill out project details:
   - **Organization**: Your personal organization
   - **Name**: `daystart-backend`  
   - **Database Password**: Generate strong password (save this!)
   - **Region**: Choose closest to your users (e.g., `us-west-1` for US West Coast)
   - **Pricing Plan**: Start with Free tier

### 1.2 Save Project Credentials
Once created, go to **Settings > API** and save these:
```
Project URL: https://YOUR_PROJECT_ID.supabase.co
Project ID: YOUR_PROJECT_ID (from the URL)
anon public: eyJhbG... (for iOS app)
service_role secret: eyJhbG... (for backend functions)
```

### 1.3 Configure Authentication
1. Go to **Authentication > Settings**
2. **Site URL**: `daystart://auth-callback` (your iOS app URL scheme)
3. **Additional Redirect URLs**: Add your iOS app schemes

#### Enable Apple Sign-In
1. Go to **Authentication > Providers**
2. Enable **Apple**
3. You'll need:
   - **Client ID**: `your.app.bundle.id` (e.g., `com.yourcompany.daystart`)
   - **Client Secret**: Generate in Apple Developer Console

#### Enable Google Sign-In
1. Enable **Google** provider
2. You'll need Google OAuth credentials from Google Cloud Console

## Step 2: Get External API Keys

### 2.1 OpenAI (Required)
1. Go to [platform.openai.com](https://platform.openai.com)
2. Create API key for GPT-4o access
3. Save the key: `sk-...`

### 2.2 ElevenLabs (Required)
1. Go to [elevenlabs.io](https://elevenlabs.io)
2. Create account and get API key
3. Note available voice IDs for your app's voice options

### 2.3 NewsAPI (Required)
1. Go to [newsapi.org](https://newsapi.org)
2. Sign up for Business plan ($450/month for commercial use)
3. Get API key

### 2.4 Alpha Vantage (Required)
1. Go to [alphavantage.co](https://alphavantage.co)
2. Sign up for Standard plan (~$50/month)
3. Get API key

### 2.5 Resend (Required)
1. Go to [resend.com](https://resend.com)
2. Create account and get API key for health check emails

## Step 3: Set Up GitHub Repository

### 3.1 Create Repository
1. Go to GitHub and create new repository: `daystart-backend`
2. Make it **private** (contains API keys)
3. Don't initialize with README (we have our files)

### 3.2 Push Local Code
```bash
cd /Users/natep/DayStart/daystart-backend
git init
git add .
git commit -m "Initial backend setup"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/daystart-backend.git
git push -u origin main
```

### 3.3 Configure GitHub Secrets
Go to your repository **Settings > Secrets and Variables > Actions**

Add these **Repository Secrets**:

#### Supabase
- `SUPABASE_ACCESS_TOKEN`: Get from [app.supabase.com/account/tokens](https://app.supabase.com/account/tokens)
- `SUPABASE_PROJECT_ID`: Your project ID from Step 1.2
- `SUPABASE_DB_PASSWORD`: Database password from Step 1.1

#### API Keys
- `OPENAI_API_KEY`: From Step 2.1
- `ELEVENLABS_API_KEY`: From Step 2.2  
- `NEWSAPI_KEY`: From Step 2.3
- `ALPHA_VANTAGE_KEY`: From Step 2.4
- `RESEND_API_KEY`: From Step 2.5

#### Configuration
- `HEALTH_CHECK_EMAIL`: Your email for system alerts
- `CRON_JOB_SECRET`: Generate random string for cron job authentication

## Step 4: Deploy Initial Setup

### 4.1 Install Supabase CLI Locally
```bash
npm install -g supabase
supabase login
```

### 4.2 Link to Project
```bash
cd /Users/natep/DayStart/daystart-backend
supabase link --project-ref YOUR_PROJECT_ID
```

### 4.3 Deploy Database Schema
```bash
supabase db reset
```

### 4.4 Verify Setup
1. Go to your Supabase dashboard
2. Check **Table Editor** - you should see all the tables
3. Check **Storage** - you should see `audio-files` bucket

## Step 5: Set Up Cron Jobs

### 5.1 Create Cron-Job.org Account
1. Go to [cron-job.org](https://cron-job.org)
2. Create free account (upgrade if needed for more jobs)

### 5.2 Configure Cron Jobs

#### Hourly Content Fetchers
**News Fetcher**:
- URL: `https://YOUR_PROJECT_ID.supabase.co/functions/v1/cron_fetch_news`
- Schedule: `0 * * * *` (every hour)
- Method: POST
- Headers: `Authorization: Bearer YOUR_SERVICE_ROLE_KEY`

**Sports Fetcher**:
- URL: `https://YOUR_PROJECT_ID.supabase.co/functions/v1/cron_fetch_sports`
- Schedule: `0 * * * *`
- Method: POST  
- Headers: `Authorization: Bearer YOUR_SERVICE_ROLE_KEY`

**Stocks Fetcher**:
- URL: `https://YOUR_PROJECT_ID.supabase.co/functions/v1/cron_fetch_stocks`
- Schedule: `0 * * * *`
- Method: POST
- Headers: `Authorization: Bearer YOUR_SERVICE_ROLE_KEY`

#### Health Check (Every 15 minutes)
- URL: `https://YOUR_PROJECT_ID.supabase.co/functions/v1/cron_health_check`
- Schedule: `*/15 * * * *`
- Method: POST
- Headers: `Authorization: Bearer YOUR_SERVICE_ROLE_KEY`

#### Daily Cleanup (2 AM UTC)
- URL: `https://YOUR_PROJECT_ID.supabase.co/functions/v1/cron_cleanup_storage`
- Schedule: `0 2 * * *`
- Method: POST
- Headers: `Authorization: Bearer YOUR_SERVICE_ROLE_KEY`

## Step 6: iOS App Integration

### 6.1 Install Supabase Swift SDK
Add to your iOS project:
```swift
dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
]
```

### 6.2 Configure Supabase Client
```swift
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://YOUR_PROJECT_ID.supabase.co")!,
    supabaseKey: "YOUR_ANON_KEY"
)
```

### 6.3 Update App URL Schemes
In `Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>auth-callback</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>daystart</string>
        </array>
    </dict>
</array>
```

## Step 7: Testing & Verification

### 7.1 Test GitHub Actions
1. Make a small change to README.md
2. Commit and push to main branch
3. Check **Actions** tab - deployment should succeed

### 7.2 Test Functions Manually
Use a tool like Postman or curl:
```bash
curl -X POST \
  "https://YOUR_PROJECT_ID.supabase.co/functions/v1/cron_health_check" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
```

### 7.3 Monitor Logs
- Go to Supabase dashboard **Logs** section
- Check for any errors in function execution
- Verify cron jobs are running successfully

## Step 8: Production Checklist

### 8.1 Security Review
- [ ] All API keys stored in GitHub Secrets (never committed)
- [ ] RLS policies enabled and tested
- [ ] Storage bucket is private
- [ ] Service role key only used in backend functions

### 8.2 Monitoring Setup
- [ ] Health check emails working
- [ ] Cron job notifications configured
- [ ] Error alerting set up via Resend

### 8.3 Performance Baseline
- [ ] Database indexes created
- [ ] Function cold start times acceptable
- [ ] API response times under 5 seconds

## Troubleshooting

### Common Issues

**"Permission denied" errors**:
- Check RLS policies are correct
- Verify you're using the right API key (anon vs service_role)

**Function deployment fails**:
- Check all environment variables are set in GitHub Secrets
- Verify Supabase access token has correct permissions

**Cron jobs not running**:
- Check the URLs are correct (include `/functions/v1/`)
- Verify Authorization header format
- Check function logs in Supabase dashboard

### Getting Help
- **Supabase docs**: [supabase.com/docs](https://supabase.com/docs)
- **GitHub Issues**: Create issues in your repository for tracking
- **Function logs**: Always check Supabase dashboard logs first

## Next Steps

Once everything is set up:
1. **Implement Edge Functions** (next development phase)
2. **Test with real iOS app integration**
3. **Set up monitoring dashboards**
4. **Optimize for your user base**

Your backend infrastructure is now ready for DayStart! 🚀