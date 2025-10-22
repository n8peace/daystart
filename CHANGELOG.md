# DayStart Changelog 🍌

*Because every great day starts with knowing what's new, and every great changelog starts with bananas.*

All notable changes to DayStart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2025.10.19] - Waiting for App Store Review

**Build:** 1 | **Commit:** 3ebfd87 | **Status:** Waiting for App Store Review, Supabase Deployed

### Changed
- **Audio Visualization** - Implemented real-time audio level monitoring with MTAudioProcessingTap
  - Replaced simulated sine wave visualization with actual audio analysis
  - Uses vDSP (Accelerate framework) for efficient RMS calculation across 20 audio segments
  - Supports multiple audio formats (Float32, Int16) with robust format detection
  - Added smoothing (70% factor) and safety bounds for stable visualization
  - Removed conflicting animations for smoother real-time response
  - Removed "Playing your DayStart" text for cleaner playback UI
- **Edit Page Content Order** - Reorganized content toggles to match DayStart flow sequence
  - Content section now follows DayStart order: Weather → Calendar → Motivational Quotes → News → Sports → Stocks
  - Previously: Weather → News → Sports → Stocks → Calendar → Motivational Quotes  
  - Improves user experience by aligning edit interface with actual content delivery order
  - All functionality preserved: permission handlers, stock editor, quote style picker unchanged

### Added
- **Enhanced Content Prioritization System** - Revolutionary news curation with geographic flow and editorial intelligence
  - **6 New Regional News Sources**: Comprehensive NewsAPI coverage for West/East/South/Midwest US regions plus major cities and state-level policy
  - **AI Editorial Intelligence**: "NYT font size" concept with front_page/page_3/buried classification based on story significance
  - **Breaking News Spots System**: Dynamic allocation (1-3 spots) for massive stories like election nights, market crashes, declarations of war
  - **Geographic News Flow**: US National → Local → International structure with AI-generated contextual transitions
  - **Metro Area Relevance**: Intelligent scoring for 20+ major US cities (LA, NYC, Chicago, etc.) with hyperlocal keyword matching
  - **Multi-Spot Breaking News**: Major stories can consume 2-3 news spots for comprehensive coverage of significant events
  - **Safety Net AI Curation**: AI-curated top 10 stories as fallback to ensure no major stories are missed
  - **Smart Transitions**: Contextual AI bridges like "From Washington to your backyard..." and "Meanwhile, closer to home in [neighborhood]..."
- **Enhanced Sports Prioritization System** - Intelligent sports curation with seasonal awareness and championship detection
  - **Sports Intelligence Engine**: AI scoring system (0-100) based on game significance, seasonal context, and championship status
  - **Seasonal Awareness**: October prioritizes MLB playoffs > NBA season openers > NFL > NHL with dynamic monthly adjustments
  - **Sports Spots Allocation**: Championships get 3 spots (World Series Game 7, Super Bowl), playoffs get 2 spots, regular games get 1 spot
  - **Championship Detection**: Automatic identification of finals, playoffs, season openers, and major rivalries for proper coverage
  - **Metro Team Mapping**: Location-based relevance scoring for 20+ major US cities with comprehensive team databases
  - **Game Type Classification**: championship > playoff > season_opener > rivalry > regular priority hierarchy
  - **Multi-Spot Championships**: Major championship games can consume 2-3 sports spots for comprehensive coverage
- **DayStart AI Share** - Complete shareable audio briefing system with secure, production-ready implementation
  - **iOS Integration**: Share button in audio player with leadership-focused messaging and social media optimization
  - **Secure Architecture**: Public data stored locally in shares table to prevent sensitive data exposure to anonymous users
  - **Database Schema**: Migration 033 adds public data fields (audio_file_path, duration, date) to shares table for security isolation
  - **Edge Functions**: Enhanced create_share and get_shared_daystart with comprehensive logging and public data handling
  - **Web Player**: Branded audio player at daystartai.app/shared/{token} with DayStart theming and mobile optimization
  - **Rate Limiting**: 5 shares per briefing, 10 per day to prevent abuse
  - **Analytics Ready**: View tracking, CTA monitoring, and conversion metrics infrastructure
  - **Security First**: No JOIN operations to sensitive jobs table, anon users only access public share data
  - **48-Hour Expiration**: Automatic link expiration with proper error handling for expired shares

### Fixed
- **Content Cache Healthcheck** - Fixed incorrect column name causing false "missing" reports
  - Healthcheck was querying `api_source` column but table uses `source`
  - All content types now correctly show as available when fresh data exists
  - Resolves issue where healthcheck showed "❌ Missing" despite valid cached content
