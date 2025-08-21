import Foundation
import Supabase
import Auth

/// Wrapper around Supabase client with authentication support
class SupabaseAuthClient {
    static let shared = SupabaseAuthClient()
    
    private let logger = DebugLogger.shared
    private let client: Supabase.SupabaseClient
    
    private init() {
        guard let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseBaseURL") as? String,
              let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String else {
            fatalError("Missing Supabase configuration")
        }
        
        // Initialize Supabase client
        self.client = Supabase.SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseKey
        )
        
        logger.log("✅ SupabaseAuthClient initialized with URL: \(supabaseURL)", level: .info)
    }
    
    // MARK: - Auth Properties
    
    /// Access to Supabase auth client
    var auth: AuthClient {
        return client.auth
    }
    
    /// Get current session if available
    var currentSession: Session? {
        get async {
            do {
                return try await client.auth.session
            } catch {
                logger.logError(error, context: "Getting current session")
                return nil
            }
        }
    }
    
    /// Get current user if authenticated
    var currentUser: User? {
        get async {
            return await currentSession?.user
        }
    }
    
    // MARK: - Updated Request Methods
    
    func createAuthenticatedRequest(for url: URL, method: String) async -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DayStart-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        // Add JWT token from current session if available
        if let session = await currentSession {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            logger.log("🔑 Added JWT token to request", level: .debug)
        } else {
            // Use anon key for unauthenticated requests
            if let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String {
                request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
                logger.log("🔑 Using anon key for unauthenticated request", level: .debug)
            }
        }
        
        return request
    }
    
    // MARK: - Session Management
    
    /// Listen for auth state changes
    func onAuthStateChange(_ callback: @escaping (AuthChangeEvent, Session?) -> Void) async {
        await client.auth.onAuthStateChange { event, session in
            self.logger.log("🔐 Auth state changed: \(event)", level: .info)
            callback(event, session)
        }
    }
    
    /// Refresh current session
    func refreshSession() async throws -> Session {
        do {
            let session = try await client.auth.refreshSession()
            logger.log("✅ Session refreshed successfully", level: .info)
            return session
        } catch {
            logger.logError(error, context: "Refreshing session")
            throw error
        }
    }
}