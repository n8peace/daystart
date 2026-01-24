import Foundation
import UIKit

class SupabaseClient {
    static let shared = SupabaseClient()
    
    private let logger = DebugLogger.shared
    private let baseURL: URL
    private let restURL: URL
    private let functionsURL: URL
    private let anonKey: String
    
    private init() {
        // Load configuration from Info.plist
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "SupabaseBaseURL") as? String,
              let baseURL = URL(string: baseURLString),
              let restURLString = Bundle.main.object(forInfoDictionaryKey: "SupabaseRestURL") as? String,
              let restURL = URL(string: restURLString),
              let functionsURLString = Bundle.main.object(forInfoDictionaryKey: "SupabaseFunctionsURL") as? String,
              let functionsURL = URL(string: functionsURLString),
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String else {
            fatalError("SupabaseClient configuration missing from Info.plist. Add SupabaseBaseURL, SupabaseRestURL, SupabaseFunctionsURL and SupabaseAnonKey keys.")
        }
        
        self.baseURL = baseURL
        self.restURL = restURL
        self.functionsURL = functionsURL
        self.anonKey = anonKey
        
        DebugLogger.shared.log("SupabaseClient configured:", level: .info)
        DebugLogger.shared.log("  Base URL: \(baseURL.absoluteString)", level: .info)
        DebugLogger.shared.log("  REST URL: \(restURL.absoluteString)", level: .info)
        DebugLogger.shared.log("  Functions URL: \(functionsURL.absoluteString)", level: .info)
    }
    
    // MARK: - Audio Status API
    
    func markDayStartCompleted(for date: Date) async throws -> Bool {
        let dateString = localDateString(from: date)
        let url = functionsURL.appendingPathComponent("get_audio_status")
            .appendingQueryItem(name: "date", value: dateString)
            .appendingQueryItem(name: "mark_completed", value: "true")
        
        logger.log("✅ Supabase API: Marking DayStart completed for date: \(dateString)", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif
        
        let request = await createRequest(for: url, method: "GET")
        #if DEBUG
        logger.logNetworkRequest(request)
        #endif
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("❌ Supabase API: Invalid response type", level: .error)
                throw SupabaseError.invalidResponse
            }
            
            logger.log("📥 Supabase API: Response status (mark_completed): \(httpResponse.statusCode)", level: .info)
            
            guard httpResponse.statusCode == 200 else {
                logger.log("❌ Supabase API: HTTP \(httpResponse.statusCode)", level: .error)
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
            
            // Parse response to check success
            if let responseData = try? JSONDecoder().decode(AudioStatusAPIResponse.self, from: data) {
                return responseData.success
            }
            
            return false
        } catch {
            logger.logError(error, context: "Failed to mark DayStart completed")
            throw error
        }
    }
    
    func getAudioStatus(for date: Date) async throws -> AudioStatusResponse {
        let dateString = localDateString(from: date) // Canonical local calendar day (YYYY-MM-DD)
        let url = functionsURL.appendingPathComponent("get_audio_status")
            .appendingQueryItem(name: "date", value: String(dateString))
        
        logger.log("🔍 Supabase API: GET audio_status for date: \(dateString)", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif
        
        let request = await createRequest(for: url, method: "GET")
        #if DEBUG
        logger.logNetworkRequest(request)
        #endif
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("❌ Supabase API: Invalid response type", level: .error)
                throw SupabaseError.invalidResponse
            }
            
            logger.log("📥 Supabase API: Response status: \(httpResponse.statusCode)", level: .info)
            #if DEBUG
        logger.logNetworkResponse(httpResponse, data: data)
        #endif
            
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
                audioFilePath: audioResponse.audio_file_path,
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
        targetDate: Date? = nil,  // NEW: Optional target date for correct local_date calculation
        with preferences: UserSettings,
        schedule: DayStartSchedule,
        locationData: LocationData? = nil,
        weatherData: WeatherData? = nil,
        calendarEvents: [String]? = nil,
        isWelcome: Bool = false
    ) async throws -> JobResponse {
        let url = functionsURL.appendingPathComponent("create_job")
        
        logger.log("📤 Supabase API: POST create_job", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif
        
        var request = await createRequest(for: url, method: "POST")
        
        // Use targetDate for local_date if provided (for future jobs), otherwise use scheduled date
        let dateForLocalDate = targetDate ?? date
        
        let jobRequest = CreateJobRequest(
            local_date: localDateString(from: dateForLocalDate),
            scheduled_at: ISO8601DateFormatter().string(from: date),
            preferred_name: preferences.preferredName,
            include_weather: preferences.includeWeather,
            include_news: preferences.includeNews,
            include_sports: preferences.includeSports,
            selected_sports: preferences.selectedSports.map(\.rawValue),
            selected_news_categories: preferences.selectedNewsCategories.map(\.rawValue),
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
            force_update: nil,
            is_welcome: isWelcome
        )
        
        let jsonData = try JSONEncoder().encode(jobRequest)
        request.httpBody = jsonData
        
        // Debug logging for news specifically
        logger.log("📰 News in create_job: includeNews=\(preferences.includeNews), selectedNewsCategories=\(preferences.selectedNewsCategories.map(\.rawValue))", level: .debug)
        
        // Debug logging for sports specifically  
        logger.log("🏈 Sports in create_job: includeSports=\(preferences.includeSports), selectedSports=\(preferences.selectedSports.map(\.rawValue))", level: .debug)
        
        // Log request payload
        if let requestString = String(data: jsonData, encoding: .utf8) {
            logger.log("📝 create_job payload: \(requestString)", level: .debug)
        }
        
        do {
            #if DEBUG
        logger.logNetworkRequest(request)
        #endif
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
                requestId: jobResponse.request_id,
                isWelcome: jobResponse.is_welcome
            )
            
        } catch {
            logger.logError(error, context: "Failed to create job for \(date)")
            throw error
        }
    }

    // MARK: - Create Initial Schedule Jobs
    
    /// Creates jobs for the initial schedule after onboarding, excluding today
    func createInitialScheduleJobs(
        schedule: DayStartSchedule,
        preferences: UserSettings,
        excludeToday: Bool = true
    ) async throws -> Int {
        logger.log("📅 Creating initial schedule jobs (excludeToday: \(excludeToday))", level: .info)
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var jobsCreated = 0
        
        // Create jobs for the next 3 days (to ensure at least 48 hours coverage)
        for dayOffset in 0..<3 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            
            // Skip today if requested
            if excludeToday && dayOffset == 0 {
                logger.log("⏭️ Skipping today for initial schedule", level: .debug)
                continue
            }
            
            // Check if this day is in the schedule
            let weekday = calendar.component(.weekday, from: targetDate)
            let dayOfWeek = WeekDay.fromCalendarWeekday(weekday)
            
            guard schedule.repeatDays.contains(dayOfWeek) else {
                continue
            }
            
            // Create scheduled time for this date using timezone-independent components
            let timeComponents = schedule.effectiveTimeComponents
            let scheduledTime = calendar.date(bySettingHour: timeComponents.hour ?? 7,
                                              minute: timeComponents.minute ?? 0,
                                              second: 0,
                                              of: targetDate) ?? targetDate
            
            // Skip if the scheduled time has already passed
            if scheduledTime < Date() {
                logger.log("⏭️ Skipping past time: \(scheduledTime)", level: .debug)
                continue
            }
            
            do {
                // Build snapshot for the date (without blocking on weather/calendar for future dates)
                let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: scheduledTime)
                
                _ = try await createJob(
                    for: scheduledTime,
                    targetDate: targetDate,  // Pass the actual date separately
                    with: preferences,
                    schedule: schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather, // Include weather for all 3 days
                    calendarEvents: snapshot.calendar, // Include calendar for all 3 days
                    isWelcome: false
                )
                
                jobsCreated += 1
                logger.log("✅ Created job for \(localDateString(from: scheduledTime))", level: .debug)
            } catch {
                logger.logError(error, context: "Failed to create job for \(scheduledTime)")
                // Continue creating other jobs even if one fails
            }
        }
        
        logger.log("📅 Created \(jobsCreated) initial schedule jobs", level: .info)
        return jobsCreated
    }
    
    // MARK: - Today Job Backfill
    
    /// Creates a job for today if none exists and today is a scheduled day
    func createTodayJobIfNeeded(
        with preferences: UserSettings,
        schedule: DayStartSchedule
    ) async throws -> Bool {
        logger.log("📅 Checking if today job needs to be created", level: .info)
        
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        // Check if today is a scheduled day
        let weekday = calendar.component(.weekday, from: now)
        let dayOfWeek = WeekDay.fromCalendarWeekday(weekday)
        
        guard schedule.repeatDays.contains(dayOfWeek) else {
            logger.log("⏭️ Today is not a scheduled day", level: .debug)
            return false
        }
        
        // Check if a job already exists for today
        let audioStatus = try await getAudioStatus(for: today)
        
        if audioStatus.status != "not_found" {
            logger.log("✅ Job already exists for today: \(audioStatus.status)", level: .info)
            return false
        }
        
        logger.log("🔄 Creating today's job with high priority", level: .info)
        
        // Build snapshot for today
        let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: now)
        
        // Create job with "NOW" scheduling for immediate processing
        let jobResponse = try await createJob(
            for: now, // Use "NOW" for immediate processing
            targetDate: today, // But target today's date
            with: preferences,
            schedule: schedule,
            locationData: snapshot.location,
            weatherData: snapshot.weather,
            calendarEvents: snapshot.calendar,
            isWelcome: false
        )
        
        logger.log("✅ Today job created: \(jobResponse.jobId ?? "unknown") with status: \(jobResponse.status ?? "unknown")", level: .info)
        
        // Immediately trigger processing (same as welcome jobs)
        if let jobId = jobResponse.jobId {
            do {
                try await invokeProcessJob(jobId: jobId)
                logger.log("🚀 Successfully triggered immediate processing for today job: \(jobId)", level: .info)
            } catch {
                logger.logError(error, context: "Failed to trigger processing for today job: \(jobId)")
                // Continue normally if trigger fails - job will be picked up by cron
            }
        }
        
        return true
    }
    
    // MARK: - Bulk Update Jobs API
    func updateJobs(
        dates: [Date],
        with settings: UserSettings,
        scheduleTime: String? = nil, // NEW: Time in HH:MM format (e.g., "07:30") for recalculating scheduled_at
        cancelDates: [Date] = [],
        reactivateDates: [Date] = [],
        forceRequeue: Bool = false
    ) async throws -> UpdateJobsResult {
        let url = functionsURL.appendingPathComponent("update_jobs")

        logger.log("📤 Supabase API: POST update_jobs (update: \(dates.count), cancel: \(cancelDates.count), reactivate: \(reactivateDates.count))", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif

        var request = await createRequest(for: url, method: "POST")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let dateStrings = dates.map { formatter.string(from: $0) }
        let cancelDateStrings = cancelDates.isEmpty ? nil : cancelDates.map { formatter.string(from: $0) }
        let reactivateDateStrings = reactivateDates.isEmpty ? nil : reactivateDates.map { formatter.string(from: $0) }

        let payload = UpdateJobsRequest(
            dates: dateStrings,
            date_range: nil,
            statuses: nil, // use server default (queued + failed)
            settings: UpdateSettings(
                preferred_name: settings.preferredName,
                include_weather: settings.includeWeather,
                include_news: settings.includeNews,
                include_sports: settings.includeSports,
                selected_sports: settings.selectedSports.map { $0.rawValue },
                selected_news_categories: settings.selectedNewsCategories.map { $0.rawValue },
                include_stocks: settings.includeStocks,
                stock_symbols: settings.stockSymbols,
                include_calendar: settings.includeCalendar,
                include_quotes: settings.includeQuotes,
                quote_preference: settings.quotePreference.rawValue,
                voice_option: "voice\(settings.selectedVoice.rawValue + 1)",
                daystart_length: settings.dayStartLength * 60, // Convert minutes to seconds
                timezone: TimeZone.current.identifier,
                schedule_time: scheduleTime // NEW: Time for recalculating scheduled_at
            ),
            force_requeue: forceRequeue,
            cancel_for_removed_dates: cancelDateStrings,
            reactivate_for_added_dates: reactivateDateStrings
        )

        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData

        // Debug logging for sports specifically
        logger.log("🏈 Sports in payload: includeSports=\(settings.includeSports), selectedSports=\(settings.selectedSports.map(\.rawValue))", level: .debug)
        
        // Debug logging for news specifically
        logger.log("📰 News in payload: includeNews=\(settings.includeNews), selectedNewsCategories=\(settings.selectedNewsCategories.map(\.rawValue))", level: .debug)

        if let requestString = String(data: jsonData, encoding: .utf8) {
            logger.log("📝 update_jobs payload: \(requestString)", level: .debug)
        }

        #if DEBUG
        logger.logNetworkRequest(request)
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("❌ Supabase API: Invalid response type (update_jobs)", level: .error)
            throw SupabaseError.invalidResponse
        }

        logger.log("📥 Supabase API: Response status (update_jobs): \(httpResponse.statusCode)", level: .info)
        #if DEBUG
        logger.logNetworkResponse(httpResponse, data: data)
        #endif

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
        return UpdateJobsResult(success: true, updatedCount: resp.updated_count ?? 0, cancelledCount: resp.cancelled_count ?? 0, reactivatedCount: resp.reactivated_count ?? 0)
    }
    
    // MARK: - Snapshot Update API
    
    func updateJobSnapshots(
        jobIds: [String],
        locationData: LocationData?,
        weatherData: WeatherData?,
        calendarEvents: [String]?
    ) async throws -> Bool {
        let url = functionsURL.appendingPathComponent("update_job_snapshots")
        
        logger.log("📤 Supabase API: POST update_job_snapshots", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif
        
        var request = await createRequest(for: url, method: "POST")
        
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
        
        #if DEBUG
        logger.logNetworkRequest(request)
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("❌ Supabase API: Invalid response type (update_job_snapshots)", level: .error)
            throw SupabaseError.invalidResponse
        }
        
        logger.log("📥 Supabase API: Response status (update_job_snapshots): \(httpResponse.statusCode)", level: .info)
        #if DEBUG
        logger.logNetworkResponse(httpResponse, data: data)
        #endif
        
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
        let url = functionsURL.appendingPathComponent("get_jobs")
            .appendingQueryItem(name: "start_date", value: startDate)
            .appendingQueryItem(name: "end_date", value: endDate)
        
        logger.log("📤 Supabase API: GET get_jobs", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif
        
        var request = await createRequest(for: url, method: "GET")
        
        #if DEBUG
        logger.logNetworkRequest(request)
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("❌ Supabase API: Invalid response type (get_jobs)", level: .error)
            throw SupabaseError.invalidResponse
        }
        
        logger.log("📥 Supabase API: Response status (get_jobs): \(httpResponse.statusCode)", level: .info)
        #if DEBUG
        logger.logNetworkResponse(httpResponse, data: data)
        #endif
        
        guard httpResponse.statusCode == 200 else {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            logger.log("📄 get_jobs response: \(responseString)", level: .debug)
        }
        
        let resp = try JSONDecoder().decode(GetJobsResponse.self, from: data)
        return resp.success ? resp.jobs ?? [] : []
    }
    
    
    // MARK: - Job Management
    
    func markJobAsFailed(jobId: String, errorCode: String) async throws {
        let url = restURL.appendingPathComponent("jobs")
        
        logger.log("📤 Supabase API: PATCH jobs - marking job as failed", level: .info)
        
        var request = await createRequest(for: url, method: "PATCH")
        
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
            #if DEBUG
        logger.logNetworkRequest(request)
        #endif
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
        let url = functionsURL.appendingPathComponent("process_jobs")
        
        logger.log("🚀 Invoking process_jobs for specific job: \(jobId)", level: .info)
        
        var request = await createRequest(for: url, method: "POST")
        
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
    
    private func createRequest(for url: URL, method: String) async -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DayStart-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        // Set authorization header
        if let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        // ALWAYS set user identifier (anonymous ID for all users, permanent even after purchase)
        if let userId = await PurchaseManager.shared.userIdentifier {
            request.setValue(userId, forHTTPHeaderField: "x-client-info")
        }

        // Set auth type based on premium status (not just identifier existence)
        let isPremium = await PurchaseManager.shared.isPremium
        request.setValue(isPremium ? "purchase" : "anonymous", forHTTPHeaderField: "x-auth-type")

        logger.log("🔑 Request headers set: x-client-info=\(request.value(forHTTPHeaderField: "x-client-info")?.prefix(20) ?? "none"), x-auth-type=\(request.value(forHTTPHeaderField: "x-auth-type") ?? "none")", level: .debug)
        
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
    let selected_sports: [String]
    let selected_news_categories: [String]
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
    let is_welcome: Bool? // optional, when set true indicates this is a welcome/onboarding job
}

