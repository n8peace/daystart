import SwiftUI
import AVFoundation

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
			// COMMENTED OUT - Search functionality disabled for now
			// .overlay(alignment: .bottom) {
			// 	if !userPreferences.history.isEmpty {
			// 		searchOverlay
			// 	}
			// }
        }
        // COMMENTED OUT - Search functionality disabled for now
        // .onChange(of: searchQuery) { _ in
        //     // Reset pagination when search changes
        //     visibleCount = 10
        // }
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
            Section(header: Text("Streak")) {
                streakHeader
            }

            Section(header: Text("History")) {
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
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(BananaTheme.ColorToken.accent)
                    .frame(width: 20)
                
                Text("Current Streak")
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Text("\(streakManager.currentStreak)")
                    .font(.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Spacer()
                
                Text("Best: \(streakManager.bestStreak)")
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }

            // Mini 7-day strip
            let days = streakManager.lastNDaysStatuses(7).reversed()
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, entry in
                    VStack(spacing: 4) {
                        Text(weekdayName(for: entry.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
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


    private func color(for status: StreakManager.DayStatus) -> Color {
        switch status {
        case .completedSameDay: return BananaTheme.ColorToken.accent
        case .completedLate: return .gray
        case .inProgress: return BananaTheme.ColorToken.secondaryText
        case .notStarted: return BananaTheme.ColorToken.secondaryText.opacity(0.3)
        }
    }

    private func weekdayName(for date: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard let weekDay = WeekDay(weekday: weekday) else { return "" }
        return weekDay.name
    }

    // COMMENTED OUT - Search functionality disabled for now
    // Filtered by transcript search
    private var filteredHistory: [DayStartData] {
        let all = userPreferences.history
        // let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // guard !q.isEmpty else { return all }
        // return all.filter { $0.transcript.localizedCaseInsensitiveContains(q) }
        return all // Return all history without filtering for now
    }

    // Visible subset based on pagination
    private var displayedHistory: [DayStartData] {
        let source = filteredHistory
        let count = min(visibleCount, source.count)
        return Array(source.prefix(count))
    }

    // COMMENTED OUT - Search functionality disabled for now
    // Bottom overlay search bar
    // private var searchOverlay: some View {
    //     HStack(spacing: 8) {
    //         Image(systemName: "magnifyingglass")
    //             .foregroundColor(BananaTheme.ColorToken.secondaryText)
    //         TextField("Search transcripts", text: Binding(
    //             get: { searchQuery },
    //             set: { newValue in
    //                 textInputTask?.cancel()
    //                 let sanitized = String(newValue.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
    //                 searchQuery = sanitized
    //             }
    //         ))
    //             .textInputAutocapitalization(.never)
    //             .disableAutocorrection(true)
    //     }
    //     .padding(.horizontal, 14)
    //     .padding(.vertical, 10)
    //     .background(BananaTheme.ColorToken.card)
    //     .cornerRadius(14)
    //     .shadow(color: BananaTheme.ColorToken.shadow, radius: 8, x: 0, y: 4)
    //     .padding(.horizontal)
    //     .padding(.bottom)
    // }
}

struct HistoryRow: View {
    let dayStart: DayStartData
    let onPlay: (() -> Void)?
    @State private var isExpanded = false
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var streakManager = StreakManager.shared
    @State private var transcriptPollingTimer: Timer?
    @State private var pollingAttempt: Int = 0
    @State private var isPollingTranscript = false
    
    init(dayStart: DayStartData, onPlay: (() -> Void)? = nil) {
        self.dayStart = dayStart
        self.onPlay = onPlay
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            actionButtons

            // Show transcript only if expanded and content exists
            if isExpanded && canShowTranscript {
                transcriptView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
        .onAppear {
            // Start transcript polling if we only have a fallback/empty transcript
            if shouldStartPolling() && !isPollingTranscript {
                startTranscriptPolling()
            }
        }
        .onDisappear {
            // Clean up polling timer when view disappears
            stopTranscriptPolling()
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(BananaTheme.ColorToken.accent)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dayStart.date, style: .date)
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Text(dayStart.scheduledTime ?? dayStart.date, style: .time)
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            
            Spacer()
            
            // Action buttons and status
            HStack(spacing: 8) {
                if hasAudioFile && !dayStart.isDeleted {
                    Button(action: {
                        handlePlayButtonTap()
                    }) {
                        Image(systemName: audioPlayer.isPlaying && audioPlayer.currentTrackId == dayStart.id ? "pause.circle.fill" : "play.circle.fill")
                            .foregroundColor(BananaTheme.ColorToken.accent)
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                statusChip
            }
        }
        .padding(.vertical, 8)
    }

    // Simplified: Always show transcript if it exists and is not empty
    private var canShowTranscript: Bool {
        return !dayStart.transcript.isEmpty && !dayStart.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Helper to check if audio file exists, with fallback logic
    private var hasAudioFile: Bool {
        // First try the stored audio file path
        if let path = dayStart.audioFilePath, FileManager.default.fileExists(atPath: path) {
            return true
        }
        
        // Fallback: try both scheduledTime and date in audio cache
        let audioCache = ServiceRegistry.shared.audioCache
        if let scheduledTime = dayStart.scheduledTime, audioCache.hasAudio(for: scheduledTime) {
            return true
        }
        
        if audioCache.hasAudio(for: dayStart.date) {
            return true
        }
        
        return false
    }
    
    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(BananaTheme.ColorToken.primary.opacity(0.2))
            
            Text(dayStart.transcript)
                .font(.subheadline)
                .foregroundColor(BananaTheme.ColorToken.text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status messages for deleted or missing DayStarts
            if dayStart.isDeleted {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .frame(width: 20)
                    Text("DayStart Deleted")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if !hasAudioFile {
                HStack {
                    Image(systemName: "nosign")
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    Text("No DayStart")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // Audio player controls (always shown when audio is available)
            if hasAudioFile && !dayStart.isDeleted {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { 
                                // Show current time if this track is playing, otherwise show 0
                                audioPlayer.currentTrackId == dayStart.id ? audioPlayer.currentTime : 0
                            },
                            set: { newValue in 
                                // Only allow seeking if this track is currently loaded
                                if audioPlayer.currentTrackId == dayStart.id {
                                    audioPlayer.seek(to: newValue) 
                                }
                            }
                        ),
                        in: 0...max(getActualAudioDuration(), 1)
                    )
                    .accentColor(BananaTheme.ColorToken.accent)
                    .disabled(audioPlayer.currentTrackId != dayStart.id) // Disable if not currently loaded

                    HStack {
                        Text(timeString(audioPlayer.currentTrackId == dayStart.id ? audioPlayer.currentTime : 0))
                            .font(.caption)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        Spacer()
                        Text(timeString(getActualAudioDuration()))
                            .font(.caption)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Transcript toggle (only if we have transcript content)
            if canShowTranscript {
                HStack {
                    Button(action: { 
                        isExpanded.toggle()
                    }) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(BananaTheme.ColorToken.accent)
                                .frame(width: 20)
                            
                            Text("Transcript")
                                .font(.subheadline)
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(BananaTheme.ColorToken.accent)
                                .font(.caption)
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    private func handlePlayButtonTap() {
        let logger = DebugLogger.shared
        logger.log("🎵 History: Play button tapped for DayStart \(dayStart.id)", level: .info)
        
        if audioPlayer.currentTrackId != dayStart.id {
            logger.log("🎵 History: Loading new audio for DayStart", level: .info)
            
            // Try using stored audio file path first
            if let path = dayStart.audioFilePath, FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                audioPlayer.loadAudio(from: url, trackId: dayStart.id)
                audioPlayer.play()
            } else {
                // Fallback: get cached audio path
                let audioCache = ServiceRegistry.shared.audioCache
                let dateToUse = dayStart.scheduledTime ?? dayStart.date
                let audioPath = audioCache.getAudioPath(for: dateToUse)
                
                if FileManager.default.fileExists(atPath: audioPath.path) {
                    logger.log("🎵 History: Using cached audio path: \(audioPath.path)", level: .debug)
                    audioPlayer.loadAudio(from: audioPath, trackId: dayStart.id)
                    audioPlayer.play()
                } else {
                    logger.log("⚠️ History: No audio file found in cache or stored path", level: .warning)
                }
            }
        } else {
            logger.log("🎵 History: Track ID matches, toggling play/pause", level: .debug)
            audioPlayer.togglePlayPause()
        }
    }

    private var statusChip: some View {
        let s = streakManager.status(for: dayStart.scheduledTime ?? dayStart.date)
        switch s {
        case .completedSameDay:
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
            )
        case .completedLate:
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
            )
        case .inProgress:
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(BananaTheme.ColorToken.accent)
                        .font(.caption)
                    Text("In progress")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
            )
        case .notStarted:
            // Always show duration if we have it stored, regardless of audio file existence
            if dayStart.duration > 0 {
                return AnyView(
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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
        let actualDuration = getActualAudioDuration()
        let minutes = Int(actualDuration) / 60
        let seconds = Int(actualDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func getActualAudioDuration() -> TimeInterval {
        // First try to get audio file path
        var audioURL: URL?
        
        if let path = dayStart.audioFilePath, FileManager.default.fileExists(atPath: path) {
            audioURL = URL(fileURLWithPath: path)
        } else {
            // Fallback: try audio cache
            let audioCache = ServiceRegistry.shared.audioCache
            let dateToUse = dayStart.scheduledTime ?? dayStart.date
            let cachePath = audioCache.getAudioPath(for: dateToUse)
            
            if FileManager.default.fileExists(atPath: cachePath.path) {
                audioURL = cachePath
            }
        }
        
        // Get duration from audio file
        if let url = audioURL {
            let asset = AVAsset(url: url)
            let duration = asset.duration
            if duration.isValid && !duration.isIndefinite {
                return duration.seconds
            }
        }
        
        // Fallback to stored duration if can't read file
        return dayStart.duration
    }
    
    // MARK: - Transcript Polling
    
    private func isFallbackTranscript(_ transcript: String) -> Bool {
        return transcript.contains("Welcome to your DayStart! Please connect to the internet") ||
               transcript.isEmpty ||
               transcript.count < 50 // Very short transcript likely placeholder
    }
    
    private func shouldStartPolling() -> Bool {
        return isFallbackTranscript(dayStart.transcript) && 
               hasAudioFile && 
               !dayStart.isDeleted &&
               pollingAttempt < 6 // Max 6 attempts
    }
    
    private func startTranscriptPolling() {
        guard shouldStartPolling() else { return }
        
        isPollingTranscript = true
        let delay = min(5.0 * pow(2.0, Double(pollingAttempt)), 120.0) // Cap at 2 minutes
        
        transcriptPollingTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task {
                await fetchTranscriptUpdate()
            }
        }
    }
    
    private func stopTranscriptPolling() {
        transcriptPollingTimer?.invalidate()
        transcriptPollingTimer = nil
        isPollingTranscript = false
    }
    
    private func fetchTranscriptUpdate() async {
        pollingAttempt += 1
        
        do {
            let supabaseClient = ServiceRegistry.shared.supabaseClient
            let dateToUse = dayStart.scheduledTime ?? dayStart.date
            let audioStatus = try await supabaseClient.getAudioStatus(for: dateToUse)
            
            await MainActor.run {
                if let transcript = audioStatus.transcript, !isFallbackTranscript(transcript) {
                    // Success! Update the transcript and stop polling
                    UserPreferences.shared.updateHistory(
                        with: dayStart.id,
                        transcript: transcript,
                        duration: audioStatus.duration.map { TimeInterval($0) },
                        jobId: audioStatus.jobId
                    )
                    stopTranscriptPolling()
                } else if pollingAttempt < 6 {
                    // Continue polling with exponential backoff
                    startTranscriptPolling()
                } else {
                    // Max attempts reached, stop polling
                    stopTranscriptPolling()
                }
            }
        } catch {
            await MainActor.run {
                // On error, continue polling if we haven't hit max attempts
                if pollingAttempt < 6 {
                    startTranscriptPolling()
                } else {
                    stopTranscriptPolling()
                }
            }
        }
    }
}