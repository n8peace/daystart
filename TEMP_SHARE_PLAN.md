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
- ✅ **Ready for deployment** to Netlify

**Current URLs:**
- `https://daystartai.app/shared/test123` → Shows branded audio player (mock mode)
- `https://daystartai.app` → Redirects to App Store

### 🔄 **TODO - Backend Integration**
- 🔄 **Database schema** for `public_daystart_shares` table
- 🔄 **Supabase edge functions** (`get_shared_daystart`, `create_share`)
- 🔄 **iOS app integration** for share link generation
- 🔄 **Real audio playback** connection

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

### 🔄 Step 3: Supabase Backend (TODO - Database + Edge Functions)

**A. Database Schema:**
```sql
-- Add to new migration file
CREATE TABLE public_daystart_shares (
  share_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES jobs(job_id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  share_token TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  view_count INTEGER DEFAULT 0,
  last_accessed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX shares_token_idx ON public_daystart_shares(share_token);
CREATE INDEX shares_expiry_idx ON public_daystart_shares(expires_at);

-- RLS policies
ALTER TABLE public_daystart_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read for valid shares" ON public_daystart_shares
  FOR SELECT TO anon, authenticated
  USING (expires_at > NOW());
```

**B. Edge Function: `get_shared_daystart`**
```typescript
// supabase/functions/get_shared_daystart/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { token } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // 1. Validate token and get job data
  const { data: share } = await supabase
    .from('public_daystart_shares')
    .select(`
      job_id,
      view_count,
      jobs (
        audio_file_path,
        audio_duration,
        local_date,
        script_content,
        daystart_length
      )
    `)
    .eq('share_token', token)
    .gt('expires_at', new Date().toISOString())
    .single()
  
  if (!share) {
    return new Response(JSON.stringify({ error: 'Invalid or expired share' }), { 
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    })
  }
  
  // 2. Generate signed URL for audio
  const { data: audioUrl } = await supabase.storage
    .from('daystart-audio')
    .createSignedUrl(share.jobs.audio_file_path, 3600) // 1 hour
  
  // 3. Update view count
  await supabase
    .from('public_daystart_shares')
    .update({ 
      view_count: share.view_count + 1,
      last_accessed_at: new Date().toISOString()
    })
    .eq('share_token', token)
  
  // 4. Return sanitized data
  return new Response(JSON.stringify({
    audio_url: audioUrl.signedUrl,
    duration: share.jobs.audio_duration,
    date: share.jobs.local_date,
    length_minutes: Math.round(share.jobs.daystart_length / 60)
  }), {
    headers: { 
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': 'https://daystartai.app'
    }
  })
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

### Edge Function for Creating Shares

You'll also need a `create_share` edge function to generate share tokens from the iOS app:

**`supabase/functions/create_share/index.ts`:**
```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { job_id, duration_hours = 48 } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // Generate secure random token
  const share_token = crypto.randomUUID().replace(/-/g, '')
  
  // Set expiry
  const expires_at = new Date()
  expires_at.setHours(expires_at.getHours() + duration_hours)
  
  // Get user_id from job
  const { data: job } = await supabase
    .from('jobs')
    .select('user_id')
    .eq('job_id', job_id)
    .single()
  
  if (!job) {
    return new Response(JSON.stringify({ error: 'Job not found' }), { 
      status: 404 
    })
  }
  
  // Create share record
  const { error } = await supabase
    .from('public_daystart_shares')
    .insert({
      job_id,
      user_id: job.user_id,
      share_token,
      expires_at: expires_at.toISOString()
    })
  
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500 
    })
  }
  
  return new Response(JSON.stringify({
    share_url: `https://daystartai.app/shared/${share_token}`,
    token: share_token,
    expires_at: expires_at.toISOString()
  }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
```

### iOS Integration

Update the commented-out share functions in HomeView and AudioPlayerView to call the new create_share endpoint:

```swift
private func shareDayStart(_ dayStart: DayStartData) async {
    do {
        // 1. Create share via API
        let shareResponse = try await SupabaseClient.shared.createShare(jobId: dayStart.id)
        
        // 2. Create branded message
        let duration = Int(dayStart.duration / 60)
        let shareText = """
        🌅 Check out my DayStart! 
        
        \(duration) minutes of personalized morning intelligence:
        • News & market insights  
        • Weather & calendar
        • Daily motivation
        
        Listen: \(shareResponse.shareUrl)
        
        Get DayStart: https://daystartai.app
        
        #DayStart #MorningRoutine
        """
        
        // 3. Present share sheet
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        // ... existing share sheet presentation code
        
    } catch {
        // Handle error
        print("Failed to create share: \(error)")
    }
}
```

This gives you a complete branded, mobile-responsive audio player that maintains DayStart's visual identity while driving app downloads!