// MARK: - Update Jobs API models

private struct UpdateJobsRequest: Codable {
    let dates: [String]?
    let date_range: DateRangeFilter?
    let statuses: [String]?
    let settings: UpdateSettings?
    let force_requeue: Bool?
    let cancel_for_removed_dates: [String]?
    let reactivate_for_added_dates: [String]?
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
    let selected_sports: [String]?
    let selected_news_categories: [String]?
    let include_stocks: Bool?
    let stock_symbols: [String]?
    let include_calendar: Bool?
    let include_quotes: Bool?
    let quote_preference: String?
    let voice_option: String?
    let daystart_length: Int?
    let timezone: String?
    let schedule_time: String? // NEW: Time in HH:MM format for scheduled_at calculation
}

private struct UpdateJobsAPIResponse: Codable {
    let success: Bool
    let updated_count: Int?
    let cancelled_count: Int?
    let reactivated_count: Int?
    let error_code: String?
    let error_message: String?
    let request_id: String?
}

struct UpdateJobsResult {
    let success: Bool
    let updatedCount: Int
    let cancelledCount: Int
    let reactivatedCount: Int
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
    let is_welcome: Bool?
}

private struct AudioStatusAPIResponse: Codable {
    let success: Bool
    let status: String // 'ready'|'processing'|'not_found'|'failed'
    let job_id: String?
    let audio_url: String?
    let audio_file_path: String? // Backend storage path for share functionality
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
    let isWelcome: Bool?
}

