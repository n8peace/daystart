# App Store Connect Configuration for DayStart AI

## Basic Information
- **App Name:** DayStart AI: Morning Briefing
- **Subtitle:** News, Weather & Calendar
- **In Development:** 2026.02.18 (Build 1)
- **Current Version:** 2026.02.1 (Build 1) - **LIVE** on App Store as of Feb 1, 2026
- **Support URL:** https://daystart.bananaintelligence.ai
- **Marketing URL:** https://daystart.bananaintelligence.ai

## Keywords (100 characters max)
```
morning brief,ai news,daily briefing,news summary,weather,calendar,routine
```

## Promotional Text (170 characters max)
```
Wake up. Get briefed. Succeed. Your personalized AI morning brief with news, weather, and your calendar.
```

## App Description (4000 characters max)
```
DayStart delivers a 3-minute AI-generated morning briefing, read aloud every morning.

Get today's most important news, weather, calendar events, markets, and inspiration — personalized to you and ready the moment you wake up.

Instead of checking multiple apps, DayStart gives you one calm, focused briefing to start your day informed and ahead.

What's inside your daily brief:
• Top news and headlines
• Local weather forecast
• Your calendar and schedule
• Market and economic updates
• A short moment of focus or inspiration

Designed for leaders, DayStart helps you wake up with clarity, context, and momentum — before the day starts pulling at you.

Wake up. Get briefed. Succeed.

Privacy Policy: https://daystart.bananaintelligence.ai/privacy
Terms of Service: https://daystart.bananaintelligence.ai/terms
```

## What's New in Version 2026.02.01
```
SMARTER BRIEFINGS. TRAVEL INTELLIGENCE. EXECUTIVE DELIVERY.

NEW FEATURES:
• Travel Weather Intelligence - Automatically detects destinations from calendar events and delivers relevant forecasts ("In Chicago for your Wednesday meeting, expect temps in the 30s")
• Dynamic Content Sequencing - Your briefing now leads with what matters most TODAY (travel days prioritize destination weather, packed schedules lead with calendar overview)
• Cross-Domain Synthesis - Intelligent connections across categories ("Tesla up 4%—that announcement is trending")

DELIVERY IMPROVEMENTS:
• Executive Assistant Tone - Briefings now feel like someone prepared intelligence FOR you, not reading AT you
• Smarter Weather - Only mentions notable conditions worth knowing, skips boring stretches
• Multi-Location Forecasting - Parses calendar events for travel destinations, delivers weather for everywhere you need to be

PERFORMANCE:
• 67% Faster Generation - Parallel processing for travel weather and calendar data
• Enhanced AI Prompting - Better context awareness and priority signaling

Your morning intelligence platform—now anticipates where you're going and what you need to know.
```

## Categories
- **Primary:** Productivity
- **Secondary:** News

## Age Rating
- **13+**

## Terms of Use (EULA)
- **URL:** https://daystart.bananaintelligence.ai/terms
- **Note:** Custom EULA provided, not using Apple's standard agreement

## Privacy Policy
- **URL:** https://daystart.bananaintelligence.ai/privacy

## In-App Purchase Products

### Weekly Subscription
- **Product ID:** `daystart_weekly_subscription`
- **Reference Name:** DayStart Weekly
- **Price:** $1.99/week
- **Free Trial:** None
- **Description:** Get unlimited personalized morning briefings

### Monthly Subscription
- **Product ID:** `daystart_monthly_subscription`
- **Reference Name:** DayStart Monthly
- **Price:** $4.99/month
- **Free Trial:** 3 days
- **Description:** Get unlimited personalized morning briefings

### Annual Subscription  
- **Product ID:** `daystart_annual_subscription`
- **Reference Name:** DayStart Annual
- **Price:** $39.99/year
- **Free Trial:** 7 days
- **Description:** Get unlimited personalized morning briefings (Save 33%)

## Subscription Group
- **Reference Name:** DayStart Premium
- **Description:** Unlock your Personal Morning Brief, the same intelligence advantage used by successful leaders worldwide. Transform how you start each day

