# DayStart

A personalized, AI-powered iOS morning briefing app that combines your local weather, news, sports, stocks, and motivational content into a custom audio briefing delivered with natural voices and ready the moment you wake up.

Built with SwiftUI, Supabase backend, OpenAI GPT-4, and ElevenLabs text-to-speech.

## 🚀 App Store Readiness Status

**Current Status**: Ready for final preparation before App Store submission
- ✅ Backend deployed and tested in production with receipt-based authentication
- ✅ App Store Connect configured with subscription products ($4.99/month, $39.99/year)
- ✅ Privacy manifest (PrivacyInfo.xcprivacy) and StoreKit 2 integration complete
- ✅ Legal documents prepared (need hosting): Privacy Policy and Terms of Service
- ✅ Comprehensive App Store metadata prepared (see [app-store-metadata.md](app-store-metadata.md))
- ✅ Enhanced script generation with longer, richer content (up to 6 news stories)
- 🔴 **Critical blockers**: See [App Readiness Plan](claude_app_readiness_plan.md#critical-review-blockers-fix-before-submission)

📋 **Complete readiness documentation**: [App Readiness Plan](claude_app_readiness_plan.md)

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

### ✅ Complete User Experience
- **Welcome Flow**: Guided onboarding with personalization setup
- **Auto-Start Welcome**: First DayStart automatically begins after onboarding
- **Smart Scheduling**: Flexible wake time and day selection with 4-hour lockout
- **Live Countdown**: Dynamic countdown to next DayStart with anticipation previews
- **Instant Playback**: Pre-downloaded audio for immediate start
- **Audio Controls**: Full playback controls with seek, skip ±10s, and speed adjustment (0.5x-2.0x)
- **History & Transcripts**: Access to past DayStarts with full transcripts and replay
- **Streak Tracking**: Visual progress tracking for daily consistency

### ✅ Content & Personalization
- **Weather Integration**: WeatherKit-powered local weather and forecasts
- **Calendar Events**: EventKit integration for today's schedule highlights
- **Enhanced News Coverage**: Up to 6 curated news stories with deeper context and local relevance
- **Sports**: Team-specific updates for favorite sports teams (up to 2 stories)
- **Stock Market**: Custom stock symbols with expanded market insights (up to 3 stories)
- **Enriched Motivational Quotes**: Daily inspiration with deeper reflection and context (150+ words)
- **Voice Selection**: 3 AI-generated voice options with high-quality ElevenLabs synthesis
- **Dynamic Length Control**: Intelligent content scaling (2-10 minutes) with priority-based expansion

### ✅ Enhanced Script Generation
- **Intelligent Content Allocation**: Dynamic word budgets that scale with briefing length
- **Priority-Based Expansion**: News and quotes prioritized for longer scripts
- **Local Relevance**: Smart news selection based on user location (neighborhood → city → state → national)
- **Context-Rich Content**: Longer briefings include deeper analysis and background
- **Advanced TTS Optimization**: Scripts optimized for natural speech patterns and pacing

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
- **Enhanced Audio Generation**: 
  - OpenAI GPT-4o-mini for cost-effective script generation
  - ElevenLabs eleven_flash_v2_5 TTS model for superior voice quality
  - Dynamic content scaling (6 news, 3 stocks, 150-word quotes)
  - Context-aware expansion and contraction algorithms
- **Automated Cleanup**: Scheduled cleanup of old audio files and data with RLS policies
- **Comprehensive Cost Tracking**: Monitoring of OpenAI and ElevenLabs usage with detailed logging
- **Timezone Handling**: Accurate date/time calculations across timezones with local date awareness

## Requirements

### iOS App
- **Minimum iOS Version**: iOS 17.0+
- **Supported Devices**: iPhone only
- **Orientation**: Portrait only
- **Permissions**: Location (when in use), Calendar (full access)

### Backend
- **Supabase**: PostgreSQL database and edge functions with receipt-based authentication
- **OpenAI API**: GPT-4o-mini for cost-effective script generation with dynamic scaling
- **ElevenLabs API**: Text-to-speech conversion using eleven_flash_v2_5 model
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
   - Push Notifications (for local notifications)
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
   - Create API key with GPT-4 access

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

3. **Configure RLS policies** for security (already included in migrations)

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
   - [ ] Remove `simulatePurchase` function from PurchaseManager.swift
   - [ ] Wire up paywall buttons (Restore, Terms, Privacy) in OnboardingView.swift
   - [ ] Fix Info.plist background modes (remove invalid entries)
   - [ ] Replace placeholders and host legal documents on public URLs
   - [ ] App screenshots (iPhone 6.7" and 6.5" required)
   - [ ] TestFlight testing and feedback collection

4. **Build and Submit**:
   - Build and archive in Xcode
   - Upload to App Store Connect via Xcode
   - Test with TestFlight
   - Submit for App Store review

📋 **Complete submission checklist**: [App Readiness Plan](claude_app_readiness_plan.md)

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
- **Job queue system**: Scalable processing with PostgreSQL locking
- **Automatic retries**: Failed jobs are retried with exponential backoff
- **Content freshness**: Hourly updates ensure current information
- **Cost monitoring**: Track and optimize AI service usage

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For questions or support, please open an issue in the GitHub repository.