struct AudioStatusResponse {
    let success: Bool
    let status: String // 'ready'|'processing'|'not_found'|'failed'
    let jobId: String?
    let audioUrl: URL?
    let audioFilePath: String? // Backend storage path for share functionality
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
               !baseURL.absoluteString.contains("your-project") &&
               !restURL.absoluteString.contains("your-project") &&
               !functionsURL.absoluteString.contains("your-project")
    }
}

// MARK: - App Feedback API

extension SupabaseClient {
    struct AppFeedbackPayload: Codable {
        let category: String
        let message: String?
        let include_diagnostics: Bool?
        let history_id: String?
        let app_version: String?
        let build: String?
        let device_model: String?
        let os_version: String?
        let email: String?
    }
    
    func submitAppFeedback(_ payload: AppFeedbackPayload) async throws -> Bool {
        let url = functionsURL.appendingPathComponent("submit_feedback")
        var request = await createRequest(for: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(payload)
        logger.log("📤 Supabase API: POST submit_feedback", level: .info)
        #if DEBUG
        logger.logNetworkRequest(request)
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        #if DEBUG
        logger.logNetworkResponse(httpResponse, data: data)
        #endif
        return httpResponse.statusCode == 201 || httpResponse.statusCode == 200
    }
}

// MARK: - Share API

extension SupabaseClient {
    /// Creates a shareable link for a DayStart
    func createShare(
        jobId: String,
        dayStartData: DayStartData,
        source: String = "unknown",
        durationHours: Int = 48
    ) async throws -> ShareResponse {
        let url = functionsURL.appendingPathComponent("create_share")
        
        logger.log("📤 Supabase API: POST create_share for job: \(jobId)", level: .info)
        #if DEBUG
        logger.log("📡 Request URL: \(url.absoluteString)", level: .debug)
        #endif
        
        var request = await createRequest(for: url, method: "POST")
        
        // Increase timeout for share operations (involves multiple DB queries)
        request.timeoutInterval = 60
        
        // Add app version header for tracking
        if let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            request.setValue(appVersion, forHTTPHeaderField: "x-app-version")
        }
        
