# DayStart AI

Your Personal Morning Brief. The intelligence advantage that successful leaders use to start each day.

DayStart AI delivers personalized 3-minute audio briefings with news, markets, weather, and calendar events. Built for ambitious professionals who value their time and want to start each day informed, not overwhelmed.

Built with SwiftUI, Supabase backend, OpenAI GPT-4o-mini for content generation, OpenAI TTS (primary) and ElevenLabs (fallback) for voice synthesis.

## 🚀 App Store Status

**Production**: Live on App Store (v2026.02.1 Build 1) as of February 1, 2026
- ✅ Backend deployed and tested in production with receipt-based authentication
- ✅ App Store Connect configured with subscription products (Weekly $1.99, Monthly $4.99, Annual $39.99)
- ✅ Privacy manifest (PrivacyInfo.xcprivacy) and StoreKit 2 integration complete
- ✅ Legal documents hosted at daystart.bananaintelligence.ai
- ✅ Subtitle: "News, Weather & Calendar" - optimized for App Store search
- ✅ Streamlined app description (600 chars) for clarity and conversion
- ✅ 3-minute intelligence briefings with dynamic content scaling
- ✅ Welcome Brief for new users (60-second personalized introduction)
- ✅ Firebase Analytics integration with lazy loading architecture

**Latest Production Release**: v2026.02.1 Build 1 (February 1, 2026)
- New: Calendar-based weather forecasting with travel detection
- New: Authoritative briefing tone (executive assistant vs morning DJ)
- New: EA intelligence enhancement with dynamic sequencing and synthesis
- Enhanced: Multi-location weather with geocoding and WeatherKit integration
- Enhanced: Script generation variety and professionalism
- Changed: App Store metadata optimization for better discoverability

