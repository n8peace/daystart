import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var currentPage = 0
    @State private var animationTrigger = false
    @State private var textOpacity: Double = 0.0
    @State private var heroScale: CGFloat = 0.9
    @State private var showingEmailInput = false
    @State private var emailAddress = ""
    @State private var showingEmailSentConfirmation = false
    
    private let logger = DebugLogger.shared
    
    // Optional completion handler for skip functionality
    var onSkip: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Background
            BananaTheme.ColorToken.background
                .ignoresSafeArea()
            
            // Gradient overlay
            DayStartGradientBackground()
                .opacity(0.15)
            
            if authManager.isLoading {
                loadingView
            } else {
                authContent
            }
        }
        .onAppear {
            logger.log("🔐 Authentication view appeared", level: .info)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startPageAnimation()
            }
        }
    }
    
    private var authContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                // Hero Section
                VStack(spacing: geometry.size.height * 0.05) {
                    // Animated logo/icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BananaTheme.ColorToken.primary.opacity(0.3), BananaTheme.ColorToken.accent.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: min(140, geometry.size.width * 0.3))
                            .scaleEffect(heroScale)
                        
                        Text("🌅")
                            .font(.system(size: min(70, geometry.size.width * 0.14)))
                            .scaleEffect(animationTrigger ? 1.1 : 0.9)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animationTrigger)
                    }
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Secure Your Data")
                            .font(.system(size: min(32, geometry.size.width * 0.08), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Backup & sync across all your devices")
                            .font(.system(size: min(18, geometry.size.width * 0.045), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // Authentication Options
                VStack(spacing: 16) {
                    // Sign in with Apple - Primary
                    SignInWithAppleButton { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: max(56, geometry.size.height * 0.07))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .scaleEffect(animationTrigger ? 1.02 : 1.0)
                    
                    // Sign in with Google - Secondary
                    Button(action: {
                        Task {
                            await signInWithGoogle()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: min(20, geometry.size.width * 0.05)))
                            
                            Text("Sign in with Google")
                                .font(.system(size: min(18, geometry.size.width * 0.045), weight: .semibold))
                        }
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(BananaTheme.ColorToken.card)
                                .stroke(BananaTheme.ColorToken.border, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(BananaTheme.ColorToken.border)
                            .frame(height: 1)
                        
                        Text("or")
                            .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        
                        Rectangle()
                            .fill(BananaTheme.ColorToken.border)
                            .frame(height: 1)
                    }
                    .padding(.vertical, 8)
                    
                    // Email sign in - Tertiary
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingEmailInput.toggle()
                        }
                        impactFeedback()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .font(.system(size: min(20, geometry.size.width * 0.05)))
                            
                            Text("Sign in with Email")
                                .font(.system(size: min(18, geometry.size.width * 0.045), weight: .medium))
                        }
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    }
                    
                    // Email input field (animated)
                    if showingEmailInput {
                        VStack(spacing: 12) {
                            TextField("Enter your email", text: $emailAddress)
                                .font(.system(size: min(16, geometry.size.width * 0.04)))
                                .textFieldStyle(.plain)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(BananaTheme.ColorToken.card)
                                        .stroke(BananaTheme.ColorToken.border, lineWidth: 1)
                                )
                                .submitLabel(.send)
                                .onSubmit {
                                    if isValidEmail(emailAddress) {
                                        Task {
                                            await signInWithEmail()
                                        }
                                    }
                                }
                            
                            Button(action: {
                                Task {
                                    await signInWithEmail()
                                }
                            }) {
                                Text("Send Magic Link")
                                    .font(.system(size: min(16, geometry.size.width * 0.04), weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            colors: isValidEmail(emailAddress) ? 
                                                [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent] : 
                                                [Color.gray, Color.gray],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                            .disabled(!isValidEmail(emailAddress))
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.08)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Benefits reminder
                VStack(spacing: 12) {
                    Text("Premium Benefits")
                        .font(.system(size: min(16, geometry.size.width * 0.04), weight: .semibold))
                        .foregroundColor(BananaTheme.ColorToken.text)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        BenefitRow(icon: "☁️", text: "Backup your premium voices", geometry: geometry)
                        BenefitRow(icon: "📱", text: "Sync across iPhone, iPad, Mac", geometry: geometry)
                        BenefitRow(icon: "🔒", text: "Never lose your settings again", geometry: geometry)
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.12)
                .opacity(textOpacity * 0.8)
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Skip option
                if let onSkip = onSkip {
                    Button(action: {
                        logger.logUserAction("Authentication skipped")
                        impactFeedback()
                        onSkip()
                    }) {
                        Text("I'll add an account later")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .underline()
                    }
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .opacity(textOpacity * 0.7)
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Legal text
                Text("By signing in, you agree to our Terms of Service and Privacy Policy")
                    .font(.system(size: min(12, geometry.size.width * 0.03)))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .padding(.bottom, max(24, geometry.size.height * 0.03))
                    .opacity(textOpacity * 0.6)
            }
        }
        .alert("Check Your Email", isPresented: $showingEmailSentConfirmation) {
            Button("OK") { }
        } message: {
            Text("We've sent a magic link to \(emailAddress). Click the link in the email to sign in.")
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: BananaTheme.ColorToken.primary))
                .scaleEffect(1.5)
            
            Text("Signing in...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
        }
    }
    
    // MARK: - Helper Methods
    
    private func startPageAnimation() {
        withAnimation(.easeOut(duration: 0.8)) {
            textOpacity = 1.0
            heroScale = 1.0
        }
        
        withAnimation(.easeInOut(duration: 1.0).delay(0.3)) {
            animationTrigger = true
        }
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPred.evaluate(with: email)
    }
    
    // MARK: - Authentication Handlers
    
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            logger.log("🍎 Apple Sign In authorization received", level: .info)
            
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    do {
                        try await authManager.handleAppleCredential(appleIDCredential)
                    } catch {
                        logger.logError(error, context: "Apple Sign In failed")
                        // Show error alert
                    }
                }
            }
            
        case .failure(let error):
            logger.logError(error, context: "Apple Sign In authorization failed")
            // Show error alert
        }
    }
    
    private func signInWithGoogle() async {
        do {
            try await authManager.signInWithGoogle()
        } catch {
            logger.logError(error, context: "Google Sign In failed")
            // Show error alert
        }
    }
    
    private func signInWithEmail() async {
        guard isValidEmail(emailAddress) else { return }
        
        do {
            try await authManager.signInWithEmail(email: emailAddress)
            await MainActor.run {
                showingEmailSentConfirmation = true
                showingEmailInput = false
            }
        } catch {
            logger.logError(error, context: "Email Sign In failed")
            // Show error alert
        }
    }
}

// MARK: - Supporting Views

struct BenefitRow: View {
    let icon: String
    let text: String
    let geometry: GeometryProxy
    
    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: min(16, geometry.size.width * 0.04)))
            
            Text(text)
                .font(.system(size: min(14, geometry.size.width * 0.035)))
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
            
            Spacer()
        }
    }
}