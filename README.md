# DayStart

A personalized, AI-powered iOS morning podcast app that combines your local weather, news, sports, stocks, and encouragement into a custom audio briefing delivered with natural voices and ready the moment you wake up.

## Project Structure

```
DayStart/
├── App/
│   └── DayStartApp.swift          # App entry point
├── Features/
│   ├── Home/
│   │   ├── HomeView.swift         # Main screen with all app states
│   │   ├── HomeViewModel.swift    # State management
│   │   └── AudioPlayerView.swift  # Audio playback controls
│   ├── EditSchedule/
│   │   └── EditScheduleView.swift # Settings & schedule with 4hr lockout
│   ├── History/
│   │   └── HistoryView.swift      # Past DayStarts with transcripts
│   └── Onboarding/
│       └── OnboardingView.swift   # Welcome flow & paywall
├── Core/
│   ├── Models/
│   │   └── DayStartModels.swift   # Data models
│   └── Services/
│       ├── MockDataService.swift       # Deprecated - replaced with bundled audio files
│       ├── AudioPlayerManager.swift    # Audio playback
│       ├── NotificationScheduler.swift # Local notifications
│       └── UserPreferences.swift       # Persistent storage
└── Resources/
    └── Audio/
        ├── Samples/      # Voice preview samples for onboarding
        │   ├── voice1_sample.mp3
        │   ├── voice2_sample.mp3
        │   └── voice3_sample.mp3
        └── Fallbacks/    # Voice-specific fallback audio
            ├── voice1_fallback.mp3
            ├── voice2_fallback.mp3
            └── voice3_fallback.mp3
```

## Features Implemented

### ✅ App States
- **Idle** (>10h before next): Shows next DayStart time
- **Countdown** (<10h before): Live countdown timer
- **Ready**: Yellow button to start DayStart
- **Playing**: Audio controls with seek, skip ±10s, speed
- **Recently Played**: Replay option for 30 seconds

### ✅ Edit & Schedule
- Personal settings (name, content toggles)
- Schedule configuration (time, repeat days)
- Voice selection (3 options)
- Length slider (2-10 minutes)
- **4-hour lockout** before next DayStart

### ✅ History
- List of past DayStarts
- Expandable transcripts
- Replay functionality
- Persists up to 30 entries

### ✅ Onboarding
- Welcome screens
- Name collection
- Wake time setup
- Feature overview
- Paywall (mock)

### ✅ Notifications
- Reminder at T-10h
- Ready notification at scheduled time
- Local notifications only (no push server needed)

## Setup Instructions

1. Add the project files to a new Xcode project
2. Voice-specific audio files are organized in `Resources/Audio/` (samples for previews, fallbacks for offline mode)
3. Enable the following capabilities in Xcode:
   - Push Notifications (for local notifications)
   - Background Modes > Audio (for background playback)
4. Run on simulator or device

## Next Steps (Phase 2)

When ready to add backend:
1. ~~Replace `MockDataService` with real API calls~~ ✅ Replaced with bundled audio files
2. Integrate GPT-4o for content generation
3. Add ElevenLabs for audio synthesis
4. Connect to Supabase for data persistence
5. Implement push notifications server

## Notes

- All data is stored locally using UserDefaults
- Audio uses a single placeholder file
- Notifications are local-only
- No network requests in Phase 1
