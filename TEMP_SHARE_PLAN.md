# Setting Up `/shared/{token}` Route on Existing daystartai.app

## 🔍 Current Setup
- ✅ Domain: `daystartai.app` on GoDaddy
- ✅ Hosting: Netlify 
- ✅ Current behavior: Root domain redirects to App Store
- ✅ Audio storage: Supabase with signed URLs

## 🎯 Goal: Add `/shared/{token}` route for branded audio player

## 🚀 **IMPLEMENTATION STATUS**

### ✅ **COMPLETED - Frontend & Netlify (2025-10-20)**
- ✅ **Netlify site structure created** (`/Users/natep/DayStart/netlify-site/`)
- ✅ **Branded audio player page** (`shared/index.html`) with DayStart theming
- ✅ **Responsive CSS** (`assets/css/daystart-player.css`) with banana theme
- ✅ **JavaScript player** (`assets/js/audio-player.js`) with mock functionality
- ✅ **Netlify routing** (`_redirects`) configured for `/shared/:token`
- ✅ **Security headers** (`netlify.toml`) configured
- ✅ **Google Analytics** (G-RN79S5YCEN) integrated
- ✅ **Apple Smart Banner** (app-id=6751055528) added
- ✅ **Deployed to Netlify** - Site is LIVE

**Live URLs:**
- `https://daystartai.app/shared/test123` → Shows branded audio player (mock mode)
- `https://daystartai.app` → Redirects to App Store

### ✅ **COMPLETED - Database Schema (2025-10-20)**
- ✅ **Migration created** (`032_add_share_functionality.sql`)
- ✅ **Database deployed** to Supabase with enhanced schema
- ✅ **Analytics tracking** fields ready
- ✅ **Rate limiting** support built in
- ✅ **RLS policies** configured for security

### 🔄 **TODO - Edge Functions**
- 🔄 **Create `get_shared_daystart`** edge function
- 🔄 **Create `create_share`** edge function  
- 🔄 **Deploy functions** to Supabase
- 🔄 **Test with real data** end-to-end

### 🔄 **TODO - iOS Integration** 
- 🔄 **ShareResponse model** creation
- 🔄 **SupabaseClient methods** for share API
- 🔄 **Connect share buttons** in HomeView/AudioPlayerView
- 🔄 **Update frontend JavaScript** with real API endpoint

## 📁 Step-by-Step Implementation

### ✅ Step 1: Netlify Site Structure (COMPLETED)
```
netlify-site/
├── index.html              ✅ (current App Store redirect)
├── shared/
│   └── index.html          ✅ (branded audio player page)
├── _redirects              ✅ (Netlify routing rules)
├── assets/
│   ├── css/
│   │   └── daystart-player.css  ✅ (DayStart themed CSS)
│   ├── js/
│   │   └── audio-player.js      ✅ (JavaScript player with mock mode)
│   └── images/             ✅ (created, uses existing daystart-icon-large.jpeg)
├── netlify.toml            ✅ (build config with security headers)
└── daystart-icon-large.jpeg ✅ (existing app icon)
```

### ✅ Step 2: Netlify Routing Configuration (COMPLETED)

### ✅ Step 3: Database Schema (COMPLETED)

**`_redirects` file:** ✅
```
# Shared DayStart player - capture token parameter
/shared/:token /shared/index.html 200

# Root and other paths -> App Store (uses actual App Store URL)
/ https://apps.apple.com/app/apple-store/id6751055528?pt=128010523&ct=daystartai.app&mt=8 302
/* https://apps.apple.com/app/apple-store/id6751055528?pt=128010523&ct=daystartai.app&mt=8 302
```

**`netlify.toml`:** ✅
```toml
[build]
  publish = "."

[[headers]]
  for = "/shared/*"
  [headers.values]
    X-Frame-Options = "DENY"
    X-Content-Type-Options = "nosniff"
    Referrer-Policy = "strict-origin-when-cross-origin"
    Cache-Control = "public, max-age=300"

[[headers]]
  for = "/assets/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000"
```

### 🔄 Step 4: Supabase Edge Functions (TODO)

