import Foundation
import Combine
import Supabase
import AuthenticationServices

enum AuthState {
    case unknown
    case authenticated(userId: String)
    case unauthenticated
}

enum AuthError: LocalizedError {
    case signInFailed(String)
    case signOutFailed(String)
    case sessionExpired
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var currentUserId: String?
    @Published private(set) var isLoading = false
    
    private let logger = DebugLogger.shared
    private let supabaseAuth = SupabaseAuthClient.shared
    
    private init() {
        setupAuthStateListener()
        Task {
            await checkAuthStatus()
        }
    }
    
    // MARK: - Public Methods
    
    func checkAuthStatus() async {
        logger.log("🔐 Checking auth status", level: .info)
        
        if let session = await supabaseAuth.currentSession {
            // User is authenticated
            let user = session.user
            await MainActor.run {
                self.authState = .authenticated(userId: user.id.uuidString)
                self.currentUserId = user.id.uuidString
            }
            logger.log("✅ User authenticated: \(user.id.uuidString.prefix(8))...", level: .info)
        } else {
            // User is not authenticated
            await MainActor.run {
                self.authState = .unauthenticated
                self.currentUserId = nil
            }
            logger.log("🚪 User not authenticated", level: .info)
        }
    }
    
    func signInWithApple() async throws {
        logger.log("🍎 Starting Sign in with Apple", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            // Get Apple ID credential
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            
            // This will be handled by the AuthenticationView's SignInWithAppleButton
            // The actual sign in flow continues in handleAppleSignIn
            throw AuthError.signInFailed("Use SignInWithAppleButton in UI")
        } catch {
            logger.logError(error, context: "Apple Sign In failed")
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }
    
    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async throws {
        logger.log("🍎 Processing Apple credential", level: .info)
        
        guard let identityToken = credential.identityToken,
              let idToken = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.signInFailed("Invalid Apple ID token")
        }
        
        do {
            // Sign in with Apple using Supabase
            let session = try await supabaseAuth.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken
                )
            )
            
            // Update auth state
            await MainActor.run {
                self.authState = .authenticated(userId: session.user.id.uuidString)
                self.currentUserId = session.user.id.uuidString
            }
            
            logger.log("✅ Apple Sign In successful: \(session.user.id.uuidString.prefix(8))...", level: .info)
        } catch {
            logger.logError(error, context: "Apple Sign In with Supabase")
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }
    
    func signInWithGoogle() async throws {
        logger.log("🔍 Starting Sign in with Google", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Google Sign In requires additional setup with GoogleSignIn SDK
        // For now, we'll throw an error indicating it's not yet implemented
        throw AuthError.signInFailed("Google Sign In requires additional SDK setup")
    }
    
    func signInWithEmail(email: String) async throws {
        logger.log("📧 Starting email sign in for: \(email)", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            // Send magic link with Supabase
            try await supabaseAuth.auth.signInWithOTP(
                email: email
            )
            
            logger.log("✅ Magic link sent to: \(email)", level: .info)
            
            // Note: User will need to click the magic link to complete sign in
            // The auth state change will be handled by the auth state listener
        } catch {
            logger.logError(error, context: "Email sign in with Supabase")
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }
    
    func signOut() async throws {
        logger.log("🚪 Signing out", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            // Sign out with Supabase
            try await supabaseAuth.auth.signOut()
            
            // Clear local data
            await MainActor.run {
                clearLocalData()
                authState = .unauthenticated
                currentUserId = nil
            }
            
            logger.log("✅ Sign out successful", level: .info)
        } catch {
            logger.logError(error, context: "Sign out with Supabase")
            throw AuthError.signOutFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Methods
    
    private func clearLocalData() {
        logger.log("🧹 Clearing local user data", level: .info)
        
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "schedule")
        UserDefaults.standard.removeObject(forKey: "settings")
        UserDefaults.standard.removeObject(forKey: "history")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        
        // Clear keychain if needed
        // KeychainManager.shared.clearAll()
        
        // Clear any cached audio
        // TODO: Implement AudioCache.clearCache() if needed
        
        logger.log("✅ Local data cleared", level: .info)
    }
    
    // MARK: - Session Management
    
    func refreshSession() async throws {
        logger.log("🔄 Refreshing session", level: .info)
        
        do {
            let session = try await supabaseAuth.refreshSession()
            
            // Update auth state with refreshed session
            await MainActor.run {
                self.authState = .authenticated(userId: session.user.id.uuidString)
                self.currentUserId = session.user.id.uuidString
            }
            
            logger.log("✅ Session refreshed successfully", level: .info)
        } catch {
            logger.logError(error, context: "Refreshing session")
            
            // If refresh fails, user needs to sign in again
            await MainActor.run {
                self.authState = .unauthenticated
                self.currentUserId = nil
            }
            
            throw AuthError.sessionExpired
        }
    }
    
    var isAuthenticated: Bool {
        if case .authenticated = authState {
            return true
        }
        return false
    }
    
    // MARK: - Private Auth State Management
    
    private func setupAuthStateListener() {
        Task {
            await supabaseAuth.onAuthStateChange { [weak self] event, session in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    self.logger.log("🔐 Auth event received: \(event)", level: .info)
                    
                    switch event {
                    case .signedIn:
                        if let session = session {
                            self.authState = .authenticated(userId: session.user.id.uuidString)
                            self.currentUserId = session.user.id.uuidString
                            self.logger.log("✅ User signed in: \(session.user.id.uuidString.prefix(8))...", level: .info)
                        }
                        
                    case .signedOut:
                        self.authState = .unauthenticated
                        self.currentUserId = nil
                        self.clearLocalData()
                        self.logger.log("🚪 User signed out", level: .info)
                        
                    case .tokenRefreshed:
                        if let session = session {
                            self.authState = .authenticated(userId: session.user.id.uuidString)
                            self.currentUserId = session.user.id.uuidString
                            self.logger.log("🔄 Token refreshed for: \(session.user.id.uuidString.prefix(8))...", level: .info)
                        }
                        
                    default:
                        self.logger.log("ℹ️ Auth event: \(event)", level: .info)
                    }
                }
            }
        }
    }
}