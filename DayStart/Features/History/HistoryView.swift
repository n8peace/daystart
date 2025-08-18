import SwiftUI

struct HistoryView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var userPreferences: UserPreferences
    @State private var visibleCount: Int = 10
    @State private var searchQuery: String = ""
    @ObservedObject private var streakManager = StreakManager.shared
    @State private var dismissTask: Task<Void, Never>?
    @State private var textInputTask: Task<Void, Never>?
    
    private let logger = DebugLogger.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                if userPreferences.history.isEmpty {
                    emptyStateView
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                logger.log("📚 History view appeared", level: .info)
                logger.logUserAction("History opened", details: [
                    "totalItems": userPreferences.history.count,
                    "isEmpty": userPreferences.history.isEmpty,
                    "visibleCount": visibleCount
                ])
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismissTask?.cancel()
                        dismissTask = Task {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .foregroundColor(BananaTheme.ColorToken.text)
                }
            }
			.overlay(alignment: .bottom) {
				if !userPreferences.history.isEmpty {
					searchOverlay
				}
			}
        }
        .onChange(of: searchQuery) { _ in
            // Reset pagination when search changes
            visibleCount = 10
        }
        .onDisappear {
            dismissTask?.cancel()
            textInputTask?.cancel()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
            
            Text("No DayStarts Yet")
                .adaptiveFont(BananaTheme.Typography.title2)
            
            Text("Your completed DayStarts will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var historyList: some View {
        List {
            Section(header: sectionHeader("DayStart Streak")) {
                streakHeader
            }

            Section(header: sectionHeader("Your history")) {
                let items = displayedHistory
                ForEach(Array(items.enumerated()), id: \.element.id) { index, dayStart in
                    VStack(alignment: .leading, spacing: 0) {
                        HistoryRow(dayStart: dayStart)
                    }
                    .padding(12)
                    .background(BananaTheme.ColorToken.card)
                    .cornerRadius(12)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowSeparator(.hidden)
                    .onAppear {
                            // Infinite scroll: load 10 more when last visible appears
                            if index == items.count - 1 {
                                let total = filteredHistory.count
                                if visibleCount < total {
                                    visibleCount = min(visibleCount + 10, total)
                                }
                            }
                        }
                }
            }
        }
    }

    // Header card that summarizes streaks
    private var streakHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Label("\(streakManager.currentStreak)", systemImage: "flame.fill")
                            .foregroundColor(BananaTheme.ColorToken.accent)
                            .adaptiveFont(BananaTheme.Typography.title2)
                        Text("Best: \(streakManager.bestStreak)")
                            .adaptiveFont(BananaTheme.Typography.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Mini 7-day strip
            let days = streakManager.lastNDaysStatuses(7).reversed()
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, entry in
                    VStack(spacing: 4) {
                        Text(weekdayAbbrev(entry.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Circle()
                            .fill(color(for: entry.status))
                            .frame(width: 14, height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .adaptiveFont(BananaTheme.Typography.headline)
            .foregroundColor(.primary)
            .textCase(nil)
    }

    private func color(for status: StreakManager.DayStatus) -> Color {
        switch status {
        case .completedSameDay: return BananaTheme.ColorToken.accent
        case .completedLate: return .gray
        case .inProgress: return BananaTheme.ColorToken.secondaryText
        case .notStarted: return BananaTheme.ColorToken.secondaryText.opacity(0.3)
        }
    }

    private func weekdayAbbrev(_ date: Date) -> String {
        return FormatterCache.shared.weekdayAbbrevFormatter.string(from: date)
    }

    // Filtered by transcript search
    private var filteredHistory: [DayStartData] {
        let all = userPreferences.history
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { $0.transcript.localizedCaseInsensitiveContains(q) }
    }

    // Visible subset based on pagination
    private var displayedHistory: [DayStartData] {
        let source = filteredHistory
        let count = min(visibleCount, source.count)
        return Array(source.prefix(count))
    }

    // Bottom overlay search bar
    private var searchOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
            TextField("Search transcripts", text: Binding(
                get: { searchQuery },
                set: { newValue in
                    textInputTask?.cancel()
                    let sanitized = String(newValue.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
                    searchQuery = sanitized
                }
            ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BananaTheme.ColorToken.card)
        .cornerRadius(14)
        .shadow(color: BananaTheme.ColorToken.shadow, radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .padding(.bottom)
    }
}

struct HistoryRow: View {
    let dayStart: DayStartData
    let onPlay: (() -> Void)?
    @State private var isExpanded = false
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var streakManager = StreakManager.shared
    
    init(dayStart: DayStartData, onPlay: (() -> Void)? = nil) {
        self.dayStart = dayStart
        self.onPlay = onPlay
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            actionButtons

            // Show transcript only if audio exists or entry is marked deleted
            if isExpanded && canShowTranscript {
                transcriptView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayStart.date, style: .date)
                    .adaptiveFont(BananaTheme.Typography.headline)
                
                Text(dayStart.date, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statusChip
        }
    }

    // Transcript is available when there is audio or the entry is marked deleted
    private var canShowTranscript: Bool {
        if dayStart.isDeleted { return true }
        if let path = dayStart.audioFilePath, FileManager.default.fileExists(atPath: path) { return true }
        return false
    }
    
    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.caption)
                .adaptiveFontWeight(light: .semibold, dark: .bold)
                .foregroundColor(.secondary)
            
            Text(dayStart.transcript)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(BananaTheme.ColorToken.card)
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let path = dayStart.audioFilePath, FileManager.default.fileExists(atPath: path), !dayStart.isDeleted {
                    // Play button (banana yellow)
                    Button(action: {
                        let logger = DebugLogger.shared
                        logger.log("🎵 History: Play button tapped for DayStart \(dayStart.id)", level: .info)
                        logger.log("🎵 History: Audio path exists: \(path)", level: .debug)
                        
                        // Always use direct audio player control for compact history playback
                        logger.log("🎵 History: Using direct AudioPlayerManager control for compact playback", level: .info)
                        
                        // Debug current audio player state
                        logger.log("🎵 History Debug: currentTrackId=\(audioPlayer.currentTrackId?.uuidString ?? "nil"), dayStartId=\(dayStart.id.uuidString)", level: .debug)
                        logger.log("🎵 History Debug: isPlaying=\(audioPlayer.isPlaying), currentTime=\(audioPlayer.currentTime), duration=\(audioPlayer.duration)", level: .debug)
                        
                        if audioPlayer.currentTrackId != dayStart.id {
                            logger.log("🎵 History: Loading new audio for DayStart", level: .info)
                            audioPlayer.loadAudio(for: dayStart)
                        } else {
                            logger.log("🎵 History: Track ID matches, skipping load. Checking if audio is actually ready...", level: .debug)
                        }
                        
                        audioPlayer.togglePlayPause()
                        logger.log("🎵 History: Toggle play/pause called, isPlaying: \(audioPlayer.isPlaying)", level: .info)
                    }) {
                        Label(audioPlayer.isPlaying && audioPlayer.currentTrackId == dayStart.id ? "Pause" : "Play",
                              systemImage: audioPlayer.isPlaying && audioPlayer.currentTrackId == dayStart.id ? "pause.circle.fill" : "play.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(BananaTheme.ColorToken.accent)
                    }
                    .buttonStyle(.bordered)
                } else if dayStart.isDeleted {
                    // DayStart Deleted (red)
                    Label("DayStart Deleted", systemImage: "trash")
                        .font(.subheadline)
                        .foregroundColor(.red)
                } else {
                    // No DayStart (gray)
                    Label("No DayStart", systemImage: "nosign")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                if canShowTranscript {
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 6) {
                            Text("Transcript")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(BananaTheme.ColorToken.accent)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if audioPlayer.currentTrackId == dayStart.id {
                // Inline voicemail-style player
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { audioPlayer.currentTime },
                            set: { newValue in audioPlayer.seek(to: newValue) }
                        ),
                        in: 0...max(audioPlayer.duration, 1)
                    )
                    .accentColor(BananaTheme.ColorToken.accent)

                    HStack {
                        Text(timeString(audioPlayer.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(timeString(audioPlayer.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var statusChip: some View {
        let s = streakManager.status(for: dayStart.scheduledTime ?? dayStart.date)
        switch s {
        case .completedSameDay:
            return AnyView(
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
            )
        case .completedLate:
            return AnyView(
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark").foregroundColor(.orange)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
            )
        case .inProgress:
            return AnyView(
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").foregroundColor(BananaTheme.ColorToken.accent)
                    Text("In progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
            )
        case .notStarted:
            if let path = dayStart.audioFilePath, FileManager.default.fileExists(atPath: path), !dayStart.isDeleted {
                return AnyView(
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BananaTheme.ColorToken.card)
                        .cornerRadius(8)
                )
            } else {
                return AnyView(EmptyView())
            }
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var formattedDuration: String {
        let minutes = Int(dayStart.duration) / 60
        let seconds = Int(dayStart.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}