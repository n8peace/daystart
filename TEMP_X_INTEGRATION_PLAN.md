# DayStart X/Twitter Integration Plan

## Overview
Integration of X/Twitter social feeds into DayStart's morning briefings. Users can connect their X account to receive personalized highlights from their timeline and trending topics, delivered as a 1-minute section in their daily briefing.

**Approach**: Lightweight implementation using home timeline + trending topics (2-3 API calls per user per day)

## Phase 1: Core Integration

### 1. X Developer Setup

#### Requirements
- X Developer account application with DayStart business details
- **Tier**: Basic ($200/month, 15K reads/month = ~300-500 users)
- **App Configuration**:
  - OAuth 2.0 with PKCE enabled
  - Callback URLs: `daystart://x-auth-callback`
  - Permissions: Read tweets, Read users
  - Rate limits: 15K reads/month, 300 requests per 15-minute window

#### API Endpoints Used
- `GET /2/users/me` - User profile info (1 call per auth)
- `GET /2/users/:id/tweets` - Home timeline (1 call per day per user)
- `GET /2/trends/by/woeid` - Trending topics (1 call per day, cached globally)

### 2. Database Schema Changes

#### Extend Existing Tables
```sql
-- Add to purchase_users or user preferences
ALTER TABLE purchase_users ADD COLUMN social_twitter_enabled boolean DEFAULT false;

-- Add to jobs table
ALTER TABLE jobs ADD COLUMN include_twitter boolean DEFAULT false;
ALTER TABLE jobs ADD COLUMN twitter_user_id varchar(50);
```

#### New Tables
```sql
-- Social platform connections
CREATE TABLE social_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES purchase_users(id) ON DELETE CASCADE,
  platform varchar(20) DEFAULT 'twitter',
  twitter_user_id varchar(50) NOT NULL,
  username varchar(50) NOT NULL,
  access_token text NOT NULL,
  refresh_token text,
  expires_at timestamp with time zone,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT NOW(),
  updated_at timestamp with time zone DEFAULT NOW(),
  UNIQUE(user_id, platform)
);

-- Cached social content
CREATE TABLE social_content_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES purchase_users(id) ON DELETE CASCADE,
  platform varchar(20) DEFAULT 'twitter',
  content_type varchar(30) NOT NULL, -- 'home_timeline', 'trending_topics'
  raw_content jsonb,
  processed_content text,
  expires_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT NOW(),
  UNIQUE(user_id, platform, content_type)
);

-- Global trending cache (shared across users)
CREATE TABLE trending_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform varchar(20) DEFAULT 'twitter',
  location_woeid varchar(20) DEFAULT '1', -- 1 = worldwide
  trends jsonb,
  expires_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT NOW(),
  UNIQUE(platform, location_woeid)
);
```

#### RLS Policies
```sql
-- Social connections - users can only see their own
ALTER TABLE social_connections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own social connections" ON social_connections
  FOR ALL USING (auth.uid() = user_id);

-- Social content cache - users can only see their own
ALTER TABLE social_content_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own social content" ON social_content_cache
  FOR ALL USING (auth.uid() = user_id);

-- Trending cache - readable by service role only
ALTER TABLE trending_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role can access trending cache" ON trending_cache
  FOR ALL USING (auth.role() = 'service_role');
```

### 3. iOS Frontend Implementation

#### A. Onboarding Enhancement

**New Page: `SocialOnboardingView.swift`**
- **Location**: After existing onboarding flow, before completion
- **UI Elements**:
  - Header: "Connect Your Social Feeds (Optional)"
  - Subtitle: "Get personalized highlights from what's trending in your network"
  - X Logo with "Connect X/Twitter" button
  - "Skip for now" button
- **Functionality**:
  - OAuth web view integration
  - Keychain token storage
  - Success state with @username confirmation

#### B. EditScheduleView Updates

**Social Section Addition**:
```swift
// Add after existing toggles (Quotes, Stocks)
VStack(alignment: .leading, spacing: 12) {
    Text("Social Feeds")
        .font(.headline)
        .foregroundColor(.primary)
    
    HStack {
        Image("x-logo") // X/Twitter logo
            .frame(width: 24, height: 24)
        
        VStack(alignment: .leading) {
            Text("X/Twitter Highlights")
                .font(.body)
            if let username = socialViewModel.twitterUsername {
                Text("Connected as @\(username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        Spacer()
        
        if socialViewModel.isTwitterConnected {
            Toggle("", isOn: $viewModel.preferences.socialTwitterEnabled)
                .labelsHidden()
        } else {
            Button("Connect") {
                socialViewModel.connectTwitter()
            }
            .bananaSecondaryButton()
        }
    }
    .padding()
    .bananaCardStyle()
}
```