**In Development**: v2026.02.18 Build 1

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Environment Setup](#environment-setup)
- [Deployment](#deployment)
- [Usage](#usage)
- [Contributing](#contributing)

## Features

### ✅ Complete Executive Experience
- **Personal Morning Brief**: 3-minute intelligence briefings tailored to your priorities
- **Welcome Brief**: 60-second personalized introduction for first-time users
- **Smart Scheduling**: Set your brief time and preferred days
- **Live Countdown**: Always know when your next brief arrives
- **Instant Playback**: Pre-downloaded audio ready when you wake up
- **Professional Controls**: Full playback with seek, skip ±10s, and speed adjustment (0.5x-2.0x)
- **Brief History**: Access past briefings with full transcripts
- **Leadership Streak**: Track your consistency like successful professionals do

### ✅ Intelligence & Personalization
- **Weather Intelligence**: Hyperlocal conditions and smart forecasts
- **Calendar Analysis**: Your day's priorities, crystallized
- **News Curation**: Top headlines filtered for relevance, not volume
- **Market Updates**: Track your portfolio and key indices (S&P 500, Dow Jones)
- **Sports Results**: Updates from teams you actually follow
- **Daily Motivation**: Thoughtful quotes to start strong
- **Professional Voices**: 3 natural AI voices (Grace, Rachel, Matthew) via OpenAI TTS and ElevenLabs
- **3-Minute Promise**: Precisely crafted briefs that respect your time

### ✅ Intelligent Brief Generation
- **Smart Content Balance**: Optimized allocation across all brief sections
- **Relevance Engine**: Location-aware news selection and prioritization
- **Context Awareness**: Important background included when needed
- **Natural Narration**: Scripts crafted for professional voice synthesis
- **Executive Summary Style**: Information density without overwhelm

### ✅ Advanced Technical Features
- **Background Audio Prefetching**: BGTaskScheduler integration for seamless playback
- **Three-Tier Download Strategy**: Background, foreground, and just-in-time loading
- **Audio Caching**: Local file management prevents re-downloads
- **Network Resilience**: Graceful handling of connectivity issues
- **Timeout Handling**: User-friendly error messages when generation takes too long
- **Haptic Feedback**: Contextual haptic responses throughout the app
- **Local Notifications**: Reminder and ready notifications
- **Portrait-Only Design**: Optimized for morning routine usage
- **StoreKit 2 Integration**: Modern subscription handling with receipt-based auth
- **Privacy Manifest**: Full compliance with Apple's privacy requirements

### ✅ Backend Infrastructure
- **Supabase Integration**: Production-ready backend with PostgreSQL and receipt-based authentication
- **Advanced Job Queue System**: `FOR UPDATE SKIP LOCKED` for scalable processing with retry logic
- **Intelligent Content Caching**: Hourly content refresh with deduplication and source trust scoring
- **Professional Brief Generation**: 
  - OpenAI GPT-4o-mini for intelligent script creation
  - OpenAI TTS (alloy voice) as primary TTS provider
  - ElevenLabs eleven_turbo_v2_5 as fallback TTS
  - 3-minute briefs with optimal content mix
  - Smart summarization that captures what matters
- **Automated Cleanup**: Scheduled cleanup of old audio files and data with RLS policies
- **Comprehensive Cost Tracking**: Monitoring of OpenAI and ElevenLabs usage with detailed logging
- **Timezone Handling**: Accurate date/time calculations across timezones with local date awareness
- **Daily Generic DayStart**: Automated daily audio briefing at 4:45 AM ET for non-personalized content

## Requirements

### iOS App
- **Minimum iOS Version**: iOS 17.0+
- **Supported Devices**: iPhone only
- **Orientation**: Portrait only
- **Permissions**: Location (when in use), Calendar (full access)

### Backend
- **Supabase**: PostgreSQL database and edge functions with receipt-based authentication
- **OpenAI API**: GPT-4o-mini for script generation + TTS-1 model for voice synthesis
- **ElevenLabs API**: Fallback text-to-speech using eleven_turbo_v2_5 model
- **Deno**: For Supabase edge functions with TypeScript support

## Architecture

### iOS App Architecture
```
DayStart iOS App
├── Lazy Service Loading (Spotify-style performance)
├── Background Audio Prefetching (BGTaskScheduler)
├── Local Data Persistence (UserDefaults + Core Data)
├── Network Layer (Supabase client)
└── Audio Management (AVFoundation)
```

### Backend Architecture
```
Supabase Backend
├── Edge Functions (TypeScript)
│   ├── create_job (Job creation)
│   ├── process_jobs (Script + audio generation)
│   ├── get_audio_status (Download status)
│   ├── refresh_content (Content updates)
│   └── cleanup-audio (File management)
├── PostgreSQL Database
│   ├── jobs (Processing queue)
│   ├── content_cache (News/sports/stocks)
│   ├── streak_tracking (User progress)
│   └── daystart_history (Past briefings)
└── Storage Bucket (Audio files)
```

## Project Structure

```
DayStart/
├── DayStart/
│   ├── App/
│   │   └── DayStartApp.swift           # App entry point with deferred loading
│   ├── Features/
│   │   ├── Home/
│   │   │   ├── HomeView.swift          # Main interface
│   │   │   ├── HomeViewModel.swift     # State management
│   │   │   └── AudioPlayerView.swift   # Playback controls
│   │   ├── EditSchedule/
│   │   │   ├── EditScheduleView.swift  # Settings & schedule
│   │   │   └── VoicePickerView.swift   # Voice selection
│   │   ├── History/
│   │   │   └── HistoryView.swift       # Past DayStarts
│   │   └── Onboarding/
│   │       └── OnboardingView.swift    # Welcome flow & paywall
│   ├── Core/
│   │   ├── Models/
│   │   │   └── DayStartModels.swift    # Data models
│   │   ├── Services/
│   │   │   ├── AudioPlayerManager.swift      # Audio playback
│   │   │   ├── AudioPrefetchManager.swift    # Background downloads
│   │   │   ├── AudioCache.swift              # Local file management
│   │   │   ├── SupabaseClient.swift          # Backend communication
│   │   │   ├── LocationManager.swift         # WeatherKit integration
│   │   │   ├── CalendarManager.swift         # EventKit integration
│   │   │   ├── NotificationScheduler.swift   # Local notifications
│   │   │   ├── StreakManager.swift           # Progress tracking
│   │   │   ├── NetworkMonitor.swift          # Connectivity monitoring
│   │   │   └── ServiceRegistry.swift         # Lazy service loading
│   │   └── Theme/
│   │       └── BananaTheme.swift       # Design system
│   ├── Resources/
│   │   └── Audio/
│   │       └── Samples/                # Voice preview samples
│   └── Services/
│       └── WelcomeDayStartScheduler.swift # First-time experience
├── supabase/
│   ├── functions/                      # Edge functions
│   ├── migrations/                     # Database schema
│   └── storage/                        # Storage bucket config
└── Documentation/
    ├── REQUIREMENTS.md                 # System requirements
    ├── PRIVACY_POLICY.md              # Privacy policy document
    ├── TERMS_OF_SERVICE.md            # Terms of service document
    ├── app-store-metadata.md          # Complete App Store submission data
    ├── claude_app_readiness_plan.md   # Comprehensive deployment checklist
    └── claude-*.md                     # Implementation guides
```

## Installation

### 1. iOS App Setup

1. **Clone the repository**:
   ```bash
   git clone [repository-url]
   cd DayStart
   ```

2. **Open in Xcode**:
   ```bash
   open DayStart.xcodeproj
   ```

3. **Remove test code before submission**:
   - Delete `simulatePurchase` function from `PurchaseManager.swift`

4. **Configure capabilities in Xcode**:
   - Background Modes: Audio, Processing (only these two)
   - Location Services
   - Calendar Access

5. **Update bundle identifier** and development team in project settings

6. **Configure StoreKit**:
   - The project includes `DayStart.storekit` configuration file
   - Enable StoreKit testing in scheme: Edit Scheme → Run → Options → StoreKit Configuration
   - Products configured:
     - `daystart_monthly_subscription` ($4.99/month, 3-day free trial)
     - `daystart_annual_subscription` ($39.99/year, 7-day free trial, save 33%)
   - Receipt-based authentication system eliminates need for traditional user accounts

### 2. Supabase Backend Setup

1. **Create Supabase project**:
   - Go to [supabase.com](https://supabase.com)
   - Create new project
   - Note your project URL and anon key

2. **Install Supabase CLI**:
   ```bash
   npm install -g supabase
   ```

3. **Initialize Supabase locally**:
   ```bash
   supabase login
   supabase link --project-ref your-project-ref
   ```

4. **Deploy database schema**:
   ```bash
   supabase db push
   ```

5. **Deploy edge functions**:
   ```bash
   supabase functions deploy
   ```

6. **Configure storage bucket**:
   ```bash
   supabase storage create-bucket daystart-audio --public false
   ```

## Environment Setup

### iOS App Configuration

1. **Update Info.plist** with your Supabase credentials:
   ```xml
   <key>SupabaseBaseURL</key>
   <string>https://your-project.supabase.co</string>
   <key>SupabaseAnonKey</key>
   <string>your-anon-key</string>
   ```

### Supabase Environment Variables

Set the following secrets in your Supabase dashboard:

```bash
OPENAI_API_KEY=your-openai-api-key
ELEVENLABS_API_KEY=your-elevenlabs-api-key
NEWS_API_KEY=your-news-api-key (optional)
SPORTS_API_KEY=your-sports-api-key (optional)
```

### Required API Keys

1. **OpenAI API Key**: 
   - Go to [platform.openai.com](https://platform.openai.com)
   - Create API key with GPT-4o-mini and TTS access

2. **ElevenLabs API Key**:
   - Go to [elevenlabs.io](https://elevenlabs.io)
   - Create account and get API key

3. **Optional APIs**:
   - News API for enhanced news content
   - Sports API for detailed sports scores

## Deployment

### Production Deployment

1. **Configure production environment**:
   ```bash
   supabase secrets set OPENAI_API_KEY=your-key
   supabase secrets set ELEVENLABS_API_KEY=your-key
   ```

2. **Enable cron jobs** for content refresh:
   ```sql
   -- Runs every hour to refresh content
   SELECT cron.schedule('refresh-content', '0 * * * *', 'SELECT refresh_content_cache();');
   
   -- Runs daily to clean up old audio files
   SELECT cron.schedule('cleanup-audio', '0 2 * * *', 'SELECT cleanup_old_audio_files();');
   ```

3. **Configure external cron service** (e.g., cron-job.org) for daily generic DayStart:
   - URL: `https://YOUR_PROJECT.supabase.co/functions/v1/create_job`
   - Schedule: `45 4 * * *` (4:45 AM ET daily)
   - Method: POST
   - Headers:
     ```json
     {
       "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY",
       "x-client-info": "DAILY_GENERIC",
       "Content-Type": "application/json"
     }
     ```
   - Body: See technical documentation for configuration details

4. **Configure RLS policies** for security (already included in migrations)

### iOS App Store Preparation

1. **App Store Connect Setup**:
   - ✅ App record created with comprehensive metadata
   - ✅ App icon (1024x1024) uploaded
   - ✅ In-App Purchase products configured ($4.99/month, $39.99/year)
   - ✅ Privacy manifest (PrivacyInfo.xcprivacy) included
   - ✅ StoreKit configuration ready for testing
   - ✅ Receipt-based authentication system implemented

2. **Legal Documentation**:
   - ✅ Privacy Policy template created ([PRIVACY_POLICY.md](PRIVACY_POLICY.md))
   - ✅ Terms of Service template created ([TERMS_OF_SERVICE.md](TERMS_OF_SERVICE.md))
   - ⚠️ **IMPORTANT**: Replace all [bracketed] placeholders with real information
   - ⚠️ **IMPORTANT**: Host documents at:
     - https://daystart.bananaintelligence.ai/privacy
     - https://daystart.bananaintelligence.ai/terms
   - ✅ Complete App Store metadata prepared ([app-store-metadata.md](app-store-metadata.md))

3. **Pre-Submission Checklist**:
   - [x] Remove `simulatePurchase` function (not present in codebase)
   - [x] Paywall buttons already wired up in OnboardingView.swift
   - [x] Info.plist background modes already correct (audio, processing only)
   - [x] Legal documents updated with Banana Intelligence, LLC info
   - [x] App screenshots completed
   - [x] App Privacy and Content Rights configured in App Store Connect
   - [x] Upload build to App Store Connect
   - [ ] TestFlight testing and feedback collection

4. **Build and Submit**:
   - Build and archive in Xcode
   - Upload to App Store Connect via Xcode
   - Test with TestFlight
   - Submit for App Store review

📋 **Complete submission checklist**: See TECHNICAL_DOCUMENTATION.md for full deployment details

## Usage

### For Users

1. **Onboarding**: Complete the welcome flow to set preferences
2. **Schedule**: Set your wake time and preferred days
3. **Customize**: Choose voice, content types, and briefing length
4. **Enjoy**: Your DayStart will be ready each morning automatically

### For Developers

1. **Local Development**: Use Supabase local development environment
2. **Testing**: Run unit tests and UI tests in Xcode
3. **Debugging**: Enable debug logging in the app for detailed logs
4. **Monitoring**: Check Supabase dashboard for backend metrics

## Key Technical Decisions

### Performance Optimizations
- **Lazy service loading**: Only essential services load at startup
- **Background prefetching**: Audio downloads before user wakes up via BGTaskScheduler
- **Local caching**: Prevents unnecessary re-downloads with AudioCache
- **Receipt-based auth**: No user accounts needed - StoreKit receipt ID as user identity
- **Debounced state updates**: Smooth UI transitions

### User Experience
- **Immediate welcome experience**: First DayStart auto-starts after onboarding
- **Graceful error handling**: User-friendly messages for timeouts and errors
- **Offline capability**: Cached audio works without internet
- **Consistent design**: Banana-themed design system throughout

### Backend Reliability
- **Job queue system**: FOR UPDATE SKIP LOCKED with 15-minute leases
- **Priority system**: Welcome (100), urgent (75), regular (50), background (25)
- **Automatic retries**: 3 attempts before marking failed
- **Content caching**: 7-day cache with hourly refresh
- **Cost tracking**: OpenAI and ElevenLabs usage monitoring
- **Storage management**: 10-day retention with orphan cleanup

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Download DayStart AI

**Ready to start your mornings with intelligence?**

🌅 **[Download DayStart AI from the App Store](https://apps.apple.com/app/apple-store/id6751055528)**

Join thousands of ambitious professionals who start each day informed, not overwhelmed. Get your personalized 3-minute morning brief delivered with AI-powered voice synthesis.

- ✅ **Free 7-day trial** - No commitment required
- ⚡ **3-minute promise** - Complete intelligence briefing in under 3 minutes
- 🎯 **Personalized content** - News, weather, calendar, and motivation tailored to you
- 🔊 **Professional voices** - Broadcast-quality AI narration via OpenAI TTS and ElevenLabs

Available now on the App Store for iPhone.

---

## Support

For questions or support, please open an issue in the GitHub repository.