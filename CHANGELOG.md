# DayStart Changelog 🍌

*Because every great day starts with knowing what's new, and every great changelog starts with bananas.*

---

## iOS App Releases 📱

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