### Weekly Subscription - Localization (English)
- **Display Name:** Weekly Leadership Pass
- **Description:** Get your Personal Morning Brief delivered daily. Perfect for trying our premium intelligence platform with minimal commitment. No trial - immediate access.

### Monthly Subscription - Localization (English)
- **Display Name:** Monthly Leadership Pass
- **Description:** Get your Personal Morning Brief delivered daily. Join successful professionals who start each day with intelligence, not information overload. Includes 3-day free trial.

### Annual Subscription - Localization (English)  
- **Display Name:** Annual Leadership Pass
- **Description:** Get your Personal Morning Brief delivered daily. The choice of leaders who invest in their morning advantage. Save 33% with 7-day free trial.

### Weekly Subscription - Review Notes
```
DayStart Weekly subscription provides unlimited access to personalized AI-generated morning briefings. Features include:

- Daily personalized audio briefings with weather, news, calendar events, and market updates
- Customizable content preferences
- Offline audio download and playback
- Background audio generation and scheduling
- No free trial - immediate access upon purchase

To test: Use sandbox account, tap "Weekly Pass" on paywall screen (first option, pre-selected), complete purchase flow. Note continue button shows "Continue for $1.99" (not "Start Free Trial"). Audio generation requires network connectivity and may take 2-3 minutes for first briefing.
```

### Monthly Subscription - Review Notes
```
DayStart Monthly subscription provides unlimited access to personalized AI-generated morning briefings. Features include:

- Daily personalized audio briefings with weather, news, calendar events, and market updates
- Customizable content preferences 
- Offline audio download and playback
- Background audio generation and scheduling
- 3-day free trial included

To test: Use sandbox account, tap "Monthly Pass" on paywall screen, complete purchase flow. Audio generation requires network connectivity and may take 2-3 minutes for first briefing.
```

### Annual Subscription - Review Notes
```
DayStart Annual subscription provides unlimited access to personalized AI-generated morning briefings with significant savings vs monthly. Features include:

- Daily personalized audio briefings with weather, news, calendar events, and market updates  
- Customizable content preferences
- Offline audio download and playback
- Background audio generation and scheduling
- 7-day free trial included
- 33% savings compared to monthly subscription

To test: Use sandbox account, tap "Annual Pass" on paywall screen, complete purchase flow. Audio generation requires network connectivity and may take 2-3 minutes for first briefing.
```

## App Store Connect Configuration

### App Information Settings
1. **Content Rights**: Select "No, it does not contain, show, or access third-party content"
2. **Age Rating**: 13+ (no objectionable content)
3. **App Encryption Documentation**: 
   - Select "Yes" (uses HTTPS)
   - Choose "Only using encryption for HTTPS calls"
   - Add to Info.plist: `ITSAppUsesNonExemptEncryption = false` ✓
4. **Digital Services Act**: 
   - Select "Trader" (selling subscriptions)
   - Provide business name, address, phone, email
5. **App Server Notifications**: Skip (leave blank)
6. **App-Specific Shared Secret**: Skip (leave blank)

### Privacy Settings (Data Collection)
Select **Yes** for data collection with these categories:
1. **Location → Coarse Location**: For weather updates (App Functionality)
2. **Sensitive Info**: Calendar events for briefing context (App Functionality)
3. **Identifiers → User ID**: Purchase receipt ID (App Functionality)
4. **Diagnostics → Other Diagnostic Data**: Optional feedback diagnostics (App Functionality)

All data: Linked to identity via receipt ID, NOT used for tracking

### TestFlight Setup
- Beta testers access the full app without App Store review
- Testers use sandbox Apple IDs for free StoreKit testing
- Purchases in TestFlight are free (sandbox environment)
- No special configuration needed - uses same StoreKit setup

## Pre-Submission Checklist

