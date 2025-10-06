# DayStart Changelog 🍌

*Because every great day starts with knowing what's new, and every great changelog starts with bananas.*

All notable changes to DayStart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- Support for social media DayStarts with `social_daystart` field
- Special date handling: `local_date` can now be "TODAY" (converts to YYYY-MM-DD in timezone)
- Special time handling: `scheduled_at` can now be "NOW" (immediate processing)
- Auto-detection of social DayStarts based on x-client-info patterns (DAILY_GENERIC, SOCIAL_TIKTOK, etc.)
- Social intro/outro content for TikTok and other platforms:
  - Intro: "Welcome to your daily DayStart AI briefing — your personalized morning update in 90 seconds or less."
  - Outro: "To get your own personalized DayStart every morning, search DayStart AI in the App Store."
- Database migration 029: Add social_daystart column with index for efficient querying

### Changed
- create_job edge function now handles special date/time values before validation
- process_jobs adds intro/outro for social DayStarts when social_daystart=true

### Fixed

### Removed

---

## [2025.10.16] - 2025-10-16

**Build:** 1 | **Commit:** TBD | **Status:** In Development

### Removed
- Deleted unused MockDataService.swift file (364 lines)
  - Service was not referenced anywhere in codebase
  - Not included in Xcode project build
  - No production impact - all data comes from Supabase

---

## [2025.09.25] - 2025-09-25

**Build:** 1 | **Commit:** `1df1c98` | **Status:** **LIVE** on App Store as of 2025-09-27

### Added
- Market indices ^GSPC (S&P 500) and ^DJI (Dow Jones) now included in default Yahoo Finance data pulls
- Stock validation service recognizes market index symbols (^GSPC, ^DJI) with proper display names
- Automatic cleanup of test-deploy artifacts in cleanup-audio edge function
  - Deletes all test-deploy folders and files from storage bucket
  - Removes test-deploy job records from database
  - Tracks test-deploy cleanup stats in audio_cleanup_log

### Changed
- **New App Store positioning: "Your Personal Morning Brief"** - repositioned as the intelligence advantage successful leaders use
- **Introduced as "Morning Intelligence Platform"** - category-creating positioning that differentiates from alarms, podcasts, and news apps
- App Store metadata completely rewritten to target ambitious professionals who value their time
- Enhanced app description opener: "The most successful people in the world don't start their day scrolling. They start with a brief."
- Added clear differentiation statement: "It's not an alarm. It's not a podcast. It's not the news."
- Subtitle changed from "AI Audio News & Weather Brief" to "Your Personal Morning Brief"
- Keywords updated to include "executive" and "entrepreneur" - removed generic "success" term
- Promotional text strengthened with "world-class leaders" instead of "successful leaders"
- New closing tagline: "You don't just wake up. You start ahead." replacing "successful mornings start with clarity, not chaos"
- Removed generic "50+ industries" claim, now "Trusted by ambitious professionals worldwide"
- Standardized all duration references to "3 minutes" throughout metadata (previously mixed "3-minute" and "3 minutes")
- Subscription display names now "Monthly/Annual Leadership Pass" to align with executive positioning
- Default stock symbols updated from ["AAPL", "TSLA", "^GSPC"] to ["^GSPC", "^DJI", "BTC-USD"] for new users
- Onboarding default stocks updated from "SPY, DIA, BTC-USD" to "^GSPC, ^DJI, BTC-USD" to use market indices
- MockDataService test data updated to use new default stock symbols
- Process jobs script generation now ensures ALL user-selected stocks are mentioned regardless of DayStart length
- Updated TTS prompt to properly pronounce index names (e.g., "S and P five hundred" instead of "^GSPC")

### Fixed
- Days of the week in Edit & Schedule screen now center properly on larger phone screens instead of being left-justified
- Welcome DayStart now correctly shows tomorrow's weather and calendar events instead of today's when previewing what's coming up
- Updated welcome DayStart closing to be more engaging: "I'll see you tomorrow at {scheduled time} where we'll go deeper"

---

## [2025.09.22] - 2025-09-22

**Build:** 2 | **Commit:** `401ba53` | **Status:** **LIVE** on App Store as of 2025-09-24

### Added
- Customized welcome DayStart script with 60-second introduction for new users
- Welcome DayStarts now mention tomorrow's scheduled time and provide onboarding instructions
- Motivational quote included in welcome experience
- Confirmation dialog when exiting EditScheduleView with unsaved changes
- Pull-to-refresh functionality on Home screen for manual status checking
- Pain point and feature cards in onboarding are now tappable to advance to the next screen
- Process jobs optimization: Automatically triggers job processing when audio status returns "queued" during preparing state
- Welcome DayStart now shows proper preparing view with countdown and fun rotating messages instead of blank loading

### Changed
- Home screen now transitions directly to welcome-ready state after onboarding instead of showing a brief idle state first
- Welcome DayStart polling interval reduced from 30 seconds to 10 seconds (consistent with regular DayStarts)
- Onboarding completion for existing subscribers now properly triggers welcome DayStart flow
- Welcome scheduler sets pending state synchronously to avoid race conditions
- Updated AI prompt to correctly identify Donald Trump as the current president in news content