**A. Database Schema (Enhanced with Recommendations):**
```sql
-- Migration: 032_add_share_functionality.sql
-- Add share functionality for public DayStart links
-- This is a completely new feature that doesn't modify existing tables

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
  
  -- Rate limiting
  shares_per_job INTEGER DEFAULT 1 -- Track multiple shares of same job
);

-- Indexes for performance
CREATE UNIQUE INDEX shares_token_idx ON public_daystart_shares(share_token);
CREATE INDEX shares_expiry_idx ON public_daystart_shares(expires_at);
CREATE INDEX shares_user_idx ON public_daystart_shares(user_id);
CREATE INDEX shares_job_idx ON public_daystart_shares(job_id);

-- Enable RLS
ALTER TABLE public_daystart_shares ENABLE ROW LEVEL SECURITY;

-- RLS Policies
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

-- Add helpful comments
COMMENT ON TABLE public_daystart_shares IS 'Stores shareable links for DayStart audio briefings with expiration and analytics';
COMMENT ON COLUMN public_daystart_shares.share_token IS 'URL-safe unique token used in share URLs';
COMMENT ON COLUMN public_daystart_shares.expires_at IS 'When the share link expires (typically 48 hours)';
COMMENT ON COLUMN public_daystart_shares.share_source IS 'Where the share was initiated from in the app';
COMMENT ON COLUMN public_daystart_shares.shares_per_job IS 'Number of shares created for this job (rate limiting)';
```

**B. Edge Function: `get_shared_daystart` (Enhanced)**
```typescript
// supabase/functions/get_shared_daystart/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://daystartai.app',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type'
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    const { token } = await req.json()
    
    if (!token || typeof token !== 'string' || token.length < 8) {
      return new Response(JSON.stringify({ 
        error: 'Invalid share link',
        code: 'INVALID_TOKEN' 
      }), { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )
    
    // 1. Validate token and get job data
    const { data: share } = await supabase
      .from('public_daystart_shares')
      .select(`
        share_id,
        job_id,
        view_count,
        jobs (
          audio_file_path,
          audio_duration,
          local_date,
          script_content,
          daystart_length,
          preferred_name
        )
      `)
      .eq('share_token', token)
      .gt('expires_at', new Date().toISOString())
      .single()
    
    if (!share || !share.jobs) {
      return new Response(JSON.stringify({ 
        error: 'This briefing has expired or is no longer available',
        code: 'SHARE_EXPIRED' 
      }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 2. Verify audio file exists
    const audioFileName = share.jobs.audio_file_path.split('/').pop()
    const audioPath = share.jobs.audio_file_path.split('/').slice(0, -1).join('/')
    
    const { data: files } = await supabase.storage
      .from('daystart-audio')
      .list(audioPath)
    
    if (!files?.find(f => f.name === audioFileName)) {
      console.error(`Audio file not found: ${share.jobs.audio_file_path}`)
      return new Response(JSON.stringify({ 
        error: 'Audio file no longer available',
        code: 'AUDIO_NOT_FOUND' 
      }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 3. Generate signed URL for audio
    const { data: audioUrl, error: urlError } = await supabase.storage
      .from('daystart-audio')
      .createSignedUrl(share.jobs.audio_file_path, 3600) // 1 hour
    
    if (urlError || !audioUrl?.signedUrl) {
      console.error('Failed to create signed URL:', urlError)
      return new Response(JSON.stringify({ 
        error: 'Failed to load audio',
        code: 'URL_GENERATION_FAILED' 
      }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // 4. Update view count and analytics
    await supabase
      .from('public_daystart_shares')
      .update({ 
        view_count: share.view_count + 1,
        last_accessed_at: new Date().toISOString()
      })
      .eq('share_id', share.share_id)
    
    // 5. Return sanitized data
    return new Response(JSON.stringify({
      audio_url: audioUrl.signedUrl,
      duration: share.jobs.audio_duration,
      date: share.jobs.local_date,
      length_minutes: Math.round(share.jobs.daystart_length / 60),
      // Optional: Include name for personalized greeting
      user_name: share.jobs.preferred_name || null
    }), {
      status: 200,
      headers: { 
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'private, max-age=300' // 5 min cache
      }
    })
    
  } catch (error) {
    console.error('Share retrieval error:', error)
    return new Response(JSON.stringify({ 
      error: 'Something went wrong',
      code: 'INTERNAL_ERROR' 
    }), { 
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
```

