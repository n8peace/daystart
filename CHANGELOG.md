# DayStart Changelog 🍌

*Because every great day starts with knowing what's new, and every great changelog starts with bananas.*

---

## Development & Infrastructure 🔧

### September 6, 2025
🚀 **Deployment Automation Enhancement**

**New Features:**
- Added automated deployment validation with test job creation
- Implemented automatic rollback on deployment failures
- Created comprehensive debug logging system

**Scripts Added:**
- `deploy-supabase.sh` - Main deployment script with test validation
- `scripts/rollback-functions.sh` - Git-based function rollback
- `scripts/debug-process-jobs.sh` - Detailed debugging for failed jobs

**CI/CD Updates:**
- GitHub Actions now uses unified deployment script
- Automatic log artifact upload for debugging
- Test job validation on every deployment

**Improvements:**
- macOS compatibility fixes for date commands
- Verbose output for better deployment visibility
- Automatic cleanup of test data after validation

---

## iOS App Releases 📱

### v2025.09.4 (Build 4) - September 7, 2025
🍌 **The "Crystal Clear Subscription" Release**
📱 **App Store Resubmission** - Addressing review feedback

✨ **Compliance Updates:**
- Enhanced subscription free trial disclosure to clearly indicate automatic renewal after trial period
- Updated subscription pricing cards with clearer renewal text ("renews annually" / "renews monthly")
- Removed duplicate price display on annual subscription card for cleaner UI
- Updated CTA button text to show "then [price] monthly/annually" for better clarity
- Added explicit disclosure: "After your free trial, your subscription auto-renews until canceled"

🔍 **These changes ensure users clearly understand:**
- Free trials automatically convert to paid subscriptions
- The exact price they'll be charged when the trial ends
- Subscriptions continue until manually canceled

📍 **WeatherKit Information (Response to App Review):**
1. **Does the app include WeatherKit functionality?**
   - Yes, DayStart uses WeatherKit to provide personalized weather information in morning briefings
   
2. **Steps to navigate to WeatherKit functionality:**
   - Weather is automatically included in every DayStart briefing (no navigation required)
   - Users can toggle weather on/off during onboarding (Page 5: Weather Location)
   - In the app: Home screen → Play button → Weather content plays automatically in the audio briefing
   - Weather data is fetched server-side using WeatherKit API and integrated into the AI-generated script

🔧 **Bug Fixes:**
- Fixed onboarding auto-completion for users with existing purchases to improve testing experience
- Added 2-second delay before auto-completing onboarding to prevent immediate completion on app launch
- Enhanced authentication flow logging for better debugging of onboarding issues

### v2025.09.4 (Build 3) - September 4, 2025
🍌 **The "Smooth Sailing Banana" Release**
📱 **Initial App Store Submission** - Submitted to Apple for review ✅

✨ **New Features:**
- Added in-app feedback system - now you can tell us when things go bananas (or when they're perfectly ripe!)
- Enhanced morning briefings with improved audio quality
- Changed default inspiration type from "Stoic" to "Good Feelings" for more uplifting quotes

🚀 **Improvements:**
- Removed intrusive connection error overlays for smoother user experience
- Better background processing for smoother audio playback
- Streamlined user experience across all screens
- Toast notifications now handle all error messaging gracefully

🔧 **Bug Fixes:**
- Fixed purchase restore flow to properly handle success and failure cases
- Added user-friendly error messages when no previous purchase is found
- Purchase restoration now keeps users on paywall instead of resetting to start

🔧 **Backend Enhancements:**
- New feedback collection system with secure receipt-based authentication
- Enhanced content processing capabilities

🔒 **Privacy Improvements:**
- Removed latitude/longitude coordinates from location data - now only sends city/state/country for weather context
- Enhanced privacy compliance by eliminating precise location tracking

---

### v2025.09.3 (Build 1) - September 3, 2025  
🍌 **The "Smart Banana" Release**

✨ **New Features:**
- AI-curated content that learns your morning routine preferences
- Dynamic pricing system for premium features
- Enhanced TTS voice options (upgraded voice3 from alloy to ash)

🚀 **Improvements:**
- Smarter content recommendations based on your usage patterns
- Better audio caching and prefetch management
- Improved job processing reliability

🔧 **Backend Enhancements:**
- AI content curation system (Migration 025)
- Enhanced job cancellation support
- Optimized content processing functions

---

## Supabase Backend Updates 🛠️

### Migration 026 - September 4, 2025
🍌 **App Feedback Collection System**
- Added `app_feedback` table for user feedback collection
- Implemented secure RLS policies with receipt-based authentication
- Support for diagnostic data collection when users opt-in
- Categories: audio_issue, content_quality, scheduling, other

### Migration 025 - September 3, 2025
🍌 **AI Content Curation Engine**
- Enhanced `get_fresh_content` function with AI-curated content prioritization
- Improved content personalization algorithms
- Better integration with existing content cache system

### Migration 024 - September 2, 2025
🍌 **Job Status Management**
- Added `cancelled` job status for better job lifecycle management
- Improved job processing reliability and user control

---

## Release Notes Style Guide 📝

**For Future Releases:**
- 🍌 Theme each release with banana-inspired names
- ✨ New Features: Major additions that users will notice
- 🚀 Improvements: Enhancements to existing features
- 🔧 Bug Fixes: Fixes that resolve issues
- 🛠️ Backend: Technical improvements and infrastructure updates

**Version Format:**
- iOS App: `YYYY.MM.DD` (Build N)
- Backend: Migration number with date

**Tone:**
- Fun and engaging while being informative
- Banana Intelligence personality throughout
- Clear about what users can expect from each update

---

*Built with 🍌 by the Banana Intelligence team*