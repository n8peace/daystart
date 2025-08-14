import Foundation
import BackgroundTasks

@MainActor
class AudioPrefetchManager {
    static let shared = AudioPrefetchManager()
    
    private let taskIdentifier = "ai.bananaintelligence.DayStart.audio-prefetch"
    private let logger = DebugLogger.shared
    
    private init() {}
    
    // MARK: - Tier 1: BGTaskScheduler (Background Processing)
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            guard let self = self else { return }
            self.handleAudioPrefetch(task: task as! BGProcessingTask)
        }
        logger.log("Registered background task: \(taskIdentifier)", level: .info)
    }
    
    func scheduleAudioPrefetch(for scheduledTime: Date) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = scheduledTime.addingTimeInterval(-2 * 3600) // 2 hours before
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.log("Scheduled BGTask for \(scheduledTime)", level: .info)
        } catch {
            logger.logError(error, context: "Failed to schedule background task")
        }
    }
    
    private func handleAudioPrefetch(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            let success = await precreateJobsWithSnapshotIfNeeded()
            task.setTaskCompleted(success: success)
        }
    }
    
    // MARK: - Tier 2: Foreground Check (App State Transitions)
    
    func checkForUpcomingDayStarts() async {
        let upcomingSchedules = getSchedulesWithinHours(2)
        
        guard !upcomingSchedules.isEmpty else {
            logger.log("No upcoming DayStarts within 2 hours", level: .debug)
            return
        }
        
        logger.log("Checking \(upcomingSchedules.count) upcoming DayStarts for ready audio", level: .info)
        
        for schedule in upcomingSchedules {
            await checkAndDownloadAudio(for: schedule.date)
        }
    }
    
    private func checkAndDownloadAudio(for date: Date) async -> Bool {
        // Check if audio already cached locally
        if AudioCache.shared.hasAudio(for: date) {
            logger.log("Audio already cached for \(date)", level: .debug)
            return true
        }
        
        // Call backend to check if audio is ready
        do {
            let response = try await SupabaseClient.shared.getAudioStatus(for: date)
            
            if response.status == "ready", let audioUrl = response.audioUrl {
                logger.log("Audio ready for \(date), downloading...", level: .info)
                return await AudioDownloader.shared.download(from: audioUrl, for: date)
            } else if response.status == "not_found" {
                // Audio doesn't exist yet, create a job for it with snapshot context
                logger.log("Audio not found for \(date), creating job with snapshot...", level: .info)
                let snapshot = await SnapshotBuilder.shared.buildSnapshot()
                do {
                    let jobResponse = try await SupabaseClient.shared.createJob(
                        for: date,
                        with: UserPreferences.shared.settings,
                        schedule: UserPreferences.shared.schedule,
                        locationData: snapshot.location,
                        weatherData: snapshot.weather,
                        calendarEvents: snapshot.calendar
                    )
                    logger.log("Created job \(jobResponse.jobId ?? "unknown") for \(date)", level: .info)
                } catch {
                    logger.logError(error, context: "Failed to create job for \(date)")
                }
                
                return false
            } else {
                logger.log("Audio not ready for \(date), status: \(response.status)", level: .debug)
                return false
            }
        } catch {
            logger.logError(error, context: "Failed to check audio status for \(date)")
            return false
        }
    }
    
    private func precreateJobsWithSnapshotIfNeeded() async -> Bool {
        let upcomingSchedules = getSchedulesWithinHours(2)
        if upcomingSchedules.isEmpty { return true }
        
        var createdOrConfirmed = 0
        for schedule in upcomingSchedules {
            let scheduledTime = schedule.scheduledTime
            do {
                let status = try await SupabaseClient.shared.getAudioStatus(for: scheduledTime)
                if status.status == "ready" || status.status == "processing" {
                    // Nothing to do
                    continue
                }
                // Build snapshot context
                let snapshot = await SnapshotBuilder.shared.buildSnapshot()
                _ = try await SupabaseClient.shared.createJob(
                    for: scheduledTime,
                    with: UserPreferences.shared.settings,
                    schedule: UserPreferences.shared.schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar
                )
                createdOrConfirmed += 1
            } catch {
                logger.logError(error, context: "BG precreate job failed for \(scheduledTime)")
            }
        }
        logger.log("Background precreate completed: \(createdOrConfirmed)/\(upcomingSchedules.count) jobs ensured", level: .info)
        return createdOrConfirmed > 0
    }
    
    // MARK: - Helper Methods
    
    private func getSchedulesWithinHours(_ hours: Int) -> [ScheduleInfo] {
        let userPreferences = UserPreferences.shared
        let schedule = userPreferences.schedule
        let calendar = Calendar.current
        let now = Date()
        let endTime = now.addingTimeInterval(TimeInterval(hours * 3600))
        
        var schedules: [ScheduleInfo] = []
        
        // Check each day within the time window
        for dayOffset in 0...2 { // Check today, tomorrow, day after
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { continue }
            
            // Skip if beyond our time window
            guard candidateDate <= endTime else { continue }
            
            // Check if this day is in the repeat schedule
            let weekday = calendar.component(.weekday, from: candidateDate)
            guard let weekDay = WeekDay(weekday: weekday), schedule.repeatDays.contains(weekDay) else { continue }
            
            // Skip tomorrow if skipTomorrow is true
            if schedule.skipTomorrow {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                if calendar.isDate(candidateDate, inSameDayAs: tomorrow) {
                    continue
                }
            }
            
            // Create the scheduled time for this date
            let timeComponents = calendar.dateComponents([.hour, .minute], from: schedule.time)
            var scheduledComponents = calendar.dateComponents([.year, .month, .day], from: candidateDate)
            scheduledComponents.hour = timeComponents.hour
            scheduledComponents.minute = timeComponents.minute
            
            if let scheduledTime = calendar.date(from: scheduledComponents),
               scheduledTime > now && scheduledTime <= endTime {
                schedules.append(ScheduleInfo(date: candidateDate, scheduledTime: scheduledTime))
                
                // Submit BG processing request so iOS may run us before this time
                scheduleAudioPrefetch(for: scheduledTime)
            }
        }
        
        return schedules
    }
    
    // MARK: - Public Interface
    
    func prefetchAudioIfNeeded(for date: Date) async -> Bool {
        return await checkAndDownloadAudio(for: date)
    }
    
    func cancelAllBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        logger.log("Cancelled all background audio prefetch tasks", level: .info)
    }
}

// MARK: - Helper Structs

private struct ScheduleInfo {
    let date: Date
    let scheduledTime: Date
}

// AudioStatusResponse moved to SupabaseClient.swift for consistency