import SwiftUI

struct VoicePickerView: View {
    @Binding var selectedVoice: VoiceOption
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var originalSelection: VoiceOption
    
    private let logger = DebugLogger.shared
    
    private var hasUnsavedChanges: Bool {
        return selectedVoice != originalSelection
    }
    
    init(selectedVoice: Binding<VoiceOption>) {
        self._selectedVoice = selectedVoice
        self._originalSelection = State(initialValue: selectedVoice.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(VoiceOption.allCases, id: \.self) { voice in
                        Button(action: { onSelect(voice) }) {
                            HStack(spacing: BananaTheme.Spacing.md) {
                                Image(systemName: "person.wave.2")
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(voiceDescription(for: voice))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedVoice == voice {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(BananaTheme.ColorToken.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                logger.log("🎤 Voice picker appeared", level: .info)
                logger.logUserAction("Voice picker opened", details: [
                    "currentVoice": selectedVoice.name,
                    "originalVoice": originalSelection.name
                ])
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        logger.logUserAction("Voice picker cancelled", details: [
                            "originalVoice": originalSelection.name,
                            "wasChanged": selectedVoice != originalSelection
                        ])
                        AudioPlayerManager.shared.stopVoicePreview()
                        selectedVoice = originalSelection
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(BananaTheme.ColorToken.text)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        logger.logUserAction("Voice picker confirmed", details: [
                            "selectedVoice": selectedVoice.name,
                            "originalVoice": originalSelection.name,
                            "wasChanged": selectedVoice != originalSelection
                        ])
                        AudioPlayerManager.shared.stopVoicePreview()
                        dismiss()
                    }) {
                        Image(systemName: "checkmark")
                            .foregroundColor(hasUnsavedChanges ? BananaTheme.ColorToken.accent : BananaTheme.ColorToken.text)
                    }
                    .tint(BananaTheme.ColorToken.primary)
                }
            }
            .onDisappear {
                AudioPlayerManager.shared.stopVoicePreview()
            }
        }
    }
    
    private func onSelect(_ voice: VoiceOption) {
        logger.logUserAction("Voice tapped for preview", details: [
            "voice": voice.name,
            "wasAlreadySelected": selectedVoice == voice
        ])
        if selectedVoice != voice { selectedVoice = voice }
        AudioPlayerManager.shared.previewVoice(voice)
    }
    
    private func voiceDescription(for voice: VoiceOption) -> String {
        switch voice {
        case .voice1:
            return "Warm and smooth, perfect for gentle wake-ups"
        case .voice2:
            return "Clear and authoritative, great for headlines"
        case .voice3:
            return "Calm and composed, thoughtful delivery style"
        }
    }
}