### Step 4: Branded Audio Player Page

**`shared/index.html`:**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Shared DayStart</title>
    <link rel="stylesheet" href="../assets/css/daystart-player.css">
    
    <!-- Open Graph for rich sharing -->
    <meta property="og:title" content="Listen to my DayStart">
    <meta property="og:description" content="Personalized morning briefing with news, weather, and insights">
    <meta property="og:type" content="music.song">
    <meta property="og:site_name" content="DayStart">
</head>
<body>
    <!-- App Download Banner -->
    <div class="download-banner">
        <div class="banner-content">
            <span>🌅 Get your own personalized DayStart</span>
            <a href="https://apps.apple.com/app/daystart/id123456789" class="download-btn">
                Download App
            </a>
        </div>
    </div>

    <!-- Main Player -->
    <div class="player-container">
        <div class="player-header">
            <img src="../assets/images/daystart-logo.svg" alt="DayStart" class="logo">
            <h1>Shared DayStart</h1>
        </div>

        <div class="audio-player" id="audioPlayer">
            <!-- Loading state -->
            <div class="loading" id="loading">
                <div class="spinner"></div>
                <p>Loading DayStart...</p>
            </div>

            <!-- Player controls (hidden until loaded) -->
            <div class="player-controls" id="playerControls" style="display: none;">
                <div class="progress-container">
                    <div class="progress-bar" id="progressBar">
                        <div class="progress-fill" id="progressFill"></div>
                    </div>
                    <div class="time-display">
                        <span id="currentTime">0:00</span>
                        <span id="duration">0:00</span>
                    </div>
                </div>

                <div class="controls">
                    <button class="control-btn" id="skipBack">
                        ⏪ 10s
                    </button>
                    <button class="play-pause-btn" id="playPause">
                        ▶️
                    </button>
                    <button class="control-btn" id="skipForward">
                        10s ⏩
                    </button>
                </div>

                <div class="daystart-info">
                    <p class="date" id="daystartDate"></p>
                    <p class="duration-info" id="durationInfo"></p>
                </div>
            </div>

            <!-- Error state -->
            <div class="error" id="error" style="display: none;">
                <p>Unable to load this DayStart</p>
                <a href="https://apps.apple.com/app/daystart/id123456789">Get the DayStart app</a>
            </div>
        </div>

        <!-- App promotion footer -->
        <div class="app-promotion">
            <h2>Experience Your Own DayStart</h2>
            <p>Get personalized morning briefings with news, weather, calendar events, and daily motivation.</p>
            <a href="https://apps.apple.com/app/daystart/id123456789" class="cta-button">
                <img src="../assets/images/app-store-badge.svg" alt="Download on App Store">
            </a>
        </div>
    </div>

    <audio id="audioElement" preload="metadata"></audio>
    <script src="../assets/js/audio-player.js"></script>
</body>
</html>
```

### Step 5: JavaScript Audio Player

**`assets/js/audio-player.js`:**
```javascript
class DayStartPlayer {
    constructor() {
        this.audio = document.getElementById('audioElement');
        this.token = this.getTokenFromUrl();
        this.init();
    }

    getTokenFromUrl() {
        const path = window.location.pathname;
        const match = path.match(/\/shared\/([^\/]+)/);
        return match ? match[1] : null;
    }

    async init() {
        if (!this.token) {
            this.showError();
            return;
        }

        try {
            await this.loadDayStart();
            this.setupControls();
            this.showPlayer();
        } catch (error) {
            console.error('Failed to load DayStart:', error);
            this.showError();
        }
    }

