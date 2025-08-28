# Remaining Tasks Before App Store Submission

## ✅ Completed (Just Now)
1. **Removed simulatePurchase function** - Eliminated test code that would cause rejection
2. **Wired up paywall buttons**:
   - Terms → Opens https://daystart.bananaintelligence.ai/terms
   - Privacy → Opens https://daystart.bananaintelligence.ai/privacy
   - Restore → Calls purchaseManager.restorePurchases()
3. **Fixed Info.plist** - Removed invalid background modes (kept only audio & processing)

## 🔴 Critical Remaining Tasks

### 1. Legal Documents (MUST DO)
**Files to update:**
- `PRIVACY_POLICY.md`
- `TERMS_OF_SERVICE.md`

**Required actions:**
- Replace ALL [bracketed] placeholders with real information:
  - [Month Day, Year] → Actual effective date
  - [Banana Intelligence LLC full legal name] → Your company name
  - [Address] → Your business address
  - [Privacy contact email] → Your contact email
  - [Data Protection Officer] → Name or "Not Applicable"
- Host these documents at:
  - https://daystart.bananaintelligence.ai/privacy
  - https://daystart.bananaintelligence.ai/terms

### 2. Testing Checklist
**Purchase Testing (with Sandbox Apple ID):**
- [ ] Test monthly subscription purchase ($4.99)
- [ ] Test annual subscription purchase ($39.99)
- [ ] Test restore purchases functionality
- [ ] Test canceling and re-purchasing

**Permission Testing:**
- [ ] Test app works WITHOUT location permission
- [ ] Test app works WITHOUT calendar permission

**Empty State Testing:**
- [ ] Verify app shows appropriate UI before purchase
- [ ] Ensure reviewer can understand app value without buying

**General Testing:**
- [ ] Test on clean device (no debug environment)
- [ ] Verify audio generation works
- [ ] Check all UI flows are smooth

## 📝 App Store Review Notes
Remember to include these in your submission notes:
1. "BGProcessing tasks (audio-prefetch, snapshot-update) are used to prefetch generated audio and refresh snapshots near scheduled times; tasks are rare, short, and user-initiated by schedule."
2. "Supabase keys in Info.plist are public anon keys with Row Level Security enforced; no sensitive secrets are included in the app."

## 🚀 Submission Ready
Once the above tasks are complete, you're ready to:
1. Archive and upload to App Store Connect
2. Submit for review with confidence

Good luck with your launch! 🎉