        // Format date for consistency with backend
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let localDateString = dateFormatter.string(from: dayStartData.date)
        
        let preferredName = await UserPreferences.shared.settings.preferredName
        
        // Enhanced logging for audioStoragePath issues
        let audioStoragePath = dayStartData.audioStoragePath ?? ""
        if audioStoragePath.isEmpty {
            logger.log("⚠️ createShare: audioStoragePath is empty for jobId=\(jobId), localDate=\(localDateString)", level: .warning)
            logger.log("📊 DayStart debug info: hasAudioFilePath=\(dayStartData.audioFilePath != nil), hasJobId=\(dayStartData.jobId != nil), duration=\(dayStartData.duration)", level: .debug)
        } else {
            logger.log("✅ createShare: audioStoragePath available: \(audioStoragePath)", level: .debug)
        }
        
        let requestBody = CreateShareRequest(
            job_id: jobId,
            share_source: source,
            duration_hours: durationHours,
            audio_file_path: audioStoragePath,
            audio_duration: Int(dayStartData.duration),
            local_date: localDateString,
            daystart_length: Int(dayStartData.duration), // Use duration for length
            preferred_name: preferredName
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        // Log request payload
        if let requestString = String(data: jsonData, encoding: .utf8) {
            logger.log("📝 create_share payload: \(requestString)", level: .debug)
        }
        
        do {
            #if DEBUG
            logger.logNetworkRequest(request)
            #endif
            
            logger.log("🌐 Starting share creation network request...", level: .info)
            let (data, response) = try await URLSession.shared.data(for: request)
            logger.log("🌐 Share creation network request completed", level: .info)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("❌ Supabase API: Invalid response type", level: .error)
                throw SupabaseError.invalidResponse
            }
            
            logger.log("📥 Supabase API: Response status (create_share): \(httpResponse.statusCode)", level: .info)
            #if DEBUG
            logger.logNetworkResponse(httpResponse, data: data)
            #endif
            
            // Log response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                logger.log("📄 create_share response: \(responseString)", level: .debug)
            }
            
