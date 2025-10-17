import SwiftUI

struct AudioVisualizationView: View {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @State private var animationTrigger = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                let baseHeight = 10.0 + Double(index % 3) * 10.0 + (index % 2 == 0 ? 5.0 : 0.0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(BananaTheme.ColorToken.primary.opacity(0.7))
                    .frame(width: 4, height: audioPlayer.isPlaying ? 
                           max(baseHeight, Double(audioPlayer.audioLevels[safe: index] ?? 0) * 40) : 
                           baseHeight * 0.3)
                    .scaleEffect(y: audioPlayer.isPlaying ? 
                                (animationTrigger ? 1.2 : 0.8) : 0.6)
                    .animation(
                        audioPlayer.isPlaying ? 
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.05) :
                            .easeInOut(duration: 1.0),
                        value: animationTrigger
                    )
                    .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)
            }
        }
        .frame(height: 50)
        .onAppear {
            startAnimation()
        }
        .onChange(of: audioPlayer.isPlaying) { _, isPlaying in
            if isPlaying {
                startAnimation()
            } else {
                animationTrigger = false
            }
        }
    }
    
    private func startAnimation() {
        guard audioPlayer.isPlaying else { return }
        
        withAnimation(.easeInOut(duration: 1.0).delay(0.2)) {
            animationTrigger.toggle()
        }
    }
}

// Safe array access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    AudioVisualizationView()
        .padding()
        .background(BananaTheme.ColorToken.background)
}