**Duration Calculation Update**:
```swift
// In EditScheduleViewModel
var estimatedDuration: Int {
    var duration = baseDuration
    if preferences.quotesEnabled { duration += 30 }
    if preferences.stocksEnabled { duration += 30 }
    if preferences.socialTwitterEnabled { duration += 60 } // New
    return duration
}
```

#### C. Social Authentication Flow

**New ViewModel: `SocialViewModel.swift`**
```swift
@MainActor
class SocialViewModel: ObservableObject {
    @Published var isTwitterConnected = false
    @Published var twitterUsername: String?
    @Published var isAuthenticating = false
    
    func connectTwitter() {
        // OAuth 2.0 PKCE flow
        // Store tokens in Keychain
        // Update user preferences
    }
    
    func disconnectTwitter() {
        // Remove tokens from Keychain
        // Update user preferences
        // Clear cached content
    }
}
```

#### D. Security Implementation

**Keychain Storage**:
```swift
// Add to existing KeychainManager
extension KeychainManager {
    func storeTwitterTokens(accessToken: String, refreshToken: String?) {
        store(accessToken, for: "twitter_access_token")
        if let refresh = refreshToken {
            store(refresh, for: "twitter_refresh_token")
        }
    }
    
    func getTwitterAccessToken() -> String? {
        return retrieve("twitter_access_token")
    }
}
```

### 4. Backend Implementation

#### A. New Supabase Edge Functions

**`x_auth_callback.ts`**
```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { code, state } = await req.json()
  
  // Exchange authorization code for access token
  const tokenResponse = await exchangeCodeForTokens(code)
  
  // Get user info from X API
  const userInfo = await getTwitterUserInfo(tokenResponse.access_token)
  
  // Store connection in database
  await storeTwitterConnection({
    user_id: getUserIdFromState(state),
    twitter_user_id: userInfo.id,
    username: userInfo.username,
    access_token: tokenResponse.access_token,
    refresh_token: tokenResponse.refresh_token,
    expires_at: new Date(Date.now() + tokenResponse.expires_in * 1000)
  })
  
  return new Response(JSON.stringify({ success: true, username: userInfo.username }))
})
```

**`refresh_social_content.ts` (extends existing)**
```typescript
// Add to existing refresh_content function
async function refreshSocialContent() {
  // Get all active Twitter connections
  const connections = await getActiveTwitterConnections()
  
  // Refresh global trending topics (once per refresh cycle)
  await refreshTrendingTopics()
  
  // Process each user's timeline
  for (const connection of connections) {
    try {
      // Fetch home timeline (15 most recent tweets)
      const timeline = await fetchTwitterTimeline(connection.access_token, 15)
      
      // Process and cache content
      await cacheUserTimeline(connection.user_id, timeline)
      
    } catch (error) {
      console.error(`Failed to refresh content for user ${connection.user_id}:`, error)
      // Continue processing other users
    }
  }
}

async function fetchTwitterTimeline(accessToken: string, maxResults: number = 15) {
  const response = await fetch(`https://api.twitter.com/2/users/me/tweets?max_results=${maxResults}&tweet.fields=public_metrics,created_at,author_id&expansions=author_id`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  })
  
  if (!response.ok) {
    throw new Error(`Twitter API error: ${response.status}`)
  }
  
  return await response.json()
}

async function refreshTrendingTopics() {
  // Fetch global trending topics (WOEID 1 = worldwide)
  const response = await fetch('https://api.twitter.com/2/trends/by/woeid/1', {
    headers: {
      'Authorization': `Bearer ${process.env.TWITTER_BEARER_TOKEN}`
    }
  })
  
  const trends = await response.json()
  
  // Cache for 6 hours (trends change frequently)
  await supabase
    .from('trending_cache')
    .upsert({
      platform: 'twitter',
      location_woeid: '1',
      trends: trends.data,
      expires_at: new Date(Date.now() + 6 * 60 * 60 * 1000) // 6 hours
    })
}
```

#### B. Job Creation Updates

**Modify `create_job.ts`**
```typescript
// Add social settings check
const socialSettings = await getUserSocialSettings(userId)
const twitterConnection = await getActiveTwitterConnection(userId)

