# Weather Permission Bug Fix - Rollback Instructions

## Changes Made (Current Implementation)

Fixed timing issue where weather permission dialog appeared after page navigation, causing weather to be disabled even when users granted permission.

### Modified File
- `/DayStart/Features/Onboarding/OnboardingView.swift`

### Specific Changes
1. Removed automatic page navigation from `requestLocationPermission()` function
2. Removed automatic page navigation from `requestCalendarPermission()` function  
3. Updated weather permission button to handle navigation after permission is determined
4. Updated calendar permission button to handle navigation after permission is determined
5. Removed swipe gesture interceptor that was triggering permission requests

## Rollback Options

### Option 1: Git Revert (Recommended - Fastest)
```bash
git checkout bb68eb1 -- DayStart/Features/Onboarding/OnboardingView.swift
```

### Option 2: File Backup Restore
```bash
cp DayStart/Features/Onboarding/OnboardingView.swift.backup DayStart/Features/Onboarding/OnboardingView.swift
```

### Option 3: Git Reset (if no other changes made)
```bash
git reset --hard bb68eb1
```

### Option 4: Manual Revert
If you need to manually revert specific changes:

1. In `requestLocationPermission()` function, add back:
   ```swift
   withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
       currentPage = 6
   }
   ```

2. In `requestCalendarPermission()` function, add back:
   ```swift
   withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
       currentPage = 7
   }
   ```

3. Revert weather permission button (around line 906):
   ```swift
   Button(action: {
       Task {
           await requestLocationPermission()
       }
   })
   ```

4. Revert calendar permission button (around line 1043):
   ```swift
   Button(action: {
       Task {
           await requestCalendarPermission()
       }
   })
   ```

5. Re-add the `.simultaneousGesture()` modifier after `.animation(.easeInOut, value: currentPage)`

## Verification After Rollback
1. Check that `git diff` shows no changes from commit bb68eb1
2. Build and run the app
3. Test onboarding flow to ensure it matches previous behavior

## Clean Up
After successful rollback:
```bash
rm DayStart/Features/Onboarding/OnboardingView.swift.backup
rm ROLLBACK_INSTRUCTIONS.md
```