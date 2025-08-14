import SwiftUI

struct SplashScreenView: View {
    @State private var opacity = 1.0
    @State private var minimumTimeElapsed = false
    @Binding var isAppReady: Bool
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Full screen background
            Color.black
                .ignoresSafeArea()
            
            // Centered image that fills the screen (edges cut off)
            Image("SplashIcon")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .opacity(opacity)
            
            // Loading indicator at bottom
            VStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
                    .opacity(minimumTimeElapsed && !isAppReady ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: minimumTimeElapsed)
                    .padding(.bottom, 100)
            }
        }
        .onAppear {
            // Minimum display time of 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                minimumTimeElapsed = true
                checkIfReadyToDismiss()
            }
        }
        .onChange(of: isAppReady) { _ in
            checkIfReadyToDismiss()
        }
    }
    
    private func checkIfReadyToDismiss() {
        // Dismiss only when both minimum time elapsed AND app is ready
        if minimumTimeElapsed && isAppReady {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
            }
            
            // Complete after fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
}