const jobData = {
  user_id: userId,
  // ... existing fields
  include_twitter: socialSettings.social_twitter_enabled && twitterConnection?.is_active,
  twitter_user_id: twitterConnection?.twitter_user_id || null,
  created_at: new Date().toISOString()
}

async function getUserSocialSettings(userId: string) {
  const { data } = await supabase
    .from('purchase_users')
    .select('social_twitter_enabled')
    .eq('id', userId)
    .single()
  
  return data
}
```

#### C. Script Generation Updates

**Modify `process_jobs.ts`**
```typescript
// Add social content to script generation
if (job.include_twitter && job.twitter_user_id) {
  const socialContent = await getSocialContent(job.user_id)
  
  if (socialContent) {
    scriptPrompt += `\n\nSocial Context:\n${socialContent}`
    estimatedDuration += 60 // Add 1 minute for social section
  }
}

async function getSocialContent(userId: string) {
  // Get user's cached timeline
  const { data: timeline } = await supabase
    .from('social_content_cache')
    .select('processed_content')
    .eq('user_id', userId)
    .eq('content_type', 'home_timeline')
    .gt('expires_at', new Date().toISOString())
    .single()
  
  // Get global trending topics
  const { data: trending } = await supabase
    .from('trending_cache')
    .select('trends')
    .eq('platform', 'twitter')
    .gt('expires_at', new Date().toISOString())
    .single()
  
  if (!timeline && !trending) return null
  
  return {
    timeline: timeline?.processed_content,
    trending: trending?.trends?.slice(0, 5) // Top 5 trends
  }
}
```

### 5. AI Script Generation Enhancement

#### Prompt Modification
```typescript
const socialPromptAddition = `

SOCIAL MEDIA BRIEFING (60 seconds):
Based on the user's Twitter timeline and trending topics, create a social media briefing that includes:

1. PERSONAL HIGHLIGHTS (30 seconds):
   - Summarize 2-3 most engaging or relevant tweets from accounts they follow
   - Identify common themes or topics appearing in their timeline
   - Focus on content that would be interesting in a morning briefing context

2. TRENDING CONTEXT (30 seconds):
   - Explain 2-3 trending topics that are relevant to the user's interests
   - Provide brief context on why these topics are trending
   - Connect trends to the user's timeline interests when possible

Timeline Content: ${socialContent.timeline}
Trending Topics: ${JSON.stringify(socialContent.trending)}

Keep the tone conversational and morning-appropriate. Avoid controversial topics unless they're major news events.
`
```

### 6. Error Handling & Resilience

#### API Failure Scenarios
```typescript
// Rate limit handling
if (response.status === 429) {
  const resetTime = response.headers.get('x-rate-limit-reset')
  console.log(`Rate limited. Reset at: ${resetTime}`)
  // Fall back to cached content
  return getCachedContent(userId)
}

// Token expiration
if (response.status === 401) {
  // Attempt token refresh
  const refreshed = await refreshTwitterToken(connection.refresh_token)
  if (refreshed) {
    // Retry request with new token
    return retryWithNewToken(refreshed.access_token)
  } else {
    // Mark connection as inactive, notify user
    await deactivateTwitterConnection(connection.id)
  }
}
```

#### Graceful Degradation
- **No Social Content**: Continue with regular briefing
- **Partial Content**: Use timeline OR trending if one fails
- **Stale Cache**: Use expired cache with disclaimer
- **Connection Issues**: Show status in app, allow reconnection

### 7. Performance Optimization

#### Caching Strategy
- **Timeline Content**: 12-hour cache (refresh with other content)
- **Trending Topics**: 6-hour cache (more volatile)
- **User Profiles**: 7-day cache (username, profile changes)
- **Failed Requests**: 1-hour cache to avoid retrying broken connections

#### Batch Processing
```typescript
// Process all social users in batches during refresh cycle
const BATCH_SIZE = 50
const connections = await getActiveTwitterConnections()

for (let i = 0; i < connections.length; i += BATCH_SIZE) {
  const batch = connections.slice(i, i + BATCH_SIZE)
  
  // Process batch in parallel with rate limit awareness
  await Promise.allSettled(
    batch.map(connection => 
      processUserSocialContent(connection).catch(err => 
        console.error(`Failed for user ${connection.user_id}:`, err)
      )
    )
  )
  
  // Rate limit compliance: delay between batches
  await delay(60000) // 1 minute between batches
}
```

### 8. Privacy & Security

#### Data Minimization
- **Store only processed summaries**, not raw tweet content
- **Automatic cleanup** of expired cache entries
- **User-initiated deletion** when disconnecting accounts

#### Token Security
```typescript
// Encrypt tokens before storage
const encryptedToken = await encrypt(accessToken, process.env.ENCRYPTION_KEY)