            guard httpResponse.statusCode == 201 else {
                // Handle specific error codes
                if let errorData = try? JSONDecoder().decode(CreateShareErrorResponse.self, from: data) {
                    switch errorData.code {
                    case "RATE_LIMIT_EXCEEDED":
                        throw SupabaseError.apiError("RATE_LIMIT", errorData.error)
                    case "DAILY_LIMIT_EXCEEDED":
                        throw SupabaseError.apiError("DAILY_LIMIT", errorData.error)
                    case "RAPID_RETRY_DETECTED":
                        throw SupabaseError.apiError("RAPID_RETRY", errorData.error)
                    default:
                        throw SupabaseError.apiError(errorData.code, errorData.error)
                    }
                }
                
                logger.logError(NSError(domain: "SupabaseError", code: httpResponse.statusCode),
                               context: "HTTP error in createShare: \(httpResponse.statusCode)")
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
            
            logger.log("🔍 Parsing share response JSON...", level: .debug)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let shareResponse = try decoder.decode(ShareResponse.self, from: data)
            logger.log("✅ Share response parsed successfully", level: .debug)
            
            logger.log("✅ Supabase API: Share created with token: \(shareResponse.token)", level: .info)
            
            return shareResponse
            
        } catch {
            // Log specific error types for better debugging
            if let urlError = error as? URLError {
                logger.log("❌ Network error in createShare: \(urlError.localizedDescription) (code: \(urlError.code.rawValue))", level: .error)
                if urlError.code == .timedOut {
                    logger.log("⏰ Share creation timed out - consider backend performance", level: .error)
                }
            } else if error is DecodingError {
                logger.log("❌ JSON decoding error in createShare: \(error)", level: .error)
            } else {
                logger.log("❌ Unknown error in createShare: \(error)", level: .error)
            }
            
            logger.logError(error, context: "Failed to create share for job: \(jobId)")
            throw error
        }
    }
}

// MARK: - Share API Models

private struct CreateShareRequest: Codable {
    let job_id: String
    let share_source: String
    let duration_hours: Int
    // Public data fields to store in shares table
    let audio_file_path: String
    let audio_duration: Int
    let local_date: String
    let daystart_length: Int
    let preferred_name: String
}

private struct CreateShareErrorResponse: Codable {
    let error: String
    let code: String?
}