### Fixed
- Fixed critical issue where welcome DayStarts could be overwritten by regular DayStarts during onboarding
- Added purchase validation to prevent premature job creation before subscription completion
- Enhanced backend job creation to prioritize welcome jobs when duplicate requests occur
- Added client-side validation to verify welcome jobs are created correctly
- Improved job creation idempotency to preserve welcome job status
- Users can no longer accidentally lose unsaved changes when dismissing the settings screen
- Users no longer confused by non-interactive cards that appeared clickable in onboarding pages 1 and 2
- Fixed onboarding flow going directly to idle instead of welcome DayStart for existing subscribers
- Fixed "x" button during audio playback - now properly returns to idle state with appropriate countdown/schedule content instead of staying in playing state
- Fixed preparing view not showing countdown timer and rotating messages for welcome DayStarts
- Fixed race condition where welcome scheduler async initialization could complete before HomeView loaded

### Removed

---

## [2025.09.16] - 2025-09-16

**Build:** 2 | **Commit:** `aec035a`

### Added
- Greeting format now omits comma and name when user has no preferred name set (says "Good morning, it's..." instead of "Good morning, there, it's...")
- Healthcheck emails now use color-coded borders and headers based on status (green for pass, orange for warn, red for fail)
- iOS best practice permission flow with complete gesture blocking
- Invisible overlay that captures ALL gestures when permissions are undetermined  
- Real-time permission status synchronization with system state
- Purchase user analytics tracking across all Edge Functions
- Daily generic DayStart automation (4:45 AM ET)
- AI-powered healthcheck diagnosis using o3-mini
- Apple Weather attribution for App Store compliance
- Welcome job priority system with bypass validation

### Fixed
- **Critical:** Permission timing bug where weather dialog appeared after page transition
- **Critical:** Users who granted location permission having weather incorrectly disabled
- **Critical:** Weather and calendar features not enabled in onboarding when permissions were already granted
- **Critical:** Onboarding creating 14 days of jobs instead of 48 hours (reduced from 14 days to 3 days)
- Day abbreviation display truncated with ellipsis (W...) on smaller screens
- Day names wrapping to next line (We\nd) with larger font sizes
- Welcome DayStart could be cancelled if user's schedule didn't include current day
- Race conditions between permission dialogs and page transitions

### Changed
- Permission pages now block ALL navigation until permissions are explicitly granted/denied
- Day abbreviations updated to single/double letters: M, Tu, W, Th, F, Sa, Su
- Onboarding simplified - removed day selection, defaults to all 7 days
- Welcome DayStart completely separate from regular scheduled DayStarts
- Healthcheck timeouts increased to reduce false positives from cold starts
- Performance: Reduced buffering countdown from 3 minutes to 2 minutes
- Increased sports story limits for longer briefings: 3-minute briefings now include 2 sports (was 1), 5-minute briefings include 3 sports (was 1), and 5+ minute briefings include 3 sports (was 2)

### Technical Details
- Added `canNavigateFromCurrentPage` computed property for permission validation
- Implemented gesture-blocking overlay with both tap and swipe handling
- Enhanced permission request functions with proper async handling
- Added `shortName` property to WeekDay enum for backward compatibility
- Updated `checkRequestErrorRate` to exclude healthcheck self-reporting
- Added `is_welcome` flag to job creation API (backwards compatible)

---

## [2025.09.4] - 2025-09-12 🚀

**Build:** 10 | **Commit:** `500cc04` | **App Store Release**

### Added
- **🎉 First public release on Apple App Store**
- Production-ready iOS application available for download
- App Store listing at https://apps.apple.com/app/daystart/id6737686106

### Live Status
- Approved by Apple and live on the App Store as of September 12, 2025
- Marks the official launch of DayStart to the world!

---

## [2025.09.4] - 2025-09-09

**Build:** 8

### Fixed
- Paywall layout cutoff on iPhone 13 mini and smaller devices
- Location permission dialog improvements
- Responsive design adjustments for compact devices

### Changed
- Dynamic spacing adjustments for screens under 700pt height
- Reduced font sizes and padding for compact devices
- Optimized button heights and star icon sizing for better fit

---

## Archive

*Older versions have been moved to maintain changelog readability. For complete version history including development builds, see git commit history.*

### Development Builds (2025.09.3 - 2025.09.4)
- **Build 7:** iPad support removal, onboarding consistency improvements
- **Build 6:** Enhanced location permission handling
- **Build 3:** Core functionality improvements  
- **Build 1:** Initial release implementation

---

## About This Changelog

This changelog follows the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format:

- **Added** for new features
- **Changed** for changes in existing functionality  
- **Fixed** for any bug fixes
- **Removed** for now removed features
- **Security** for vulnerability fixes

### Version Format
- Versions follow `[YYYY.MM.DD]` format
- Build numbers and commit hashes included for reference
- Dates in ISO 8601 format (YYYY-MM-DD)

### Emoji Guide
- 🚀 App Store releases
- 🍌 Major feature releases  
- 🐛 Bug fixes
- ⚡ Performance improvements
- 🎯 UX improvements
- 🔧 Technical changes