- **Preferred Name Sanitization** - Added comprehensive name validation to prevent job failures
  - Backend: Sanitizes complex Unicode characters, emojis, and special symbols server-side
  - iOS: Real-time character filtering prevents invalid input before submission
  - Preserves common accented characters (José, François, Björk) for international names
  - Enforces 50-character limit with visual counter when approaching limit
- **Audio Cleanup Enhancement** - Enhanced cleanup function to detect and remove orphaned files
  - Added support for cleaning up `test-manual-` folders in addition to `test-deploy-`
  - Implemented hybrid cleanup approach: database-driven (fast, default) and storage-based orphan detection (thorough, optional)
  - Configurable retention period (default 10 days)
  - Added SQL functions for orphan file detection
  - Improved cleanup logging with orphan statistics
  - Prevents job failures like the one with exotic Unicode name: ᗴᗰIᒪYஐꨄღఌᰔದᜊᱬ𖢇☙❧❦❣︎❥❤︎︎♡︎♥︎
  - Gracefully handles edge cases: emoji-only names filtered to empty string
  - Fully backwards compatible: older app versions continue working with server-side sanitization
- **Presidential Title Accuracy** - Enhanced script generation to prevent incorrect political references
  - Added critical prompt instructions emphasizing Trump as CURRENT president (as of Jan 20, 2025)
  - Implemented automatic validation in script sanitization to catch and correct title errors
  - Auto-corrects "former president Trump" → "President Trump" and "president Biden" → "former President Biden"
  - Includes debugging logs when political corrections are applied for monitoring accuracy

### Removed
- **Tomorrow's Lineup Preview** - Commented out tomorrow's content preview to reduce visual clutter
  - Simplified HomeView interface by removing detailed preview of tomorrow's DayStart content
  - Keeps focus on the main DayStart functionality rather than anticipatory content
  - Interface now cleaner and less busy for better user experience

### Added
- **External Service Health Monitoring** - Healthcheck now monitors critical external dependencies
  - Real-time health status for OpenAI API (GPT-4 for content generation)
  - Real-time health status for ElevenLabs API (voice synthesis)
  - Response time tracking and degradation detection
  - Early warning system for external service issues affecting audio generation
- **Interactive Audio Visualization** - Added dynamic yellow audio bars to playing state
  - Animated 20-bar visualization matching onboarding design
- **Hyper-Personalized Notifications** - Replaced generic notification text with dynamic, context-aware content
  - Morning notifications now include specific weather details: "🌅 Brrr! High of 32°F" 
  - Calendar-aware messages: "🌅 Busy day! 4 events - Essential briefing before the rush"
  - Streak milestone celebrations: "🎉 One week streak! Your briefing celebrates 7 days strong"
  - Day-specific energy: "🌅 TGIF! Friday briefing - End your week on a high note"
  - Location-based greetings: "🌅 Good morning from San Francisco! Your local briefing is ready"
  - Night-before previews with tomorrow's weather and calendar data
  - Intelligent style rotation prevents notification fatigue
  - On-brand fallbacks ensure quality messaging even when data is unavailable
  - Real-time audio reactivity - static when silent, dynamic when speaking
  - Smooth transitions between playing and loading states
  - Performance-optimized with 10Hz update rate
- **Optional Email in Feedback Forms** - Added optional contact field to feedback submissions
  - Optional email field in feedback forms for user follow-up
  - Fully backwards compatible - existing users unaffected
  - Secure storage with proper privacy handling
- **Recent Feedback Monitoring in Healthcheck** - Integration of user feedback tracking
- **Banana Intelligence Branding** - Added "Powered by 🍌🧠 Banana Intelligence" link to Edit Schedule page
  - Matches branding from onboarding flow
  - Positioned above version number in page footer
  - Links to https://bananaintelligence.ai/
- **News Story Transitions** - Added subtle transitions between news stories for better audio flow
  - 10 transition options: one-word ("Also,", "Meanwhile,") and short phrases ("In other news,")
  - Smart randomization - transitions used ~60% of the time to prevent overuse
  - Contextual options: "Back home,", "Nationally,", "Locally," for story scope
  - Maintains current story count and pacing while improving natural flow
- **Expanded Calendar & Quote Sections** - Increased word budgets for richer content
  - Regular DayStart: Calendar 120→180 words (+50%), Quote 150→200 words (+33%)
  - Social DayStart: Calendar 60→90 words (+50%), Quote 60→80 words (+33%)
  - Calendar coverage expanded from 1-3 events to 2-5 events for more comprehensive daily overview
  - More room for event details, timing context, and meaningful philosophical content
  - News remains dominant content focus (~40-49% of total allocation)
