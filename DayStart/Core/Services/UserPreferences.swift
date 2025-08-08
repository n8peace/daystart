import Foundation
import SwiftUI
import Combine

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private let userDefaults = UserDefaults.standard
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            userDefaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    @Published var schedule: DayStartSchedule {
        didSet {
            saveSchedule()
        }
    }
    
    @Published var settings: UserSettings {
        didSet {
            saveSettings()
        }
    }
    
    @Published var history: [DayStartData] {
        didSet {
            saveHistory()
        }
    }
    
    private init() {
        self.hasCompletedOnboarding = userDefaults.bool(forKey: "hasCompletedOnboarding")
        self.schedule = Self.loadSchedule()
        self.settings = Self.loadSettings()
        self.history = Self.loadHistory()
    }
    
    private static func loadSchedule() -> DayStartSchedule {
        guard let data = UserDefaults.standard.data(forKey: "schedule"),
              let schedule = try? JSONDecoder().decode(DayStartSchedule.self, from: data) else {
            return DayStartSchedule()
        }
        return schedule
    }
    
    private static func loadSettings() -> UserSettings {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return UserSettings.default
        }
        return settings
    }
    
    private static func loadHistory() -> [DayStartData] {
        guard let data = UserDefaults.standard.data(forKey: "history"),
              let history = try? JSONDecoder().decode([DayStartData].self, from: data) else {
            return []
        }
        return history
    }
    
    private func saveSchedule() {
        if let data = try? JSONEncoder().encode(schedule) {
            userDefaults.set(data, forKey: "schedule")
        }
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: "settings")
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: "history")
        }
    }
    
    func addToHistory(_ dayStart: DayStartData) {
        history.insert(dayStart, at: 0)
        if history.count > 30 {
            history.removeLast()
        }
    }
    
    func isWithinLockoutPeriod(of date: Date) -> Bool {
        let hoursUntil = date.timeIntervalSinceNow / 3600
        return hoursUntil < 4 && hoursUntil > 0
    }
}