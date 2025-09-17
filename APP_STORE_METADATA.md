# App Store Connect Configuration for DayStart AI

## Current Live Version: 2025.09.4 (Build 10)
## Next Release: 2025.09.16 (Build 2)

## Basic Information
- **App Name:** DayStart AI
- **Current Version:** 2025.09.4 (Build 10) - Live on App Store
- **Next Version:** 2025.09.16 (Build 2)
- **Support URL:** https://daystart.bananaintelligence.ai
- **Marketing URL:** https://daystart.bananaintelligence.ai

## Keywords (100 characters max)
```
morning,briefing,ai,news,weather,calendar,audio,productivity,routine,personalized,habit
```

## Promotional Text (170 characters max)
```
Start your day informed! Get personalized AI audio briefings with weather, news, calendar events & more - all in one hands-free morning update.
```

## App Description (4000 characters max)
```
Skip the scrolling, start informed. Transform your morning routine with DayStart AI - your intelligent personal assistant that creates custom audio briefings tailored just for you.

Wake up to a professionally narrated summary of everything you need to know for the day ahead. No more frantically checking multiple apps or scrolling through endless feeds. DayStart AI brings it all together in one seamless, hands-free audio experience.

WHAT'S INCLUDED IN YOUR BRIEFING:
• Local Weather Forecast - Current conditions and today's outlook for your exact location (powered by WeatherKit)
• Breaking News - Top stories from trusted sources, intelligently curated
• Calendar Events - Your schedule for the day, meeting times, and reminders  
• Stock Market Updates - Track your portfolio and market movements
• Sports Scores - Results from your favorite teams
• Daily Inspiration - Motivational quotes to energize your morning

WEATHERKIT INTEGRATION:
DayStart AI uses WeatherKit to provide accurate, hyperlocal weather information. Weather data is automatically included in every morning briefing - no navigation required. Simply press play on your DayStart and weather information will be seamlessly integrated into your personalized audio briefing.

KEY FEATURES:
• AI-Powered Personalization - Our advanced AI learns your preferences and interests
• Natural Voice Synthesis - Crystal-clear narration that sounds remarkably human
• Offline Playback - Download briefings for your commute
• Customizable Content - Choose exactly what you want to hear

PERFECT FOR:
• Busy professionals who need to stay informed
• Commuters who want hands-free news updates during their drive
• Morning exercisers looking for audio content
• Anyone who values their time and wants a smarter morning routine

HOW IT WORKS:
1. Set your wake-up time and content preferences
2. DayStart AI generates your personalized briefing overnight
3. Wake up to your custom audio briefing or play it when ready
4. Start your day informed, inspired, and ahead of the curve

SUBSCRIPTION OPTIONS:
• 3 and 7-day free trials to experience the full power of DayStart AI
• Monthly subscription: $4.99/month
• Annual subscription: $39.99/year (save 33%)

Join others who've revolutionized their mornings with DayStart AI. Because the best days start with the right information.

Privacy Policy: https://daystart.bananaintelligence.ai/privacy
Terms of Service: https://daystart.bananaintelligence.ai/terms

By subscribing, you agree that payment will be charged to your Apple Account at confirmation of purchase. Your subscription will automatically renew unless auto-renew is turned off at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions in your Apple Account settings.
```

## Subtitle (30 characters max)
```
AI Audio News & Weather Brief
```

## What's New in Version 2025.09.16
```
🍌 Rise and shine, DayStarters! We've been up before dawn making your mornings even better:

SMOOTHER THAN BANANA BUTTER:
• Fixed that pesky weather permission timing - no more dialog surprises!
• Simplified setup - we'll start you off with all 7 days (because who doesn't want daily brilliance?)
• Days of the week got a makeover: M, Tu, W, Th, F, Sa, Su - short, sweet, and fits on any screen!

FASTER WAKE-UPS:
• Reduced buffering time from 3 to 2 minutes (that's 60 seconds more snooze for you!)
• Welcome DayStart now works like a charm - no more accidental cancellations

MORE SPORTS, MORE SCORES:
• Increased sports coverage in longer briefings - because we know you need ALL the highlights

Bug fixes? We squashed 'em. Permission flows? Smooth as silk. Your perfect morning? Still just one tap away.

Sweet dreams! 🌅
```

