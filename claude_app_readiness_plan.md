# DayStart App Store Readiness Plan

## Executive Summary

This document outlines the remaining compliance and technical items needed before DayStart can be released to the App Store. The app now uses a **purchase-based identity system** where users are identified by their StoreKit receipt IDs (paid = access).

**Timeline Recommendation:** Ready for App Store submission in ~1-2 weeks.

**Risk Level:** 🟡 **MEDIUM** - Core functionality complete but several App Store review blockers need immediate attention.

---

## 🟢 Completed Items

### 1. Purchase-Based Identity System ✅
**Solution Implemented:** Users are identified by StoreKit receipt IDs
- ✅ **PurchaseManager** handles all StoreKit 2 interactions
- ✅ **Receipt IDs** used as stable user identifiers
- ✅ **No traditional auth** - massively simplified architecture
- ✅ **API Integration** - x-client-info header contains receipt ID
- ✅ **Backend Auth Fixed** - create_job and get_jobs now use receipt-based auth
- ✅ **CORS Headers** - x-client-info added to all required functions
- ✅ **RLS Policies** - Migration 023 created for proper receipt-based access control

**Benefits:**
- No passwords, no account management
- Automatic cross-device sync via Apple ID
- Family Sharing support built-in
- Zero user friction

---

## ✅ Phase 1: Critical Deployment Items - COMPLETED

### 1. Deploy Backend Fixes ✅
**Status:** COMPLETED
**Time Taken:** ~90 minutes

**Completed Items:**
- ✅ Applied migration `023_fix_rls_for_receipt_auth.sql` to production Supabase
- ✅ Verified create_job and get_jobs work with x-client-info auth
- ✅ Tested purchase flow end-to-end with backend
- ✅ No more 401 authentication errors
- ✅ Receipt-based auth working in production

---

## 🟡 Phase 2: App Store Compliance (In Progress)

### 2. App Store Connect: Product Configuration ✅
**Status:** COMPLETED
**Time Taken:** ~2 hours

**Completed Items:**
- ✅ App record created in App Store Connect
- ✅ App icon (1024x1024) uploaded
- ✅ In-App Purchase products created with new IDs:
  - Monthly: `daystart_monthly_subscription` ($4.99, 3-day trial)
  - Annual: `daystart_annual_subscription` ($39.99, 7-day trial)
- ✅ Subscription Group "DayStart Premium" configured
- ✅ StoreKit configuration file created and added to Xcode
- ✅ StoreKit testing enabled in Xcode scheme

### 3. Privacy Manifest (PrivacyInfo.xcprivacy) ✅
**Status:** COMPLETED
**Time Taken:** ~15 minutes

**Completed Items:**
- ✅ Created PrivacyInfo.xcprivacy file at project root
- ✅ Declared required API usages:
  - UserDefaults (CA92.1)
  - File timestamps (C617.1)
- ✅ Declared data collection:
  - Audio data for app functionality (no tracking)

### 4. Legal Documents
**Status:** Critical for App Store approval (automatic rejection without valid URLs)
**Effort:** 2-3 hours

**Requirements:**

#### A. Privacy Policy (REQUIRED)
- **Must be hosted** at publicly accessible URL
- **Must be specific** to DayStart's functionality
- **Required sections:**
  - What data is collected (location, calendar events, usage analytics)
  - How data is used (personalized audio generation)
  - Data sharing (mention Supabase hosting)
  - User rights (data deletion, access)
  - StoreKit transaction data handling

#### B. Terms of Service (REQUIRED)
- **Must be hosted** at publicly accessible URL  
- **Required sections:**
  - Subscription terms and billing
  - Content usage rights
  - AI-generated content disclaimers
  - Service availability
  - Cancellation policy

#### C. Update Info.plist
```xml
<key>NSHumanReadableCopyright</key>
<string>© 2025 Banana Intelligence. All rights reserved.</string>
<key>NSPrivacyPolicyURL</key>
<string>https://yourdomain.com/privacy</string>
<key>NSTermsOfServiceURL</key>
<string>https://yourdomain.com/terms</string>
```