### Critical Items (Will Cause Rejection) - UPDATED
- [x] No `simulatePurchase` function found in PurchaseManager.swift ✓
- [x] Privacy Policy live at https://daystart.bananaintelligence.ai/privacy ✓ 
- [x] Terms of Service live at https://daystart.bananaintelligence.ai/terms ✓
- [x] Wire up paywall buttons (Restore, Terms, Privacy) ✓
- [x] Fix Info.plist background modes ✓
- [x] NSCalendarsUsageDescription added to Info.plist ✓
- [x] Swift 6 concurrency issues resolved ✓
- [x] Product IDs updated to daystart_monthly_subscription & daystart_annual_subscription ✓
- [x] Paywall text updated to "Skip the scrolling, get briefed" ✓
- [x] dSYM generation settings added ✓
- [x] Test app works without purchase (good empty state)
- [x] Complete subscription metadata in App Store Connect
- [x] Ensure Supabase backend is running during review

### App Store Review Notes - Version 2026.02.01
```
QUICK TEST:
1. Complete onboarding → Start subscription (Weekly $1.99 or try Monthly/Annual with free trial)
2. Add calendar events with TRAVEL LOCATIONS to test new intelligence features:
   - Add event: "Flight to Chicago" or use location field "New York, NY" for dates 2-3 days out
   - Add event: "Meeting in San Francisco" with location for tomorrow
3. Generate briefing (2-3 minutes) → Listen for:
   - Travel weather mentions ("In Chicago for your Wednesday meeting, expect temps in the 30s")
   - Executive assistant tone (authoritative, direct, no filler commentary)
   - Dynamic sequencing (briefing leads with travel context when you have upcoming trips)
   - Cross-domain connections (stocks + news synthesis, calendar + weather integration)
4. Test different scenarios:
   - Packed calendar (5+ events) → Briefing should lead with schedule overview
   - Travel day → Should prioritize destination weather
   - Routine day → Standard weather → calendar → news flow

POSITIONING:
DayStart AI delivers a Personal Morning Brief that now intelligently adapts to YOUR day. Travel briefings prioritize destination weather. Packed days lead with schedule context. The AI acts like an executive assistant who researched, filtered, and connected the dots.

KEY FEATURES:
- 3 minute audio intelligence briefs
- NEW: Travel weather detection from calendar events
- NEW: Dynamic content sequencing based on daily context
- NEW: Executive assistant delivery style
- Personalized to each user's priorities
- Professional voice synthesis via OpenAI TTS and ElevenLabs
- No login required, privacy-first approach

WHAT'S NEW IN 2026.02.01:
- TRAVEL WEATHER INTELLIGENCE: Automatically detects travel destinations from calendar (parses "Flight to Chicago", location fields) and delivers relevant weather forecasts
- DYNAMIC CONTENT SEQUENCING: Briefing adapts opening based on what matters TODAY (travel days prioritize destination weather, packed schedules lead with calendar)
- EXECUTIVE ASSISTANT TONE: Shifted from "morning DJ" to "prepared intelligence briefing" delivery style
- CROSS-DOMAIN SYNTHESIS: AI connects related information ("Tesla up 4%—that announcement is trending", "Chicago meeting Thursday—pack for thirties")
- PERFORMANCE: 67% faster travel weather processing via parallel geocoding and API calls
- PRIVACY: Enhanced weather data cleanup after job completion
- Core functionality unchanged: scheduling, audio generation, news/sports selection work as in previous version

WEATHERKIT:
- Yes, app uses WeatherKit for weather data
- NEW: Multi-location weather for travel destinations detected from calendar
- Weather plays automatically in every briefing (no navigation needed)
- Toggle weather: Onboarding page 5 or Edit screen
- Apple Weather attribution properly displayed

SUBSCRIPTIONS:
- Product IDs: daystart_weekly_subscription, daystart_monthly_subscription, daystart_annual_subscription
- Free trials: None (weekly), 3-day (monthly), 7-day (annual)
- No login required, uses StoreKit receipt IDs

BACKGROUND PROCESSING:
Essential for prefetching audio before scheduled wake time using BGTaskScheduler. Prevents playback delays and enables offline functionality.

PERMISSIONS (BOTH OPTIONAL):
- Location: Weather updates (now includes travel destinations)
- Calendar: Event summaries + NEW travel destination detection
- App works fully without any permissions (graceful degradation)

CONTACT: nate@bananaintelligence.ai
```