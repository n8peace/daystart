import Foundation
import UIKit

class SupabaseClient {
    static let shared = SupabaseClient()
    
    private let logger = DebugLogger.shared
    private let baseURL: URL
    private let anonKey: String
    
    private init() {
        // Load configuration from Info.plist
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "SupabaseBaseURL") as? String,
              let baseURL = URL(string: baseURLString),
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String else {
            fatalError("SupabaseClient configuration missing from Info.plist. Add SupabaseBaseURL and SupabaseAnonKey keys.")
        }
        
        self.baseURL = baseURL
        self.anonKey = anonKey
        
        DebugLogger.shared.log("SupabaseClient configured with base URL: \(baseURL.absoluteString)", level: .info)
    }
    
    // MARK: - Audio Status API
    
    func getAudioStatus(for date: Date) async throws -> AudioStatusResponse {
        let dateString = localDateString(from: date) // Canonical local calendar day (YYYY-MM-DD)
        let url = baseURL.appendingPathComponent("get_audio_status")
            .appendingQueryItem(name: "date", value: String(dateString))
        
        logger.log("🔍 Supabase API: GET audio_status for date: \(dateString)", level: .info)
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        
        let request = createRequest(for: url, method: "GET")
        logger.logNetworkRequest(request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("❌ Supabase API: Invalid response type", level: .error)
                throw SupabaseError.invalidResponse
            }
            
            logger.log("📥 Supabase API: Response status: \(httpResponse.statusCode)", level: .info)
            logger.logNetworkResponse(httpResponse, data: data)
            
            // Log response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                logger.log("📄 Response body: \(responseString)", level: .debug)
            }
            
            // Always expect 200 per GPT-5 review - check success field instead
            guard httpResponse.statusCode == 200 else {
                logger.logError(NSError(domain: "SupabaseError", code: httpResponse.statusCode), 
                               context: "HTTP error in getAudioStatus: \(httpResponse.statusCode)")
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
            
            let audioResponse = try JSONDecoder().decode(AudioStatusAPIResponse.self, from: data)
            
            logger.log("✅ Supabase API: Audio status = \(audioResponse.status), success = \(audioResponse.success)", level: .info)
            
            // Check success field per GPT-5 API contract
            if !audioResponse.success {
                let error = SupabaseError.apiError(audioResponse.error_code, audioResponse.error_message ?? "Unknown error")
                logger.logError(error, context: "API error in getAudioStatus: \(audioResponse.error_code ?? "unknown")")
                throw error
            }
            
            if let audioUrl = audioResponse.audio_url {
                logger.log("🎵 Audio URL received: \(audioUrl)", level: .info)
            }
            
            return AudioStatusResponse(
                success: audioResponse.success,
                status: audioResponse.status,
                jobId: audioResponse.job_id,
                audioUrl: audioResponse.audio_url.flatMap(URL.init),
                estimatedReadyTime: audioResponse.estimated_ready_time.flatMap { ISO8601DateFormatter().date(from: $0) },
                duration: audioResponse.duration,
                transcript: audioResponse.transcript,
                errorCode: audioResponse.error_code,
                errorMessage: audioResponse.error_message,
                requestId: audioResponse.request_id
            )
            
        } catch {
            logger.logError(error, context: "Failed to get audio status for \(date)")
            throw error
        }
    }
    
    // MARK: - Job Creation API
    
    func createJob(
        for date: Date,
        with preferences: UserSettings,
        schedule: DayStartSchedule,
        locationData: LocationData? = nil,
        weatherData: WeatherData? = nil,
        calendarEvents: [String]? = nil
    ) async throws -> JobResponse {
        let url = baseURL.appendingPathComponent("create_job")
        
        logger.log("📤 Supabase API: POST create_job", level: .info)
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        
        var request = createRequest(for: url, method: "POST")
        
        let jobRequest = CreateJobRequest(
            local_date: localDateString(from: date),
            scheduled_at: ISO8601DateFormatter().string(from: date),
            preferred_name: preferences.preferredName,
            include_weather: preferences.includeWeather,
            include_news: preferences.includeNews,
            include_sports: preferences.includeSports,
            include_stocks: preferences.includeStocks,
            stock_symbols: preferences.stockSymbols,
            include_calendar: preferences.includeCalendar,
            include_quotes: preferences.includeQuotes,
            quote_preference: preferences.quotePreference.rawValue,
            voice_option: "voice\(preferences.selectedVoice.rawValue + 1)",
            daystart_length: preferences.dayStartLength * 60, // Convert minutes to seconds
            timezone: TimeZone.current.identifier,
            location_data: locationData,
            weather_data: weatherData,
            calendar_events: calendarEvents,
            force_update: nil
        )
        
        let jsonData = try JSONEncoder().encode(jobRequest)
        request.httpBody = jsonData
        
        // Log request payload
        if let requestString = String(data: jsonData, encoding: .utf8) {
            logger.log("📝 create_job payload: \(requestString)", level: .debug)
        }
        
        do {
            logger.logNetworkRequest(request)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("❌ Supabase API: Invalid response type", level: .error)
                throw SupabaseError.invalidResponse
            }
            
            logger.log("📥 Supabase API: Response status: \(httpResponse.statusCode)", level: .info)
            
            // Log response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                logger.log("📄 create_job response: \(responseString)", level: .debug)
            }
            
            // Always expect 200 per GPT-5 review - check success field instead
            guard httpResponse.statusCode == 200 else {
                logger.logError(NSError(domain: "SupabaseError", code: httpResponse.statusCode),
                               context: "HTTP error in createJob: \(httpResponse.statusCode)")
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
            
            let jobResponse = try JSONDecoder().decode(CreateJobAPIResponse.self, from: data)
            
            logger.log("✅ Supabase API: Job created = \(jobResponse.job_id ?? "nil"), status = \(jobResponse.status ?? "nil")", level: .info)
            
            // Check success field per GPT-5 API contract
            if !jobResponse.success {
                let error = SupabaseError.apiError(jobResponse.error_code, jobResponse.error_message ?? "Unknown error")
                logger.logError(error, context: "API error in createJob: \(jobResponse.error_code ?? "unknown")")
                throw error
            }
            
            return JobResponse(
                success: jobResponse.success,
                jobId: jobResponse.job_id,
                status: jobResponse.status,
                estimatedReadyTime: jobResponse.estimated_ready_time.flatMap { ISO8601DateFormatter().date(from: $0) },
                errorCode: jobResponse.error_code,
                errorMessage: jobResponse.error_message,
                requestId: jobResponse.request_id
            )
            
        } catch {
            logger.logError(error, context: "Failed to create job for \(date)")
            throw error
        }
    }

    // MARK: - Bulk Update Jobs API
    func updateJobs(
        dates: [Date],
        with settings: UserSettings,
        forceRequeue: Bool = false
    ) async throws -> UpdateJobsResult {
        let url = baseURL.appendingPathComponent("update_jobs")

        logger.log("📤 Supabase API: POST update_jobs", level: .info)
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)

        var request = createRequest(for: url, method: "POST")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let dateStrings = dates.map { formatter.string(from: $0) }

        let payload = UpdateJobsRequest(
            dates: dateStrings,
            date_range: nil,
            statuses: nil, // use server default (queued + failed)
            settings: UpdateSettings(
                preferred_name: settings.preferredName,
                include_weather: settings.includeWeather,
                include_news: settings.includeNews,
                include_sports: settings.includeSports,
                include_stocks: settings.includeStocks,
                stock_symbols: settings.stockSymbols,
                include_calendar: settings.includeCalendar,
                include_quotes: settings.includeQuotes,
                quote_preference: settings.quotePreference.rawValue,
                voice_option: "voice\(settings.selectedVoice.rawValue + 1)",
                daystart_length: settings.dayStartLength * 60, // Convert minutes to seconds
                timezone: TimeZone.current.identifier
            ),
            force_requeue: forceRequeue
        )

        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData

        if let requestString = String(data: jsonData, encoding: .utf8) {
            logger.log("📝 update_jobs payload: \(requestString)", level: .debug)
        }

        logger.logNetworkRequest(request)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("❌ Supabase API: Invalid response type (update_jobs)", level: .error)
            throw SupabaseError.invalidResponse
        }

        logger.log("📥 Supabase API: Response status (update_jobs): \(httpResponse.statusCode)", level: .info)
        logger.logNetworkResponse(httpResponse, data: data)

        guard httpResponse.statusCode == 200 else {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        if let responseString = String(data: data, encoding: .utf8) {
            logger.log("📄 update_jobs response: \(responseString)", level: .debug)
        }

        let resp = try JSONDecoder().decode(UpdateJobsAPIResponse.self, from: data)
        if !resp.success {
            throw SupabaseError.apiError(resp.error_code, resp.error_message ?? "Unknown error")
        }
        return UpdateJobsResult(success: true, updatedCount: resp.updated_count ?? 0)
    }
    
    // MARK: - Snapshot Update API
    
    func updateJobSnapshots(
        jobIds: [String],
        locationData: LocationData?,
        weatherData: WeatherData?,
        calendarEvents: [String]?
    ) async throws -> Bool {
        let url = baseURL.appendingPathComponent("update_job_snapshots")
        
        logger.log("📤 Supabase API: POST update_job_snapshots", level: .info)
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        
        var request = createRequest(for: url, method: "POST")
        
        let requestBody = UpdateJobSnapshotsRequest(
            job_ids: jobIds,
            location_data: locationData,
            weather_data: weatherData,
            calendar_events: calendarEvents
        )
        
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(requestBody)
        } catch {
            logger.logError(error, context: "Failed to encode update job snapshots request")
            throw error
        }
        
        request.httpBody = jsonData
        
        if let requestString = String(data: jsonData, encoding: .utf8) {
            logger.log("📝 update_job_snapshots payload: \(requestString)", level: .debug)
        }
        
        logger.logNetworkRequest(request)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("❌ Supabase API: Invalid response type (update_job_snapshots)", level: .error)
            throw SupabaseError.invalidResponse
        }
        
        logger.log("📥 Supabase API: Response status (update_job_snapshots): \(httpResponse.statusCode)", level: .info)
        logger.logNetworkResponse(httpResponse, data: data)
        
        guard httpResponse.statusCode == 200 else {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            logger.log("📄 update_job_snapshots response: \(responseString)", level: .debug)
        }
        
        let resp = try JSONDecoder().decode(UpdateJobSnapshotsResponse.self, from: data)
        return resp.success
    }
    
    func getJobsInDateRange(startDate: String, endDate: String) async throws -> [JobSummary] {
        let url = baseURL.appendingPathComponent("get_jobs")
            .appendingQueryItem(name: "start_date", value: startDate)
            .appendingQueryItem(name: "end_date", value: endDate)
        
        logger.log("📤 Supabase API: GET get_jobs", level: .info)
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        
        var request = createRequest(for: url, method: "GET")
        
        logger.logNetworkRequest(request)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("❌ Supabase API: Invalid response type (get_jobs)", level: .error)
            throw SupabaseError.invalidResponse
        }
        
        logger.log("📥 Supabase API: Response status (get_jobs): \(httpResponse.statusCode)", level: .info)
        logger.logNetworkResponse(httpResponse, data: data)
        
        guard httpResponse.statusCode == 200 else {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            logger.log("📄 get_jobs response: \(responseString)", level: .debug)
        }
        
        let resp = try JSONDecoder().decode(GetJobsResponse.self, from: data)
        return resp.success ? resp.jobs ?? [] : []
    }
    
    // MARK: - Authentication (Future)
    
    fileprivate func createAuthenticatedJob(_ request: CreateJobRequest) async throws -> JobResponse {
        // TODO: Implement when authentication is added
        // This would include the auth token in headers
        throw SupabaseError.notImplemented
    }
    
    fileprivate func createAnonymousJob(_ request: CreateJobRequest) async throws -> JobResponse {
        // TODO: Implement anonymous job creation
        // This would not save to user history
        throw SupabaseError.notImplemented
    }
    
    // MARK: - Job Management
    
    func markJobAsFailed(jobId: String, errorCode: String) async throws {
        let url = baseURL.appendingPathComponent("jobs")
        
        logger.log("📤 Supabase API: PATCH jobs - marking job as failed", level: .info)
        
        var request = createRequest(for: url, method: "PATCH")
        
        let updateData = [
            "job_id": "eq.\(jobId)",
            "status": "failed",
            "error_code": errorCode,
            "error_message": "Job failed due to timeout or processing error",
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Create query parameters for the update
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "job_id", value: "eq.\(jobId)")]
        request.url = urlComponents.url
        
        let jsonData = try JSONEncoder().encode([
            "status": "failed",
            "error_code": errorCode,
            "error_message": "Job failed due to timeout or processing error",
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ])
        request.httpBody = jsonData
        
        do {
            logger.logNetworkRequest(request)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
                logger.logError(NSError(domain: "SupabaseError", code: httpResponse.statusCode),
                               context: "HTTP error in markJobAsFailed: \(httpResponse.statusCode)")
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
            
            logger.log("✅ Job \(jobId) marked as failed with error: \(errorCode)", level: .info)
            
        } catch {
            logger.logError(error, context: "Failed to mark job as failed: \(jobId)")
            throw error
        }
    }
    
    // MARK: - Edge Function Invocation
    
    func invokeProcessJob(jobId: String) async throws {
        let url = URL(string: "\(baseURL.absoluteString.replacingOccurrences(of: "/rest/v1", with: ""))/functions/v1/process_jobs")!
        
        logger.log("🚀 Invoking process_jobs for specific job: \(jobId)", level: .info)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["jobId": jobId]
        request.httpBody = try JSONEncoder().encode(payload)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseError.invalidResponse
            }
            
            // Edge functions return 200 for success
            guard httpResponse.statusCode == 200 else {
                logger.log("❌ Edge function returned status: \(httpResponse.statusCode)", level: .error)
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
            
            logger.log("✅ Successfully invoked process_jobs for job: \(jobId)", level: .info)
        } catch {
            logger.logError(error, context: "Failed to invoke process_jobs for job: \(jobId)")
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private func createRequest(for url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DayStart-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        // Add device ID as client info for tracking
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
            request.setValue(deviceId, forHTTPHeaderField: "x-client-info")
            logger.log("📎 x-client-info set: \(deviceId)", level: .debug)
        }
        
        logger.log("🔑 Auth headers set, timeout: 30s", level: .debug)
        
        return request
    }

    private func localDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

