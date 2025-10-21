import Foundation

final class SharePromptManager {
    static let shared = SharePromptManager()
    private let defaults = UserDefaults.standard
    
    private enum Key {
        static let hasPromptedAfterThird = "sharePrompt.hasPromptedAfterThird"
    }
    
    private init() {}
    
    var hasPromptedAfterThirdCompletion: Bool {
        defaults.bool(forKey: Key.hasPromptedAfterThird)
    }
    
    func shouldShowSharePrompt() -> Bool {
        // Don't show if already prompted
        guard !hasPromptedAfterThirdCompletion else { return false }
        
        // Check if user has exactly 3 completed DayStarts
        let completionCount = getCompletedDayStartCount()
        return completionCount == 3
    }
    
    func markSharePromptShown() {
        defaults.set(true, forKey: Key.hasPromptedAfterThird)
    }
    
    private func getCompletedDayStartCount() -> Int {
        let history = UserPreferences.shared.history
        
        // Count non-deleted, successful DayStart completions
        let completedCount = history.filter { dayStart in
            // Only count completed, non-deleted DayStarts
            return !dayStart.isDeleted && 
                   dayStart.duration > 0 && 
                   !dayStart.transcript.isEmpty &&
                   !dayStart.transcript.contains("Welcome to your DayStart! Please connect")
        }.count
        
        return completedCount
    }
}