#### D. App Store Connect Legal Setup
1. Go to "App Information" → "General Information"
2. Add Privacy Policy URL
3. Add Terms of Service URL (optional but recommended)
4. Ensure copyright notice is current

### 5. App Store Metadata & Assets
**Status:** Required for submission
**Effort:** 4-6 hours

#### A. App Store Connect → "App Store" Tab

**App Information:**
- Name: "DayStart" (must match CFBundleDisplayName)
- Subtitle: "AI Morning Briefings" (30 chars max)
- Category: Primary: "News", Secondary: "Productivity"

**App Description (4000 characters max):**
```
Start every morning perfectly informed with DayStart's AI-generated audio briefings.

Personalized for you:
• Weather updates for your location
• Today's top news stories
• Your calendar events
• Stock market updates
• Daily inspiration quotes
• Sports scores for your teams

Key Features:
✓ Hands-free audio briefings
✓ Smart scheduling with alarms
✓ Customizable content preferences
✓ High-quality AI voice synthesis
✓ Offline listening capability
✓ Privacy-focused design

Perfect for busy professionals, commuters, and anyone who wants to start their day informed without scrolling through apps.

Premium subscription includes unlimited briefings, advanced customization, and priority processing.
```

**Keywords (100 characters max):**
`morning,news,briefing,audio,ai,weather,calendar,productivity,alarm,voice`

#### B. Screenshots (REQUIRED)
**6.7" Display (iPhone 14 Pro Max):** 1290 × 2796 pixels
**6.5" Display (iPhone XS Max):** 1242 × 2688 pixels  
**5.5" Display (iPhone 8 Plus):** 1242 × 2208 pixels

**Required Screenshots (minimum 3, maximum 10):**
1. Main onboarding screen
2. Content preferences setup
3. Subscription screen
4. Audio player with briefing
5. Settings/customization screen

#### C. App Preview Video (Recommended)
- Duration: 15-30 seconds
- Same sizes as screenshots
- Show key user flow: setup → preferences → listening

#### D. Additional Metadata
- **Support URL:** Required (create simple support page)
- **Marketing URL:** Optional
- **Version Notes:** "Initial release with AI-powered morning briefings"
- **Rating:** Choose appropriate age rating (likely 4+)
- **Content Rights:** Declare use of third-party content (news, weather data)

### 6. StoreKit Testing & TestFlight
**Status:** Required for production confidence
**Effort:** 6-8 hours

#### A. Sandbox Testing Setup
1. **App Store Connect → "Users and Access" → "Sandbox Testers"**
   - Create 2-3 test Apple IDs
   - Use different regions if targeting multiple markets
   - Verify email addresses

2. **Device Setup:**
   - Sign out of production App Store on test device
   - Sign in with sandbox account
   - Ensure "Sandbox Environment" appears in Settings

#### B. Subscription Testing Checklist
- [ ] **Monthly subscription purchase**
  - Complete purchase flow
  - Verify receipt generated
  - Confirm API calls succeed with receipt
  - Test DayStart creation works

- [ ] **Annual subscription purchase**
  - Complete purchase flow
  - Verify pricing discount shows correctly
  - Test receipt validation

- [ ] **Restore Purchases**
  - Delete app, reinstall
  - Tap "Restore Purchases"
  - Verify subscription status restored

- [ ] **Family Sharing** (if enabled)
  - Test with family member account
  - Verify shared subscription access

- [ ] **Subscription Management**
  - Test cancellation flow
  - Verify grace period behavior
  - Test resubscription

#### C. TestFlight Distribution
1. **Upload Build:**
   - Archive app in Xcode
   - Upload to App Store Connect
   - Wait for processing (30-90 minutes)

2. **Internal Testing:**
   - Add internal testers
   - Test on multiple devices/iOS versions
   - Verify all functionality works

3. **External Testing (Optional):**
   - Submit for beta review (24-48 hours)
   - Add external testers
   - Gather feedback before submission

---

## 🔴 Critical Review Blockers (Fix Before Submission)

### 1. Privacy/Terms Documents
**Issue:** PRIVACY_POLICY.md and TERMS_OF_SERVICE.md have placeholders
**Fix:** Replace all bracketed placeholders with real info and host at:
- https://daystart.bananaintelligence.ai/privacy
- https://daystart.bananaintelligence.ai/terms