// MARK: - API Request/Response Models

fileprivate struct CreateJobRequest: Codable {
    let local_date: String
    let scheduled_at: String
    let preferred_name: String
    let include_weather: Bool
    let include_news: Bool
    let include_sports: Bool
    let include_stocks: Bool
    let stock_symbols: [String]
    let include_calendar: Bool
    let include_quotes: Bool
    let quote_preference: String
    let voice_option: String
    let daystart_length: Int
    let timezone: String
    let location_data: LocationData?
    let weather_data: WeatherData?
    let calendar_events: [String]?
    let force_update: Bool? // optional, when set true allows re-queueing existing job
}

// MARK: - Update Jobs API models

private struct UpdateJobsRequest: Codable {
    let dates: [String]?
    let date_range: DateRangeFilter?
    let statuses: [String]?
    let settings: UpdateSettings?
    let force_requeue: Bool?
}

private struct DateRangeFilter: Codable {
    let start_local_date: String
    let end_local_date: String
}

private struct UpdateSettings: Codable {
    let preferred_name: String?
    let include_weather: Bool?
    let include_news: Bool?
    let include_sports: Bool?
    let include_stocks: Bool?
    let stock_symbols: [String]?
    let include_calendar: Bool?
    let include_quotes: Bool?
    let quote_preference: String?
    let voice_option: String?
    let daystart_length: Int?
    let timezone: String?
}

