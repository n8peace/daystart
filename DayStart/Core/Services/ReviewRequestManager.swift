import Foundation
import StoreKit
import UIKit

final class ReviewRequestManager {
    static let shared = ReviewRequestManager()
    private let defaults = UserDefaults.standard
    
    private enum Key {
        static let promptedFirstCompletion = "review.promptedFirstCompletion"
    }
    
    var hasPromptedAfterFirstCompletion: Bool {
        defaults.bool(forKey: Key.promptedFirstCompletion)
    }
    
    func markPromptedAfterFirstCompletion() {
        defaults.set(true, forKey: Key.promptedFirstCompletion)
    }
    
    func requestSystemReviewIfPossible() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}