// Rotate tokens proactively
const tokenAge = Date.now() - connection.created_at.getTime()
if (tokenAge > 7 * 24 * 60 * 60 * 1000) { // 7 days
  await refreshTwitterToken(connection.refresh_token)
}
```

#### Privacy Manifest Updates
```xml
<!-- Add to PrivacyInfo.xcprivacy -->
<key>NSPrivacyCollectedDataTypes</key>
<array>
  <dict>
    <key>NSPrivacyCollectedDataType</key>
    <string>NSPrivacyCollectedDataTypeOtherUsageData</string>
    <key>NSPrivacyCollectedDataTypeLinked</key>
    <false/>
    <key>NSPrivacyCollectedDataTypeTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypePurposes</key>
    <array>
      <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
    </array>
  </dict>
</array>
```

### 9. Testing Strategy

#### Unit Tests
- OAuth flow simulation
- Token refresh logic
- Content processing pipeline
- Cache expiration handling

#### Integration Tests
- End-to-end social content flow
- API rate limit simulation
- Error scenario handling
- Database constraint validation

#### Beta Testing Plan
- **Phase 1**: Internal testing (5-10 accounts)
- **Phase 2**: Closed beta (50-100 users)
- **Phase 3**: Feature flag rollout (gradual release)

### 10. Monitoring & Analytics

#### Key Metrics
```typescript
// Track in existing analytics
{
  event: 'social_content_generated',
  properties: {
    platform: 'twitter',
    timeline_tweets: number,
    trending_topics: number,
    processing_time_ms: number,
    cache_hit: boolean
  }
}

{
  event: 'social_api_error',
  properties: {
    platform: 'twitter',
    error_type: 'rate_limit' | 'auth_failure' | 'network_error',
    user_id: string
  }
}
```

#### Dashboard Monitoring
- **API Usage**: Calls per day vs rate limits
- **User Adoption**: % of users with connected accounts
- **Content Quality**: Social section engagement metrics
- **Error Rates**: Failed API calls, token refresh failures

### 11. Rollout Timeline

#### Week 1-2: Foundation
- [ ] X Developer account setup and app creation
- [ ] Database schema implementation
- [ ] Basic OAuth flow in iOS

#### Week 3-4: iOS Integration
- [ ] Onboarding page creation
- [ ] EditScheduleView social section
- [ ] SocialViewModel and authentication flow
- [ ] Keychain integration

#### Week 5-6: Backend Integration
- [ ] Edge functions for auth callback and content refresh
- [ ] Job creation and processing updates
- [ ] AI script generation enhancement
- [ ] Error handling and caching

#### Week 7-8: Testing & Polish
- [ ] Unit and integration tests
- [ ] Beta user testing
- [ ] Performance optimization
- [ ] UI/UX refinements

#### Week 9-10: Production Release
- [ ] Feature flag rollout
- [ ] Monitoring and analytics setup
- [ ] User feedback collection
- [ ] Premium pricing strategy implementation

### 12. Future Enhancements

#### Phase 2 Features
- **Multiple Social Platforms**: Instagram, LinkedIn, TikTok
- **Advanced Filtering**: Topic categories, sentiment analysis
- **Personalization**: ML-based content relevance scoring
- **Social Lists**: Curated lists for different content types

#### Premium Features
- **Extended Social Analysis**: Deeper timeline analysis
- **Custom Social Sources**: Specific accounts or lists
- **Social Scheduling**: Post timing suggestions
- **Social Metrics**: Personal engagement analytics

## Success Criteria

### Technical
- [ ] <2% API error rate
- [ ] <500ms social content processing time
- [ ] 95%+ cache hit rate for trending topics
- [ ] Zero security incidents with token handling

### Business
- [ ] 20%+ adoption rate among active users
- [ ] 15%+ improvement in user retention for social users
- [ ] $150+ monthly revenue to cover Basic tier costs
- [ ] 85%+ user satisfaction with social content quality

### User Experience
- [ ] <3 taps to connect social account
- [ ] <10 seconds to complete OAuth flow
- [ ] Seamless integration with existing briefing flow
- [ ] Clear value proposition and user education

---

**Total Estimated Development Time**: 8-10 weeks
**Estimated API Costs**: $200/month (Basic tier, ~300-500 users)
**Premium Revenue Target**: $600-1500/month (80-200 premium users at $7.99/month)