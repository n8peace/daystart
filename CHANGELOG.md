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

### v2025.09.4 (Build 7) - September 8-9, 2025
🍌 **The "Permission Flow Fix & Native iOS Experience" Release**
📱 **App Store Compliance Fix** - Resolving Guideline 5.1.1 and 4.0 rejection

🎯 **iPad Support Removed (September 9):**
- Changed to iPhone-only app to address iPad layout issues
- App Store rejection showed onboarding buttons cut off on iPad Pro 11"
- Since DayStart is optimized for portrait-only morning routines, iPhone-only is the appropriate configuration

✨ **Permission Request Redesign:**
- **Removed skip buttons** from weather and calendar permission screens per Apple guidelines
- **Redesigned permission flow** with clearer messaging:
  - Simplified titles to "Weather Permission" / "Calendar Permission"
  - Updated descriptions to explain what will be asked
  - Added emphasis that permissions are "completely optional"
  - Streamlined content order: description → benefits → optional message
- **Enhanced user experience**:
  - Concise "Enable Weather" / "Enable Calendar" buttons
  - Auto-advance to next page regardless of permission choice (allow/deny)
  - Smart swipe behavior: backward swipes work normally, forward swipes trigger permission request
  - Visual feedback: buttons show green (enabled), red (disabled), or default state
  - Removed error states - permission denial is treated as valid user choice
- **Maintains functionality**: Weather/calendar features automatically enabled/disabled based on permission choice

📱 **Onboarding Consistency & Native iOS Feel (September 9):**
- **Standardized button positioning** across all 10 onboarding pages
  - Consistent bottom spacing: `max(44, geometry.safeAreaInsets.bottom + 24)`
  - All buttons now at the same visual distance from bottom on all devices
- **Native iOS fixed layouts** for better user experience:
  - Converted pages 5-8 from ScrollView to fixed VStack layout
  - No unexpected scrolling - content optimized to fit on screen
  - Maintains scrollable paywall for conversion optimization
- **Enhanced spacing and margins**:
  - Increased horizontal padding from 8% to 10% for better readability
  - Fixed cramped paywall spacing (top spacer 2%→8%, sections 1-2%→4%)
  - Consistent content spacing patterns across all pages
- **Skip button improvements**:
  - Added "Use default voice" skip option to voice selection page
  - Only 2 skip buttons total: Name (page 2) and Voice (page 7) for optional personalization

🎨 **Native iOS Design Patterns:**
- **Fixed VStack layouts** (Pages 0-8) for iPhone-native onboarding feel
- **Optimized ScrollView** (Page 9 - Paywall) for complex conversion-critical content
- **Responsive design** maintains compatibility across iPhone and iPad sizes
- **Consistent interaction model** - no mixing of scrollable and fixed content

🎨 **UI Readability Improvements (September 9):**
- **Enhanced text readability** across the app:
  - Changed small yellow/primary colored text to gray (secondaryText) for better contrast
  - Updated onboarding preview text, schedule summaries, and anticipation text
  - Modified Edit Schedule view informational text for improved visibility
- **Settings UI refinements**:
  - Theme picker accent color changed from yellow to gray
  - Quote Style picker accent color updated to gray
  - "Add Symbol" button text changed to gray
  - "Restore Purchase"/"Upgrade to Premium" button text now uses gray
  - All informational messages ("Select at least one day", "DayStart Disabled", etc.) now in gray
- **Maintains yellow accent** for interactive elements like toggle switches and primary action buttons

🔧 **Technical Implementation:**
- Updated `requestLocationPermission()` and `requestCalendarPermission()` handlers with auto-advance
- Implemented custom gesture handling for permission pages using `simultaneousGesture`
- Removed conditional UI states and error displays
- Improved onboarding flow continuity
- Converted ScrollView + fixed bottom patterns to unified VStack layouts
- Proper geometry.safeAreaInsets.bottom handling across all devices
- Updated version to 2025.09.4 (Build 7) in Info.plist

🐛 **Schedule Update Fix (September 9):**
- **Fixed backend job scheduling updates**: Schedule time changes now properly update existing jobs' scheduled_at timestamps
- **Root cause**: Backend `update_jobs` function only updated job settings, not scheduled times
- **Solution**: Added `scheduled_time` parameter to update_jobs API and client implementation
- **Impact**: Schedule changes (e.g., 14:05 → 14:08) now reflect immediately without requiring app restart
- **Technical details**:
  - Extended `UpdateJobsRequest` interface with optional `scheduled_time` field
  - Modified `buildUpdatePayload()` to handle scheduled_at database updates  
  - Updated client `updateJobs()` method and schedule change handler to pass new times
  - Fixed precision issues in time comparison logic using 1-second threshold

