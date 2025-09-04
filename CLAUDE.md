# Claude Instructions for DayStart

## Project Overview
DayStart is a production iOS app (16K+ lines) that delivers personalized AI-generated morning briefings. Users wake up to curated content including news, weather, calendar events, and motivational content delivered via high-quality AI voice synthesis.

## Developer Profile
- Full stack senior developer
- iOS professional and expert

## iOS Frontend (SwiftUI)

### Architecture Patterns
- **Lazy Service Loading**: Spotify-inspired 5-tier loading system for optimal startup performance
- **MVVM + Combine**: Reactive architecture with `@Published` properties and `EnvironmentObject`
- **Feature Modules**: Clean separation with `/Features/` structure
- **Micro-components**: Performance-optimized small UI components

### Key Components
- `HomeView.swift` (1,669 lines): Main interface with countdown timers, audio controls
- `HomeViewModel.swift` (1,858 lines): Complex state management with job polling
- `OnboardingView.swift` (2,350 lines): Complete welcome flow with StoreKit integration
- `ServiceRegistry.swift`: Manages 15+ specialized services with lazy loading

### iOS Conventions
- **Portrait only**: Optimized for morning routine usage
- **Background audio**: Full AVFoundation integration with lock screen controls
- **Keychain storage**: Secure data persistence
- **StoreKit 2**: Modern subscription handling (monthly $4.99, annual $39.99)
- **iOS 17.0+**: Target deployment, use modern Swift features
- **Privacy compliance**: WeatherKit (when in use), EventKit (full access)

### UI/Design System (BananaTheme)
- **Banana-themed branding**: Yellow/brown palette, sunrise gradients
- **Adaptive theming**: Proper light/dark mode with semantic colors
- **Custom modifiers**: `.bananaCardStyle()`, `.bananaPrimaryButton()`
- **Typography system**: Responsive font weights
- **Micro-interactions**: Haptic feedback patterns

## Backend Supabase

### Authentication System
- **Receipt-based auth**: No user accounts - StoreKit receipt IDs only
- **Headers**: `x-client-info` (receipt ID), `x-auth-type` (purchase/anonymous)
- **Privacy-first**: No email/password required

### Database Schema
- `jobs`: Queue system with PostgreSQL locking (`FOR UPDATE SKIP LOCKED`)
- `content_cache`: 12-hour cached content from multiple APIs
- `daystart_history`: User's completed DayStarts
- `purchase_users`: Receipt ID tracking
- **RLS enabled**: All tables use Row Level Security

### Edge Functions (TypeScript/Deno)
- `create_job`: Queue new DayStart generation
- `process_jobs`: Core AI script generation (GPT-4o-mini) + TTS (ElevenLabs)
- `get_audio_status`: Check generation status
- `refresh_content`: Hourly content cache updates
- `cleanup-audio`: Automated storage management

### Content Pipeline
- **Multi-source aggregation**: News, sports, stocks, weather APIs
- **AI script generation**: OpenAI GPT-4o-mini for personalized content
- **TTS synthesis**: ElevenLabs with voice variety
- **Priority-based expansion**: Intelligent content allocation for longer briefings
- **Cost optimization**: Multiple caching layers

## Security

### iOS Security
- **Keychain Manager**: Secure storage for sensitive data
- **Privacy Manifest**: Complete Apple compliance (`PrivacyInfo.xcprivacy`)
- **Minimal permissions**: Only WeatherKit and EventKit
- **Background limits**: Audio + processing only, no location background
- **Receipt validation**: StoreKit security patterns

### Backend Security
- **RLS policies**: Row-level security on all tables
- **Service role separation**: Anon vs service key usage
- **Environment variables**: All API keys in Supabase secrets
- **CORS configuration**: Proper cross-origin handling
- **Rate limiting**: 4-hour lockout prevents spam

### Privacy Compliance
- **No tracking**: No analytics or user behavior tracking
- **Data minimization**: Only essential data stored
- **Local-first**: Content cached locally when possible
- **Encrypted storage**: All user data properly secured

## Design Principles

### User Experience
- **Morning-optimized**: Quick, efficient briefings for busy users
- **One-touch operation**: Minimal interaction required
- **Offline capability**: Cached audio works without internet
- **Smart scheduling**: Prevents over-use with intelligent lockouts

### Performance Philosophy
- **Instant startup**: Sub-100ms app launch with lazy loading
- **Background preparation**: Audio prefetched via BGTaskScheduler
- **Three-tier caching**: Memory → local file → background downloads
- **Battery optimization**: Efficient background task management

### Content Quality
- **AI curation**: Dynamic script generation tailored to user preferences
- **Voice variety**: Multiple ElevenLabs voices for engagement
- **Content freshness**: 12-hour cache windows ensure relevance
- **Personalization**: Calendar integration, location-based weather

## Best Practices

### Code Standards
- **Swift 5.9+**: Use modern concurrency (`async/await`) and actors
- **SwiftUI lifecycle**: Prefer `@StateObject` over `@ObservedObject`
- **Error handling**: Comprehensive error types with user-friendly messages
- **Memory management**: Avoid retain cycles, use `weak self` appropriately
- **Thread safety**: All UI updates on MainActor

### Backend Standards
- **Backwards compatibility**: All schema changes must be additive
- **Function versioning**: Version edge functions when making breaking changes
- **Cost awareness**: Monitor OpenAI/ElevenLabs usage, implement caching
- **Error logging**: Comprehensive logging for debugging production issues

### Development Workflow
- **Always update CHANGELOG.md**: Document all changes for version tracking
- **Test on device**: Background tasks and audio require physical device testing
- **StoreKit testing**: Use local configuration file for subscription testing
- **Database migrations**: Test thoroughly, rollback plans required

### Deployment Rules
- **User-only deployment**: Never auto-deploy to GitHub or Supabase
- **Backwards compatibility**: All backend changes must support current App Store version
- **Version coordination**: iOS app versions must align with backend capabilities
- **App Store compliance**: Maintain privacy manifest and legal documents

## Critical Implementation Notes

### Audio System
- **AVAudioSession**: Configure for background playback with proper interruption handling
- **Lock screen controls**: Implement `MPNowPlayingInfoCenter` for system integration
- **File management**: Use temporary URLs, implement cleanup strategies
- **Format**: Prefer M4A for iOS optimization

### Background Tasks
- **BGTaskScheduler**: Register `ai.bananaintelligence.DayStart.refresh` for audio prefetching
- **Time limits**: iOS enforces strict background execution limits
- **Battery awareness**: Respect system resource constraints

### StoreKit Integration
- **Receipt validation**: Always validate receipts server-side
- **Restore purchases**: Handle gracefully across device transfers
- **Free trial**: 7-day trials configured for both subscription tiers
- **Sandbox testing**: Use local StoreKit configuration for development

### State Management
- **Single source of truth**: Use `@StateObject` for ViewModels
- **Environment propagation**: Pass theme and settings via environment
- **Async operations**: Always use `Task` for API calls from views
- **Loading states**: Comprehensive loading indicators for all async operations

### Performance Monitoring
- **Service timing**: Monitor service load times in development
- **Memory usage**: Profile with Instruments for memory leaks
- **Network efficiency**: Minimize API calls through intelligent caching
- **Battery impact**: Test background task usage extensively