### 2. Paywall Button Functionality
**Issue:** "Restore," "Terms," "Privacy" buttons do nothing (OnboardingView.swift L1515-1527)
**Fix:** Wire up:
- Restore → Call `purchaseManager.restorePurchases()`
- Terms → Open terms URL in Safari
- Privacy → Open privacy URL in Safari

### 3. Info.plist Background Modes
**Issue:** Over-declared modes including invalid "background-processing"
**Fix:** Keep only:
- audio
- processing
Remove: background-processing, fetch, remote-notification

### 4. Remove simulatePurchase Function
**Issue:** Test function in PurchaseManager.swift will cause rejection
**Fix:** Delete entire `simulatePurchase` function

---

## 🟢 Phase 3: Post-Launch Improvements

### 1. Enhanced Analytics
- Track subscription conversions
- Monitor daily active users
- Measure feature usage

### 2. Push Notifications
- Remind users of upcoming DayStarts
- Re-engagement campaigns

### 3. Additional Features
- Widget support
- Apple Watch companion app
- Siri Shortcuts integration

---

## Testing Checklist

### Before Submission:
- [x] Backend auth issues resolved (create_job, get_jobs fixed)
- [x] CORS headers include x-client-info
- [x] RLS policies support receipt-based auth
- [x] Deploy migration 023 to production
- [x] App record created in App Store Connect
- [x] In-App Purchase products configured
- [x] Privacy manifest (PrivacyInfo.xcprivacy) created
- [x] StoreKit configuration added to Xcode
- [ ] Test purchase flow with sandbox account
- [ ] Verify receipt validation works
- [ ] Test restore purchases
- [ ] Check all API calls include receipt ID
- [ ] Test on multiple devices
- [ ] Verify Family Sharing works

### StoreKit Testing:
1. Create sandbox test accounts
2. Test monthly subscription flow
3. Test annual subscription flow
4. Test restore purchases
5. Test subscription management

---

## Risk Assessment

| Item | Risk Level | Impact |
|------|------------|---------|
| Backend migration not deployed | HIGH | App won't work for users |
| Missing products in App Store Connect | HIGH | Cannot test real purchases |
| No privacy manifest | HIGH | Automatic rejection |
| Missing legal documents | HIGH | Rejection |
| Incomplete metadata | MEDIUM | Delay in review |

---

## Next Steps

1. **COMPLETED:** ✅ Deploy migration 023 to production Supabase
2. **COMPLETED:** ✅ Test backend fixes work end-to-end
3. **COMPLETED:** ✅ Configure subscription products in App Store Connect
4. **COMPLETED:** ✅ Create and add PrivacyInfo.xcprivacy manifest
5. **COMPLETED:** ✅ Add StoreKit configuration to Xcode
6. **TODAY:** Test In-App Purchases in sandbox environment
7. **Day 1:** Create and host legal documents (privacy policy, terms)
8. **Day 2:** Prepare App Store screenshots (iPhone & iPad sizes)
9. **Day 3:** Prepare App Store metadata and description
10. **Day 4:** Upload TestFlight build and begin testing
11. **Day 5-6:** Complete comprehensive StoreKit testing
12. **Week 2:** Submit for App Store review

---

## Simplified Architecture Benefits

With the purchase-based identity system:
- **No account creation flow** - Users just purchase
- **No password resets** - Apple handles everything
- **No email verification** - Not needed
- **No social logins** - Unnecessary complexity removed
- **Automatic account recovery** - Via App Store restore

This approach aligns perfectly with the app's value proposition: pay once, get your personalized morning audio. No friction, no complexity.

---

## Contact for Questions

For implementation questions about the purchase-based system, refer to:
- `/DayStart/Core/Services/PurchaseManager.swift`
- `/supabase/migrations/022_receipt_based_auth.sql`
- `/supabase/migrations/023_fix_rls_for_receipt_auth.sql`
- `/supabase/functions/create_job/index.ts` (updated for receipt auth)
- `/supabase/functions/get_jobs/index.ts` (updated for receipt auth)