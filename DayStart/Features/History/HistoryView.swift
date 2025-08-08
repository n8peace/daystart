import SwiftUI

struct HistoryView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var userPreferences: UserPreferences
    let onReplay: (DayStartData) -> Void
    
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
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
            ForEach(userPreferences.history) { dayStart in
                HistoryRow(dayStart: dayStart)
            }
        }
    }
}

struct HistoryRow: View {
    let dayStart: DayStartData
    @State private var isExpanded = false
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            
            if isExpanded {
                transcriptView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            actionButtons
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
            
            Text(formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(BananaTheme.ColorToken.card)
                .cornerRadius(8)
        }
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
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: {
                    if audioPlayer.currentTrackId != dayStart.id {
                        audioPlayer.loadAudio(for: dayStart)
                    }
                    audioPlayer.togglePlayPause()
                }) {
                    Label(audioPlayer.isPlaying && audioPlayer.currentTrackId == dayStart.id ? "Pause" : "Play",
                          systemImage: audioPlayer.isPlaying && audioPlayer.currentTrackId == dayStart.id ? "pause.circle.fill" : "play.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(BananaTheme.ColorToken.accent)
                }
                .buttonStyle(.bordered)

                Button(action: { isExpanded.toggle() }) {
                    Label(
                        isExpanded ? "Hide Transcript" : "Show Transcript",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
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