- **Improved Content Flow** - Moved motivational quote section for better pacing
  - Quote now appears after calendar (position 4) instead of before closing (position 7)
  - Creates "Personal → Mindset → World" progression (Weather/Calendar → Quote → News/Sports/Stocks)
  - Quote serves as mindset bridge between daily logistics and external content consumption
  - Better psychological pacing with natural breathing room before information updates
- **Deterministic Quote System** - Eliminated daily quote repetition with curated library
  - Date-based deterministic selection ensures different quote each day, same quote all day
  - Timezone-aware quote changes: quotes rotate at midnight in user's local time
  - 12 quote categories matching user preferences with comprehensive coverage:
    - Buddhist (70 quotes), Christian (50 quotes), Stoic (52 quotes)
    - Philosophical (50 quotes), Mindfulness (49 quotes), Good Feelings (49 quotes)
    - Inspirational (49 quotes), Success (50 quotes), Zen (48 quotes)
  - 400+ authentic quotes from verified sources and public domain works
  - AI contextualizes selected quotes for morning relevance rather than generating new ones
  - Enhanced reliability with improved error handling and graceful AI fallback
  - No external API dependencies - quotes embedded in codebase for reliability
  - 24-hour feedback monitoring with categorization (audio, content, scheduling, other)
  - Critical issue detection for audio and content quality problems
  - Status-based alerting (WARN for 3+ items or critical issues, FAIL for 6+ items)
  - Professional email reporting with feedback samples and dashboard links
  - Privacy-protected feedback display (truncated user IDs)
  - Contact information tracking for user follow-up opportunities

### Changed
- **Enhanced Healthcheck Accuracy & Usability** - Major improvements to system health monitoring
  - Tomorrow morning jobs now calculated in Pacific Time (4am-10am PT) instead of UTC
  - Failed job tracking with error patterns and recent failure details
  - Improved generation time calculations with median tracking and outlier detection
  - Content cache display redesigned as clean table showing fresh/expired sources per type
  - Added Supabase dashboard quick links for debugging critical issues
  - AI diagnosis now includes normal operating parameters (20-50 DayStarts/day, 2-5 min generation)
  - Better timezone handling, cleaner email formatting, and actionable insights

### Fixed
- **Date-Specific Weather Forecasts** - Fixed issue where all DayStarts showed identical weather data
  - Weather now shows forecast for the specific DayStart date, not current conditions
  - Notifications now prefer forecast temperatures over current temperature with graceful fallback
  - Added forecast date context and improved forecast language ("will see", "expecting")
  - Weather service now fetches date-specific forecasts instead of just today's weather
  - SnapshotBuilder and SnapshotUpdateManager now generate weather per target date
  - Added robust fallback logic: forecast first, current weather for today if forecast fails
  - Current temperature maintained for today's DayStart, forecast-only for future dates
  - Added `forecastDate` field to WeatherData structure for better context
- **Content Cache Warning Logic** - Fixed false warnings for appropriately expired cache entries
  - Now only warns if entire content type is missing (FAIL) or all sources expired (WARN)
  - Properly handles multiple API sources per content type
  - No longer warns about individual expired entries that get auto-refreshed
- **Intro Music Playback** - Fixed intro music playing on every play/resume action
  - Intro music now only plays once at the beginning of each DayStart
  - Pausing and resuming no longer triggers intro music replay
  - State tracking ensures intro plays once per track session
- **Onboarding Page 2 Layout on Smaller Screens** - Fixed content overflow on iPad 11" and smaller devices
  - Added responsive design patterns consistent with other onboarding pages
  - Implemented ScrollView fallback for compact screen heights (< 700pt)
  - Applied minimum length spacers instead of fixed spacing
  - Reduced spacing values for compact devices to prevent content cutoff
  - Ensures consistent user experience across all device sizes during onboarding

### Removed

---

## [2025.10.16] - 2025-10-16

**Build:** 2 | **Commit:** 69f4704 | **Status:** **LIVE** on App Store as of 2025-10-16

### Fixed
- **Countdown Timer After Rescheduling** - Fixed issue where countdown would incorrectly show today's time after rescheduling when audio had already been generated
  - Countdown now properly skips to tomorrow when audio exists for today
  - Checks both regular DayStart and welcome DayStart audio
  - Maintains correct countdown after app restart

### Added
- **User Completion Tracking** - Backend support for tracking when users complete 80%+ of their DayStart
  - New `user_completed` column in jobs table for completion tracking
  - Optional `mark_completed` parameter in get_audio_status API
  - Backwards compatible - existing app versions continue working normally
  - Foundation for future "True North" completion statistics
