# App Store Connect Configuration for DayStart AI v1.0

## Basic Information
- **App Name:** DayStart AI
- **Version:** 1.0
- **Support URL:** https://daystart.bananaintelligence.ai
- **Marketing URL:** https://daystart.bananaintelligence.ai

## Keywords (100 characters max)
```
morning,briefing,ai,news,weather,calendar,audio,productivity,routine,personalized
```

## Promotional Text (170 characters max)
```
Start your day informed! Get personalized AI audio briefings with weather, news, calendar events & more - all in one hands-free morning update.
```

## App Description (4000 characters max)
```
Transform your morning routine with DayStart AI - your personal AI assistant that creates custom audio briefings tailored just for you.

Wake up to a professionally narrated summary of everything you need to know for the day ahead. No more frantically checking multiple apps or scrolling through endless feeds. DayStart AI brings it all together in one seamless audio experience.

WHAT'S INCLUDED IN YOUR BRIEFING:
• Local Weather Forecast - Current conditions and today's outlook for your exact location
• Breaking News - Top stories from trusted sources, intelligently curated
• Calendar Events - Your schedule for the day, meeting times, and reminders  
• Stock Market Updates - Track your portfolio and market movements
• Sports Scores - Results from your favorite teams
• Daily Inspiration - Motivational quotes to energize your morning

KEY FEATURES:
• AI-Powered Personalization - Our advanced AI learns your preferences and interests
• Natural Voice Synthesis - Crystal-clear narration that sounds remarkably human
• Offline Playback - Download briefings for your commute
• Customizable Content - Choose exactly what you want to hear

PERFECT FOR:
• Busy professionals who need to stay informed
• Commuters who want hands-free news updates  
• Morning exercisers looking for audio content
• Anyone who values their time and wants a smarter morning routine

HOW IT WORKS:
1. Set your wake-up time and content preferences
2. DayStart AI generates your personalized briefing overnight
3. Wake up to your custom audio briefing or play it when ready
4. Start your day informed, inspired, and ahead of the curve

SUBSCRIPTION OPTIONS:
• Monthly subscription: $4.99/month with 3-day free trial
• Annual subscription: $39.99/year with 7-day free trial (save 33%)

Skip the scrolling, get briefed. Because the best days start with the right information.

Privacy Policy: https://daystart.bananaintelligence.ai/privacy
Terms of Service: https://daystart.bananaintelligence.ai/terms
```

## Subtitle (30 characters max)
```
Personalized AI Morning Briefings
```

## What's New in Version 1.0
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
1. **Contact Info → Name**: For personalized greetings (App Functionality)
2. **Location → Coarse Location**: City/state for weather (App Functionality)
3. **User Content → Audio Data**: Generated briefings (App Functionality)
4. **Identifiers → User ID**: Purchase receipt ID (App Functionality)
5. **Usage Data → Product Interaction**: App settings/preferences (App Functionality)
6. **Diagnostics → Performance Data**: Server logs (App Functionality)
7. **Diagnostics → Other Diagnostic Data**: Error logs (App Functionality)

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
- [ ] Test app works without purchase (good empty state)
- [ ] Complete subscription metadata in App Store Connect
- [ ] Ensure Supabase backend is running during review

### App Store Review Notes (Full)
```
TESTING INSTRUCTIONS:
- Use sandbox Apple ID for in-app purchases
- App requires network connectivity for audio generation
- First audio briefing may take 2-3 minutes to generate
- Subsequent briefings are faster due to caching

BACKGROUND PROCESSING USAGE:
BGProcessing tasks (audio-prefetch, snapshot-update) are used to prefetch generated audio and refresh data snapshots near scheduled alarm times. Tasks are infrequent, short-duration, and user-initiated through the scheduling system.

PRIVACY & PERMISSIONS:
- Location permission is optional - used only for weather updates if granted
- Calendar permission is optional - used only for including events if granted  
- App functions without permissions but with reduced personalization
- All permissions have clear purpose strings explaining usage

TECHNICAL DETAILS:
- Supabase keys in Info.plist are public anonymous keys with Row Level Security enforced
- No sensitive secrets are included in the app bundle
- Receipt-based authentication system - users identified by StoreKit transaction IDs
- Audio generation happens server-side, app streams/caches results

SUBSCRIPTION TESTING:
Monthly and Annual subscriptions both include free trials (3-day and 7-day respectively). Test with sandbox account - purchases are free in TestFlight. Restore purchases functionality available on paywall screen.

CONTENT:
All news, weather, and market data is aggregated from public APIs and feeds. The app personalizes audio briefings by combining this public information with the user's calendar events and preferences. AI-generated summaries are created server-side based on this personalized data mix.
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

### Remaining Tasks
- [ ] App Store Connect setup
  - [ ] Prepare app screenshots (iPhone & iPad sizes)
  - [ ] Configure privacy settings as listed above
  
- [ ] Testing & Validation
  - [ ] Test purchase flow with sandbox account
  - [ ] Test app works without location permission
  - [ ] Test app works without calendar permission
  - [ ] Test on clean device without debug environment
  
- [ ] Marketing Assets (Optional)
  - [ ] App preview video
  - [ ] Marketing website at daystart.bananaintelligence.ai
  - [ ] Support documentation at help.bananaintelligence.ai