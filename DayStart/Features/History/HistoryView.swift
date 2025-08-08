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
                .font(.title2)
                .fontWeight(.semibold)
            
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
                HistoryRow(dayStart: dayStart, onReplay: {
                    presentationMode.wrappedValue.dismiss()
                    onReplay(dayStart)
                })
            }
        }
    }
}

struct HistoryRow: View {
    let dayStart: DayStartData
    let onReplay: () -> Void
    @State private var isExpanded = false
    
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
                    .font(.headline)
                
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
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.caption)
                .fontWeight(.semibold)
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
        HStack(spacing: 12) {
            Button(action: onReplay) {
                Label("Replay", systemImage: "play.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.blue)
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
    }
    
    private var formattedDuration: String {
        let minutes = Int(dayStart.duration) / 60
        let seconds = Int(dayStart.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}