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
            
            // Centered image
            Image("SplashIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // PHASE 3: Reduced splash delay for faster launch (0.5s -> 0.1s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                minimumTimeElapsed = true
                withAnimation(.easeOut(duration: 0.1)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onComplete()
                }
            }
        }
        .onChange(of: isAppReady) { ready in
            // If app is ready before minimum time, dismiss immediately
            if ready && !minimumTimeElapsed {
                withAnimation(.easeOut(duration: 0.1)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onComplete()
                }
            }
        }
    }
    
    private func checkIfReadyToDismiss() {}
}