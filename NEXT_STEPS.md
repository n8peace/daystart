# DayStart - Next Steps Checklist

**Last Updated:** January 31, 2025

## 🎯 Immediate Actions (Today/Tomorrow)

### 1. Host Legal Documents 🔴
- [ ] Upload PRIVACY_POLICY.md to https://daystart.bananaintelligence.ai/privacy
- [ ] Upload TERMS_OF_SERVICE.md to https://daystart.bananaintelligence.ai/terms
- [ ] Verify URLs are accessible and properly formatted

### 2. Build & Upload to App Store Connect 🔴
- [ ] Clean build folder in Xcode (Product → Clean Build Folder)
- [ ] Update version/build number if needed
- [ ] Archive app (Product → Archive)
- [ ] Upload to App Store Connect via Xcode Organizer
- [ ] Wait for processing (~30-90 minutes)
- [ ] Select build in App Store Connect

## 📱 Testing Phase (2-3 Days)

### 3. Sandbox Purchase Testing
- [ ] Create 2-3 sandbox test accounts in App Store Connect
- [ ] Sign out of real App Store account on test device
- [ ] Sign in with sandbox account
- [ ] Test monthly subscription:
  - [ ] Purchase flow completes
  - [ ] Receipt validation succeeds
  - [ ] DayStart creation works
  - [ ] Audio generation succeeds
- [ ] Test annual subscription:
  - [ ] Purchase flow completes
  - [ ] Correct pricing shown (33% discount)
  - [ ] Receipt validation succeeds
- [ ] Test restore purchases:
  - [ ] Delete and reinstall app
  - [ ] Tap "Restore Purchases"
  - [ ] Verify subscription restored
- [ ] Test cancellation flow
- [ ] Test resubscription

### 4. TestFlight Distribution
- [ ] Add internal testers (team members)
- [ ] Test on multiple devices:
  - [ ] iPhone 15 Pro
  - [ ] iPhone 14
  - [ ] iPhone 13 mini
  - [ ] Different iOS versions (17.0+)
- [ ] Verify critical flows:
  - [ ] Onboarding experience
  - [ ] Schedule setup
  - [ ] Audio playback
  - [ ] Background prefetch
  - [ ] Notifications

### 5. External TestFlight (Optional but Recommended)
- [ ] Submit build for external TestFlight review
- [ ] Add 10-20 external testers
- [ ] Create feedback form/survey
- [ ] Gather user feedback on:
  - [ ] Onboarding clarity
  - [ ] Audio quality
  - [ ] App performance
  - [ ] Any bugs/issues

## 🚀 App Store Submission (Day 3-4)

### 6. Final Pre-Submission Checks
- [ ] All TestFlight feedback addressed
- [ ] No critical bugs found
- [ ] Purchase flow tested end-to-end
- [ ] Legal documents live and accessible
- [ ] App Store Connect fully configured

### 7. Submit for Review
- [ ] Click "Submit for Review" in App Store Connect
- [ ] Answer review questions:
  - Export compliance (uses encryption)
  - Content rights (third-party APIs)
  - Advertising identifier (not used)
- [ ] Add review notes if needed
- [ ] Submit!

## 📊 Post-Submission Monitoring

### 8. During Review (5-7 days typical)
- [ ] Monitor email for reviewer questions
- [ ] Be ready to respond quickly to any issues
- [ ] Have TestFlight access ready for reviewers

### 9. Post-Launch Preparation
- [ ] Prepare launch announcement
- [ ] Set up customer support process
- [ ] Monitor initial reviews/ratings
- [ ] Track subscription metrics
- [ ] Plan first update based on feedback

## 🎉 Success Metrics to Track

- Conversion rate (free trial → paid)
- Daily active users
- Subscription retention rate
- App Store ratings
- Customer support tickets
- Audio generation success rate
- Background prefetch success rate

## 📝 Notes

- **Review Time**: First submission typically takes 5-7 days
- **Rejection Risk**: Low - all common rejection reasons addressed
- **Support Email**: nate@bananaintelligence.ai configured
- **Analytics**: Consider adding for post-launch insights

## ✅ Completion Status

All critical blockers have been resolved. The app is technically ready for submission once the build is uploaded and testing is complete.