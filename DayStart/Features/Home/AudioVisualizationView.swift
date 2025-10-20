import SwiftUI

// Safe array access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct AudioVisualizationView: View {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                let baseHeight = 10.0 + Double(index % 3) * 10.0 + (index % 2 == 0 ? 5.0 : 0.0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(BananaTheme.ColorToken.primary.opacity(0.7))
                    .frame(width: 4, height: audioPlayer.isPlaying ? 
                           max(baseHeight, Double(audioPlayer.audioLevels[safe: index] ?? 0) * 40) : 
                           baseHeight * 0.3)
                    .scaleEffect(y: audioPlayer.isPlaying ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)
                    .animation(.easeInOut(duration: 0.1), value: audioPlayer.audioLevels[safe: index] ?? 0)
            }
        }
        .frame(height: 50)
    }
}

#Preview {
    AudioVisualizationView()
        .padding()
        .background(BananaTheme.ColorToken.background)
}