private struct UpdateJobsAPIResponse: Codable {
    let success: Bool
    let updated_count: Int?
    let error_code: String?
    let error_message: String?
    let request_id: String?
}

struct UpdateJobsResult {
    let success: Bool
    let updatedCount: Int
}

// MARK: - Snapshot Update API Models

private struct UpdateJobSnapshotsRequest: Codable {
    let job_ids: [String]
    let location_data: LocationData?
    let weather_data: WeatherData?
    let calendar_events: [String]?
}

private struct UpdateJobSnapshotsResponse: Codable {
    let success: Bool
    let updated_count: Int?
    let error_code: String?
    let error_message: String?
    let request_id: String?
}

private struct GetJobsResponse: Codable {
    let success: Bool
    let jobs: [JobSummary]?
    let error_code: String?
    let error_message: String?
    let request_id: String?
}

struct JobSummary: Codable {
    let jobId: String
    let localDate: String
    let scheduledAt: String?
    let status: String
    
    private enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case localDate = "local_date"
        case scheduledAt = "scheduled_at"
        case status
    }
}

private struct CreateJobAPIResponse: Codable {
    let success: Bool
    let job_id: String?
    let status: String? // 'queued'|'processing'|'ready'|'failed'
    let estimated_ready_time: String?
    let error_code: String?
    let error_message: String?
    let request_id: String?
}