## What's New in Version 2025.09.4
```
Welcome to DayStart AI! 

• Personalized AI-generated morning briefings
• Weather, news, calendar integration  
• High-quality voice synthesis
• Customizable content preferences
• Offline playback support

Try monthly (3-day free trial) or annual (7-day free trial) subscriptions!
```

## Categories
- **Primary:** Lifestyle
- **Secondary:** Productivity

## Age Rating
- **13+**

## Terms of Use (EULA)
- **URL:** https://daystart.bananaintelligence.ai/terms
- **Note:** Custom EULA provided, not using Apple's standard agreement

## Privacy Policy
- **URL:** https://daystart.bananaintelligence.ai/privacy

## In-App Purchase Products

### Monthly Subscription
- **Product ID:** `daystart_monthly_subscription`
- **Reference Name:** DayStart Monthly
- **Price:** $4.99/month
- **Free Trial:** 3 days
- **Description:** Get unlimited personalized morning briefings

### Annual Subscription  
- **Product ID:** `daystart_annual_subscription`
- **Reference Name:** DayStart Annual
- **Price:** $39.99/year
- **Free Trial:** 7 days
- **Description:** Get unlimited personalized morning briefings (Save 33%)

## Subscription Group
- **Reference Name:** DayStart Premium
- **Description:** Unlock unlimited AI-powered morning briefings tailored just for you

### Monthly Subscription - Localization (English)
- **Display Name:** Monthly Pass
- **Description:** Get unlimited personalized morning briefings with weather, news, calendar events, and market updates. Includes 3-day free trial.

### Annual Subscription - Localization (English)  
- **Display Name:** Annual Pass
- **Description:** Get unlimited personalized morning briefings with weather, news, calendar events, and market updates. Save 33% with 7-day free trial.

### Monthly Subscription - Review Notes
```
DayStart Monthly subscription provides unlimited access to personalized AI-generated morning briefings. Features include:

- Daily personalized audio briefings with weather, news, calendar events, and market updates
- Customizable content preferences 
- Offline audio download and playback
- Background audio generation and scheduling
- 3-day free trial included

To test: Use sandbox account, tap "Monthly Pass" on paywall screen, complete purchase flow. Audio generation requires network connectivity and may take 2-3 minutes for first briefing.
```

### Annual Subscription - Review Notes
```
DayStart Annual subscription provides unlimited access to personalized AI-generated morning briefings with significant savings vs monthly. Features include:

- Daily personalized audio briefings with weather, news, calendar events, and market updates  
- Customizable content preferences
- Offline audio download and playback
- Background audio generation and scheduling
- 7-day free trial included
- 33% savings compared to monthly subscription

To test: Use sandbox account, tap "Annual Pass" on paywall screen, complete purchase flow. Audio generation requires network connectivity and may take 2-3 minutes for first briefing.
```

## App Store Connect Configuration

### App Information Settings
1. **Content Rights**: Select "No, it does not contain, show, or access third-party content"
2. **Age Rating**: 13+ (no objectionable content)
3. **App Encryption Documentation**: 
   - Select "Yes" (uses HTTPS)
   - Choose "Only using encryption for HTTPS calls"
   - Add to Info.plist: `ITSAppUsesNonExemptEncryption = false` ✓
4. **Digital Services Act**: 
   - Select "Trader" (selling subscriptions)
   - Provide business name, address, phone, email
5. **App Server Notifications**: Skip (leave blank)
6. **App-Specific Shared Secret**: Skip (leave blank)

### Privacy Settings (Data Collection)
Select **Yes** for data collection with these categories:
1. **Location → Coarse Location**: For weather updates (App Functionality)
2. **Sensitive Info**: Calendar events for briefing context (App Functionality)
3. **Identifiers → User ID**: Purchase receipt ID (App Functionality)
4. **Diagnostics → Other Diagnostic Data**: Optional feedback diagnostics (App Functionality)

All data: Linked to identity via receipt ID, NOT used for tracking