- **Enhanced Healthcheck Monitoring** - Improved system health reporting with user-focused metrics
  - DayStarts completed in last 24 hours now displayed as primary "True North" metric
  - Shows total completions, unique users served, and average generation time
  - Removed false warnings for expected internal URL check failures
  - Better visibility into actual user value delivery vs technical metrics

### Changed
- **Increased Job Processing Capacity** - Quadrupled the maximum jobs processed per edge function run from 50 to 200
  - Reduces cold starts and improves overall throughput
  - Better utilizes the 400-second edge function timeout
  - Enables handling up to 2,400 DayStarts/hour theoretical capacity
  - Improves ability to handle peak times like 6 AM scheduling rush

---

## [2025.10.16] - 2025-10-16

**Build:** 1 | **Commit:** c4e71cb | **Status:** Supabase Deployed

### Added
- **Job Backfill System** - Automatically creates DayStart jobs for users returning after being away
  - Login-time backfill creates today's job if missing and scheduled
  - On-demand job creation when DayStart is clicked but no job exists
  - High-priority immediate processing for user-initiated requests
- **Time-Aware Greetings** - DayStart now greets you appropriately based on your scheduled time
  - 3:00 AM - 11:59 AM: "Good morning"
  - 12:00 PM - 4:59 PM: "Good afternoon"
- **Apple Promotional Offers Support** - Paywall now supports dynamic promotional pricing
  - Automatic detection of App Store Connect promotional offers
  - Strikethrough display of original prices when promotions are active
  - Percentage-based savings badges (e.g., "25% OFF")
  - Limited time offer banner with animated effects
  - Enhanced purchase flow to apply promotional offers automatically  
  - 5:00 PM - 2:59 AM: "Good evening"
  - Uses your timezone and scheduled DayStart time for accurate greeting
- **Smart Notification System** - Personalized morning/evening notifications with intelligent variety
  - 16 unique notification styles that rotate based on context (weather, calendar, streaks)
  - Priority alerts for extreme weather, streak milestones, and busy days
  - Tracks usage history to avoid repetition
  
- **Social Media Support** - Generate shareable DayStarts for TikTok and other platforms
  - Auto-detection of social requests
  - Custom intro/outro for viral content
  
- **Onboarding Redesign** - First impressions now match our executive positioning
  - Page 1: "Wake Up. Get Briefed. Succeed." with professional three-stage animation
  - Page 2: Interactive briefing preview showing "Your Chief of Staff, Working While You Sleep"
  - Navy-to-gold gradient backgrounds for authority and sophistication
  - Replaced playful elements with executive-focused design language
  - New briefing module previews: Market Intelligence, Strategic Calendar, Executive Summary
  - Professional audio waveform visualization replacing cartoon animations
  - Refined CTAs: "Get My Morning Brief" and "Let's Build Your Brief"
  - Added credibility markers and temporal context throughout
  
- **Enhanced Job Monitoring** - Improved healthcheck system
  - Tracks all queued jobs with overdue alerts
  - Email notifications for jobs delayed >5 minutes

### Changed
- **Enhanced Priority System** - Better job queue management for immediate and overdue requests
  - "NOW" jobs get highest priority (100) for immediate processing
  - Past-due jobs get urgent priority (75) 
  - Maintains existing priority levels for future scheduled jobs
- **Enhanced Social DayStart for TikTok** - Optimized social_daystart generation for viral content
  - Uses "Hello" greeting instead of time-aware greetings for consistency
  - Increased content density: 4 news stories, 2 sports, 3 stocks (vs 2/1/1 for regular)
  - Shorter pauses and transitions for punchier delivery
  - Energetic, viral-focused language style ("Breaking:", "Just in:", "Wild update:")
  - Sports prioritization: playoffs > local teams > big matchups > rivalries
  - Social media engagement-focused sign-offs
  - Optimized word budgets for 91-second target duration

### Fixed
- **Social DayStart Promotional Outro** - Now properly included in generated scripts
  - Added separate few-shot example for social DayStart format
  - Script generation now selects appropriate example based on social_daystart flag
- **Future Scheduling Bug** - Jobs scheduled 48+ hours ahead now process on the correct day
- **Script Generation Token Limits** - Increased minimum token allocation from 300 to 800
  - Fixes truncated scripts for short duration DayStarts (especially 60-90 second social_daystart)
  - Ensures complete script generation even for brief morning updates

### Removed
- **MockDataService.swift** - Deleted unused test file (no production impact)

---

## [2025.9.25] - 2025-09-25

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