private struct AudioStatusAPIResponse: Codable {
    let success: Bool
    let status: String // 'ready'|'processing'|'not_found'|'failed'
    let job_id: String?
    let audio_url: String?
    let estimated_ready_time: String?
    let duration: Int?
    let transcript: String?
    let error_code: String?
    let error_message: String?
    let request_id: String?
}

// MARK: - Public Response Models

struct JobResponse {
    let success: Bool
    let jobId: String?
    let status: String? // 'queued'|'processing'|'ready'|'failed'
    let estimatedReadyTime: Date?
    let errorCode: String?
    let errorMessage: String?
    let requestId: String?
}

struct AudioStatusResponse {
    let success: Bool
    let status: String // 'ready'|'processing'|'not_found'|'failed'
    let jobId: String?
    let audioUrl: URL?
    let estimatedReadyTime: Date?
    let duration: Int?
    let transcript: String?
    let errorCode: String?
    let errorMessage: String?
    let requestId: String?
}

// MARK: - URL Extension for Query Items

private extension URL {
    func appendingQueryItem(name: String, value: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url!
    }
}

// MARK: - Supabase Errors

enum SupabaseError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String?, String) // error_code, error_message
    case urlExpired
    case notImplemented
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let code, let message):
            return "API error (\(code ?? "unknown")): \(message)"
        case .urlExpired:
            return "Signed URL has expired"
        case .notImplemented:
            return "Feature not yet implemented"
        case .invalidConfiguration:
            return "Invalid Supabase configuration"
        }
    }
}

// MARK: - Configuration Extension

extension SupabaseClient {
    func configure(baseURL: String, anonKey: String) {
        // TODO: Allow runtime configuration
        // For now, these are hardcoded in init()
    }
    
    var isConfigured: Bool {
        return !anonKey.contains("your-anon-key-here") && 
               !baseURL.absoluteString.contains("your-project")
    }
}