    async loadDayStart() {
        const response = await fetch('https://your-supabase-project.supabase.co/functions/v1/get_shared_daystart', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token: this.token })
        });

        if (!response.ok) throw new Error('Failed to load DayStart');

        const data = await response.json();
        
        this.audio.src = data.audio_url;
        this.updateUI(data);
    }

    updateUI(data) {
        document.getElementById('daystartDate').textContent = 
            new Date(data.date).toLocaleDateString('en-US', { 
                weekday: 'long', 
                year: 'numeric', 
                month: 'long', 
                day: 'numeric' 
            });
        
        document.getElementById('durationInfo').textContent = 
            `${data.length_minutes} minute briefing`;
    }

    setupControls() {
        const playPause = document.getElementById('playPause');
        const skipBack = document.getElementById('skipBack');
        const skipForward = document.getElementById('skipForward');
        const progressBar = document.getElementById('progressBar');

        playPause.addEventListener('click', () => this.togglePlayPause());
        skipBack.addEventListener('click', () => this.skip(-10));
        skipForward.addEventListener('click', () => this.skip(10));
        
        this.audio.addEventListener('timeupdate', () => this.updateProgress());
        this.audio.addEventListener('loadedmetadata', () => this.updateDuration());
        
        progressBar.addEventListener('click', (e) => this.seek(e));
    }

    togglePlayPause() {
        if (this.audio.paused) {
            this.audio.play();
            document.getElementById('playPause').textContent = '⏸️';
        } else {
            this.audio.pause();
            document.getElementById('playPause').textContent = '▶️';
        }
    }

    skip(seconds) {
        this.audio.currentTime += seconds;
    }

    seek(e) {
        const progressBar = e.currentTarget;
        const rect = progressBar.getBoundingClientRect();
        const percent = (e.clientX - rect.left) / rect.width;
        this.audio.currentTime = percent * this.audio.duration;
    }

    updateProgress() {
        const percent = (this.audio.currentTime / this.audio.duration) * 100;
        document.getElementById('progressFill').style.width = percent + '%';
        document.getElementById('currentTime').textContent = this.formatTime(this.audio.currentTime);
    }

    updateDuration() {
        document.getElementById('duration').textContent = this.formatTime(this.audio.duration);
    }

    formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }

    showPlayer() {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('playerControls').style.display = 'block';
    }

    showError() {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('error').style.display = 'block';
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    new DayStartPlayer();
});
```

### Step 6: DayStart-Themed CSS

**`assets/css/daystart-player.css`:**
```css
/* DayStart branded styling with banana theme */
:root {
    --primary-yellow: #FFD700;
    --primary-orange: #FF8C00;
    --background: #1a1a1a;
    --surface: #2a2a2a;
    --text: #ffffff;
    --text-secondary: #cccccc;
    --accent: #FF6B35;
}

body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui;
    background: linear-gradient(135deg, var(--background) 0%, #2d1810 100%);
    color: var(--text);
    min-height: 100vh;
}

.download-banner {
    background: linear-gradient(90deg, var(--primary-yellow), var(--primary-orange));
    color: #000;
    padding: 12px 0;
    text-align: center;
    position: sticky;
    top: 0;
    z-index: 100;
}

.banner-content {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 20px;
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 20px;
}

.download-btn {
    background: #000;
    color: var(--primary-yellow);
    padding: 8px 16px;
    border-radius: 20px;
    text-decoration: none;
    font-weight: 600;
    transition: transform 0.2s;
}

.download-btn:hover {
    transform: scale(1.05);
}

.player-container {
    max-width: 600px;
    margin: 40px auto;
    padding: 0 20px;
}

.player-header {
    text-align: center;
    margin-bottom: 40px;
}

.logo {
    height: 60px;
    margin-bottom: 16px;
}

.audio-player {
    background: var(--surface);
    border-radius: 20px;
    padding: 40px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.3);
}

.loading, .error {
    text-align: center;
    padding: 40px;
}

.spinner {
    width: 40px;
    height: 40px;
    border: 4px solid var(--primary-yellow);
    border-top: 4px solid transparent;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin: 0 auto 20px;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

.progress-container {
    margin-bottom: 30px;
}

.progress-bar {
    height: 6px;
    background: rgba(255, 255, 255, 0.2);
    border-radius: 3px;
    cursor: pointer;
    margin-bottom: 12px;
}

.progress-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--primary-yellow), var(--primary-orange));
    border-radius: 3px;
    transition: width 0.1s;
}

.time-display {
    display: flex;
    justify-content: space-between;
    font-size: 14px;
    color: var(--text-secondary);
    font-variant-numeric: tabular-nums;
}