### TestFlight Setup
- Beta testers access the full app without App Store review
- Testers use sandbox Apple IDs for free StoreKit testing
- Purchases in TestFlight are free (sandbox environment)
- No special configuration needed - uses same StoreKit setup

## Pre-Submission Checklist

### Critical Items (Will Cause Rejection) - UPDATED
- [x] Remove `simulatePurchase` function from PurchaseManager.swift ✓
- [x] Privacy Policy live at https://daystart.bananaintelligence.ai/privacy ✓ 
- [x] Terms of Service live at https://daystart.bananaintelligence.ai/terms ✓
- [x] Wire up paywall buttons (Restore, Terms, Privacy) ✓
- [x] Fix Info.plist background modes ✓
- [x] NSCalendarsUsageDescription added to Info.plist ✓
- [x] Swift 6 concurrency issues resolved ✓
- [x] Product IDs updated to daystart_monthly_subscription & daystart_annual_subscription ✓
- [x] Paywall text updated to "Skip the scrolling, get briefed" ✓
- [x] dSYM generation settings added ✓
- [x] Test app works without purchase (good empty state)
- [x] Complete subscription metadata in App Store Connect
- [x] Ensure Supabase backend is running during review

### App Store Review Notes - Version 2025.09.16
```
QUICK TEST:
1. Use sandbox Apple ID
2. Complete onboarding → Purchase subscription → Tap "Start Welcome DayStart"
3. Audio plays immediately (2-3 min generation for first briefing)

WHAT'S NEW:
• Fixed permission timing bugs
• Improved day abbreviations (M, Tu, W, Th, F, Sa, Su)
• Faster buffering (2 min vs 3 min)
• More sports stories in longer briefings

WEATHERKIT:
• Yes, app uses WeatherKit for weather data
• Weather plays automatically in every briefing (no navigation needed)
• Toggle weather: Onboarding page 5 or Edit screen
• Apple Weather attribution properly displayed

SUBSCRIPTIONS:
• Product IDs: daystart_monthly_subscription, daystart_annual_subscription
• Free trials: 3-day (monthly), 7-day (annual)
• No login required - uses StoreKit receipt IDs

BACKGROUND PROCESSING:
Essential for prefetching audio 2 hours before scheduled wake time. Prevents playback delays.

PERMISSIONS (BOTH OPTIONAL):
• Location: Weather updates only
• Calendar: Event summaries only
• App works without permissions

CONTACT: nate@bananaintelligence.ai
```

### Completed ✓
- [x] App Store metadata prepared (descriptions, keywords, categories)
- [x] In-App Purchase products defined with updated IDs
- [x] Privacy manifest (PrivacyInfo.xcprivacy) created
- [x] App record created in App Store Connect
- [x] App icon (1024x1024) uploaded to App Store Connect
- [x] In-App Purchase products created in App Store Connect
- [x] StoreKit configuration file created and added to Xcode
- [x] StoreKit testing enabled in Xcode scheme
- [x] Subscription handling code already implemented in PurchaseManager
- [x] ITSAppUsesNonExemptEncryption added to Info.plist
- [x] Swift 6 concurrency compliance implemented
- [x] All concurrency errors resolved (HomeViewModel @MainActor, Timer closures fixed)
- [x] dSYM generation settings configured
- [x] Info.plist legal URLs added (privacy, terms, copyright)
- [x] NSCalendarsUsageDescription added to Info.plist
- [x] Paywall messaging updated
- [x] Archive successfully uploaded to App Store Connect
- [x] Build 10 (2025.09.4) submitted to App Store - Currently LIVE
- [x] Build 2 (2025.09.16) ready for next submission

### Remaining Tasks
- [x] App Store Connect setup
  - [x] Prepare app screenshots (iPhone & iPad sizes)
  - [x] Configure privacy settings as listed above
  
- [x] Testing & Validation
  - [x] Test purchase flow with sandbox account
  - [x] Test app works without location permission
  - [x] Test app works without calendar permission
  - [x] Test on clean device without debug environment
  
- [x] Marketing Assets (Optional)
  - [x] App preview video
  - [x] Marketing website at daystart.bananaintelligence.ai
  - [x] Support documentation at daystart.bananaintelligence.ai