🐛 **UI Update Fix (September 9):**
- **Fixed immediate UI feedback**: Schedule time changes now update "Next DayStart" display instantly
- **Root cause**: Schedule observer wasn't using MainActor threading pattern for UI updates
- **Solution**: Fixed HomeViewModel schedule observer to ensure immediate SwiftUI refresh
- **Impact**: Next alarm time now updates instantly in UI when schedule is changed
- **Technical details**:
  - Added `Task { @MainActor in ... }` wrapper to schedule observer
  - Added explicit `objectWillChange.send()` to force SwiftUI refresh
  - Fixed `DateFormatter.shortTime` access issue using centralized FormatterCache
  - Added debug logging to track schedule change propagation

🎯 **Onboarding Improvements (September 9):**
- **Fixed location permission bypass**: Users can no longer swipe past location permission without interacting
- **Updated permission UI**: Changed "Weather Permission" to "Location Permission" for clarity
- **Added location benefits**: Added "Localized news & sports" to location permission benefits list
- **Fixed default quote type**: Changed from "Stoic" to "Good Feelings" for new users
- **Consistent behavior**: Location permission now works as reliably as calendar permission
- **Root cause**: Complex early-exit logic allowed bypassing permission dialog when status was already determined
- **Solution**: Simplified permission flow to match calendar permission pattern exactly
- **Technical details**:
  - Removed early returns in `requestLocationPermission()` that skipped user interaction
  - Reduced function from 43 lines to 19 lines with consistent flow
  - Always calls permission request regardless of current status
  - Let iOS system handle already-granted cases gracefully
  - Fixed conflicting defaults: `UserSettings.default` had `.goodFeelings` but `OnboardingView` started with `.stoic`

### v2025.09.4 (Build 6) - September 8, 2025
🍌 **The "Compliance Complete" Release**
📱 **App Store Resubmission** - Comprehensive compliance updates

✨ **Subscription Compliance Updates:**
- Enhanced free trial disclosure with clear automatic renewal indicators
- Updated subscription pricing cards:
  - Changed "then auto-renews" to clearer "renews annually" / "renews monthly"
  - Removed duplicate price display on annual card for cleaner UI
  - Made renewal text same font size as trial text for better visibility
- Improved CTA button to show "then [price] monthly/annually" for pricing clarity
- Added explicit disclosure: "After your free trial, your subscription auto-renews until canceled"
- Fixed paywall layout with ScrollView to ensure Terms, Privacy, and Restore Purchase links are always visible

🎨 **Paywall Optimization (Build 6):**
- Removed ScrollView and implemented dynamic spacing to fit all content on one screen
- Optimized layout while maintaining readability:
  - Reduced star emoji to 45pt and circle to 80pt
  - Maintained hero title at 28pt for prominence
  - Optimized "Most Popular" badge with smaller font (10pt) and padding
- Streamlined pricing cards:
  - Combined trial and renewal text on one line with bullet separator
  - Reduced internal spacing and padding for compact layout
  - Reduced price font size from 24pt to 20pt
- Implemented side-by-side card layout for screens wider than 500pt
- Removed urgency banner to save vertical space
- Updated footer text to "Auto-renews until canceled. Cancel anytime in Settings."
- Maintained readable font sizes for footer links (12pt) with proper spacing
- Reduced spacer heights throughout for optimal screen utilization

📱 **Legal Compliance:**
- Added functional Terms of Use (EULA) link in app binary
- Added functional Privacy Policy link in app binary
- Added Terms of Use URL to App Store metadata
- All legal links open in Safari to: https://daystart.bananaintelligence.ai/terms and https://daystart.bananaintelligence.ai/privacy

🌦️ **WeatherKit Compliance:**
- Confirmed WeatherKit integration for personalized weather information
- Weather automatically included in every DayStart briefing
- Users can toggle weather during onboarding (Page 5: Weather Location)
- Weather data fetched server-side using WeatherKit API

🔧 **Technical Improvements:**
- Fixed onboarding auto-completion for users with existing purchases
- Added 2-second delay before auto-completing onboarding for better testing
- Enhanced authentication flow logging for debugging
- Removed intrusive connection error overlays
- Improved background processing for smoother audio playback
- Enhanced privacy by removing precise location tracking (only city/state/country)

🎯 **These changes ensure:**
- Full compliance with App Store Guidelines 3.1.2 and 2.1
- Clear communication of subscription terms and pricing
- All required legal documentation is accessible
- Better user experience with improved error handling

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