.controls {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 30px;
    margin-bottom: 30px;
}

.play-pause-btn {
    width: 80px;
    height: 80px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--primary-yellow), var(--primary-orange));
    border: none;
    font-size: 32px;
    cursor: pointer;
    transition: transform 0.2s;
}

.play-pause-btn:hover {
    transform: scale(1.1);
}

.control-btn {
    background: rgba(255, 255, 255, 0.1);
    border: none;
    color: var(--text);
    padding: 12px 16px;
    border-radius: 20px;
    cursor: pointer;
    font-size: 14px;
    transition: background 0.2s;
}

.control-btn:hover {
    background: rgba(255, 255, 255, 0.2);
}

.daystart-info {
    text-align: center;
    border-top: 1px solid rgba(255, 255, 255, 0.1);
    padding-top: 20px;
}

.date {
    font-size: 18px;
    margin-bottom: 8px;
}

.duration-info {
    color: var(--text-secondary);
    font-size: 14px;
}

.app-promotion {
    background: var(--surface);
    border-radius: 20px;
    padding: 40px;
    text-align: center;
    margin-top: 40px;
}

.app-promotion h2 {
    margin-bottom: 16px;
    background: linear-gradient(45deg, var(--primary-yellow), var(--primary-orange));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}

.cta-button img {
    height: 60px;
    margin-top: 20px;
}

