# DayStart Changelog 🍌

*Because every great day starts with knowing what's new, and every great changelog starts with bananas.*

All notable changes to DayStart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
### Changed
- Greeting format now omits comma and name when user has no preferred name set (says "Good morning, it's..." instead of "Good morning, there, it's...")
- Healthcheck emails now use color-coded borders and headers based on status (green for pass, orange for warn, red for fail)
### Fixed
### Removed

---

## [2025.09.16] - 2025-09-16 (Next Release)

**Build:** 2 | **Commit:** `0500777`

### Added
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

## [2025.09.4] - 2025-09-12 🚀 (Currently Live)

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