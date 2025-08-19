# DayStart

A personalized, AI-powered iOS morning briefing app that combines your local weather, news, sports, stocks, and motivational content into a custom audio briefing delivered with natural voices and ready the moment you wake up.

Built with SwiftUI, Supabase backend, OpenAI GPT-4, and ElevenLabs text-to-speech.

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
- **News**: Curated news articles relevant to user location
- **Sports**: Team-specific updates for favorite sports teams
- **Stock Market**: Custom stock symbols with market insights
- **Motivational Quotes**: Daily inspiration and productivity tips
- **Voice Selection**: 3 AI-generated voice options with preview samples
- **Length Control**: Customizable briefing length (2-10 minutes)

### ✅ Advanced Technical Features
- **Background Audio Prefetching**: BGTaskScheduler integration for seamless playback
- **Three-Tier Download Strategy**: Background, foreground, and just-in-time loading
- **Audio Caching**: Local file management prevents re-downloads
- **Network Resilience**: Graceful handling of connectivity issues
- **Timeout Handling**: User-friendly error messages when generation takes too long
- **Haptic Feedback**: Contextual haptic responses throughout the app
- **Local Notifications**: Reminder and ready notifications
- **Portrait-Only Design**: Optimized for morning routine usage

### ✅ Backend Infrastructure
- **Supabase Integration**: Production-ready backend with PostgreSQL
- **Job Queue System**: `FOR UPDATE SKIP LOCKED` for scalable processing
- **Content Caching**: Efficient content refresh and storage
- **Audio Generation**: OpenAI GPT-4 script generation + ElevenLabs TTS
- **Automatic Cleanup**: Scheduled cleanup of old audio files and data
- **Cost Tracking**: Monitoring of OpenAI and ElevenLabs usage
- **Timezone Handling**: Accurate date/time calculations across timezones

## Requirements

### iOS App
- **Minimum iOS Version**: iOS 17.0+
- **Supported Devices**: iPhone only
- **Orientation**: Portrait only
- **Permissions**: Location (when in use), Calendar (full access)

### Backend
- **Supabase**: PostgreSQL database and edge functions
- **OpenAI API**: GPT-4 for script generation
- **ElevenLabs API**: Text-to-speech conversion
- **Node.js**: For Supabase edge functions

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

3. **Configure capabilities in Xcode**:
   - Background Modes: Audio, Background Processing, Background Fetch
   - Push Notifications (for local notifications)
   - Location Services
   - Calendar Access

4. **Update bundle identifier** and development team in project settings

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
   <string>https://your-project.supabase.co/functions/v1</string>
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

1. **Build and archive** in Xcode
2. **Upload to App Store Connect**
3. **Submit for review** with required app metadata

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
- **Background prefetching**: Audio downloads before user wakes up
- **Local caching**: Prevents unnecessary re-downloads
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