/* Mobile responsive */
@media (max-width: 768px) {
    .banner-content {
        flex-direction: column;
        gap: 12px;
    }
    
    .audio-player {
        padding: 30px 20px;
    }
    
    .controls {
        gap: 20px;
    }
    
    .play-pause-btn {
        width: 70px;
        height: 70px;
        font-size: 28px;
    }
}
```

## 🚀 Deployment Steps

1. **Create the file structure in your Netlify site**
2. **Deploy the new Edge Function to Supabase**
3. **Run the database migration**
4. **Test with a sample share token**
5. **Verify routing works: `daystartai.app/shared/test-token`**

## Additional Implementation Notes

### Edge Function for Creating Shares (Enhanced with Rate Limiting)

**`supabase/functions/create_share/index.ts`:**
```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// URL-safe token generation
const generateShareToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
    .substring(0, 12) // Short, URL-safe token
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // iOS app needs this
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-client-info'
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    const { 
      job_id, 
      duration_hours = 48,
      share_source = 'unknown' // 'completion_screen', 'audio_player', 'manual'
    } = await req.json()
    
    // Extract user ID from header
    const userId = req.headers.get('x-client-info')
    if (!userId) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { 
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )
    
    // Verify job belongs to user and has audio
    const { data: job } = await supabase
      .from('jobs')
      .select('user_id, audio_file_path, status')
      .eq('job_id', job_id)
      .eq('user_id', userId)
      .single()
    
    if (!job) {
      return new Response(JSON.stringify({ error: 'Job not found' }), { 
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    if (job.status !== 'ready' || !job.audio_file_path) {
      return new Response(JSON.stringify({ error: 'Audio not ready' }), { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Check rate limiting - max 5 shares per job
    const { count } = await supabase
      .from('public_daystart_shares')
      .select('*', { count: 'exact', head: true })
      .eq('job_id', job_id)
    
    if (count && count >= 5) {
      return new Response(JSON.stringify({ 
        error: 'Share limit reached for this briefing',
        code: 'RATE_LIMIT_EXCEEDED' 
      }), { 
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Check daily user limit (optional)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    
    const { count: dailyCount } = await supabase
      .from('public_daystart_shares')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .gte('created_at', today.toISOString())
    
    if (dailyCount && dailyCount >= 10) {
      return new Response(JSON.stringify({ 
        error: 'Daily share limit reached',
        code: 'DAILY_LIMIT_EXCEEDED' 
      }), { 
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    // Generate token and expiry
    const share_token = generateShareToken()
    const expires_at = new Date()
    expires_at.setHours(expires_at.getHours() + duration_hours)
    
    // Create share record
    const { data: share, error } = await supabase
      .from('public_daystart_shares')
      .insert({
        job_id,
        user_id: userId,
        share_token,
        expires_at: expires_at.toISOString(),
        share_source,
        shares_per_job: (count || 0) + 1,
        share_metadata: {
          app_version: req.headers.get('x-app-version') || 'unknown',
          created_from: 'ios_app'
        }
      })
      .select()
      .single()
    
    if (error) {
      console.error('Share creation error:', error)
      return new Response(JSON.stringify({ error: 'Failed to create share' }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    
    return new Response(JSON.stringify({
      share_url: `https://daystartai.app/shared/${share_token}`,
      token: share_token,
      expires_at: expires_at.toISOString(),
      share_id: share.share_id
    }), {
      status: 201,
      headers: { 
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
      }
    })
    
  } catch (error) {
    console.error('Share creation error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), { 
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
```

### iOS Integration (Enhanced)

**1. Add ShareResponse Model:**
```swift
// Models/ShareResponse.swift
struct ShareResponse: Codable {
    let shareUrl: String
    let token: String
    let expiresAt: Date
    let shareId: UUID
    
    enum CodingKeys: String, CodingKey {
        case shareUrl = "share_url"
        case token
        case expiresAt = "expires_at"
        case shareId = "share_id"
    }
}
```

**2. Add to SupabaseClient:**
```swift
// Services/SupabaseClient.swift
extension SupabaseClient {
    func createShare(
        jobId: UUID, 
        source: String = "unknown",
        durationHours: Int = 48
    ) async throws -> ShareResponse {
        let url = URL(string: "\(supabaseUrl)/functions/v1/create_share")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(receiptId, forHTTPHeaderField: "x-client-info")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", 
                        forHTTPHeaderField: "x-app-version")
        
        let body = [
            "job_id": jobId.uuidString,
            "share_source": source,
            "duration_hours": durationHours
        ]
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw SupabaseError.apiError(errorMessage)
            }
            throw SupabaseError.requestFailed
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShareResponse.self, from: data)
    }
}
```

**3. Update Share Functions in Views:**
```swift
// HomeView.swift & AudioPlayerView.swift
private func shareDayStart(_ dayStart: DayStartData) {
    Task {
        do {
            // Show loading indicator
            isShareLoading = true
            
            // 1. Create share via API
            let shareResponse = try await SupabaseClient.shared.createShare(
                jobId: dayStart.id,
                source: "completion_screen" // or "audio_player"
            )
            
            // 2. Create leadership-focused share message
            let duration = Int(dayStart.duration / 60)
            let shareText = """
            🎯 Just got my Morning Intelligence Brief
            
            \(duration) minutes of curated insights delivered like my own Chief of Staff prepared it.
            
            Stop reacting. Start leading.
            
            Listen: \(shareResponse.shareUrl)
            
            Join the leaders who start ahead: https://daystartai.app
            
            #MorningIntelligence #Leadership #DayStart
            """
            
            // 3. Present share sheet
            await MainActor.run {
                let activityVC = UIActivityViewController(
                    activityItems: [shareText],
                    applicationActivities: nil
                )
                
                // Configure for iPad
                if let popover = activityVC.popoverPresentationController {
                    // ... existing popover config
                }
                
                // Present
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {
                    rootVC.present(activityVC, animated: true)
                }
                
                isShareLoading = false
            }
            
            // 4. Track share analytics
            AnalyticsService.shared.track(.sharedDayStart, properties: [
                "source": "completion_screen",
                "share_id": shareResponse.shareId.uuidString
            ])
            
        } catch {
            // Handle error gracefully
            await MainActor.run {
                isShareLoading = false
                // Show error alert or toast
                showShareError = true
            }
            print("Failed to create share: \(error)")
        }
    }
}
```

### JavaScript Player Enhancement

**Update `assets/js/audio-player.js` for Dynamic Content:**
```javascript
// Add to loadDayStart() method
updateUI(data) {
    // Format date nicely
    const dateObj = new Date(data.date)
    document.getElementById('daystartDate').textContent = 
        dateObj.toLocaleDateString('en-US', { 
            weekday: 'long', 
            year: 'numeric', 
            month: 'long', 
            day: 'numeric' 
        })
    
    // Duration with personalized touch
    const userName = data.user_name ? `${data.user_name}'s ` : ''
    document.getElementById('durationInfo').textContent = 
        `${userName}${data.length_minutes} minute intelligence brief`
    
    // Update page title and OG tags dynamically
    document.title = `${userName}Morning Intelligence Brief - DayStart`
    
    // Update Open Graph tags for better sharing
    const ogTitle = document.querySelector('meta[property="og:title"]')
    if (ogTitle) {
        ogTitle.content = `Listen to ${userName}${data.length_minutes} minute Morning Intelligence Brief`
    }
}
```

### Share Cleanup Addition

**Add to cleanup-audio function:**
```typescript
// In cleanup-audio/index.ts, add after audio cleanup:

// Clean up expired shares
const { error: shareCleanupError } = await supabase
  .from('public_daystart_shares')
  .delete()
  .lt('expires_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())

if (shareCleanupError) {
  console.error('Share cleanup error:', shareCleanupError)
} else {
  console.log('Cleaned up expired share links')
}
```

## 📊 Analytics & Monitoring

### Track Share Metrics:
```sql
-- Useful queries for monitoring
-- Daily share creation
SELECT 
  DATE(created_at) as date,
  COUNT(*) as shares_created,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT job_id) as unique_briefings
FROM public_daystart_shares
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Conversion tracking
SELECT 
  COUNT(*) FILTER (WHERE clicked_cta = true) as cta_clicks,
  COUNT(*) FILTER (WHERE converted_to_user = true) as conversions,
  AVG(view_count) as avg_views_per_share
FROM public_daystart_shares
WHERE created_at > NOW() - INTERVAL '30 days';
```

## 🚀 Phased Implementation Plan

### Phase 1: Basic Functionality (MVP)
- ✅ Frontend complete with branded player
- Deploy basic database schema
- Deploy edge functions without rate limiting
- Test end-to-end flow
- Feature flag in iOS app

### Phase 2: Rate Limiting & Analytics
- Add rate limiting to create_share
- Implement view tracking
- Add CTA click tracking
- Deploy analytics dashboard

### Phase 3: Advanced Features
- Dynamic OG image generation
- Share expiration notifications
- Conversion tracking
- A/B testing different share messages

## 🔍 Monitoring & Maintenance

### Update Healthcheck Function
After deploying the share feature, update the healthcheck function to monitor share system health:

```typescript
// Add to healthcheck/index.ts
async function checkShareSystem(supabase: any) {
  const start = Date.now()
  
  try {
    // Check recent share creation
    const { count: recentShares } = await supabase
      .from('public_daystart_shares')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
    
    // Check for expired shares cleanup
    const { count: expiredShares } = await supabase
      .from('public_daystart_shares')
      .select('*', { count: 'exact', head: true })
      .lt('expires_at', new Date().toISOString())
    
    // Check edge functions are accessible
    const testResponse = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/get_shared_daystart`, {
      method: 'OPTIONS'
    })
    
    const functionsHealthy = testResponse.status === 204
    const duration_ms = Date.now() - start
    
    return {
      name: 'share_system',
      status: functionsHealthy ? 'pass' : 'fail',
      duration_ms,
      details: {
        recent_shares_24h: recentShares || 0,
        expired_shares_pending_cleanup: expiredShares || 0,
        edge_functions_responsive: functionsHealthy
      }
    }
  } catch (error) {
    return {
      name: 'share_system',
      status: 'fail',
      duration_ms: Date.now() - start,
      error: error.message
    }
  }
}
```

### Share Cleanup Queries
Add these to your monitoring dashboard:

```sql
-- Daily share metrics
SELECT 
  DATE(created_at) as date,
  COUNT(*) as shares_created,
  COUNT(DISTINCT user_id) as unique_users,
  AVG(view_count) as avg_views_per_share
FROM public_daystart_shares
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Share system health
SELECT 
  COUNT(*) FILTER (WHERE expires_at > NOW()) as active_shares,
  COUNT(*) FILTER (WHERE expires_at <= NOW()) as expired_shares,
  COUNT(*) FILTER (WHERE view_count > 0) as viewed_shares,
  MAX(view_count) as most_viewed_share
FROM public_daystart_shares;
```

This comprehensive plan provides a production-ready share feature that's backwards compatible, secure, and optimized for viral growth!