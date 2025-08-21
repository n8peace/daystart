import Foundation
import BackgroundTasks
import CoreLocation
import UserNotifications

/// Manages progressive snapshot updates for scheduled DayStarts within 48-hour horizon
/// Features:
/// - Rate limiting (max once per hour except for preference changes)
/// - Progressive updates (10h and 2h before delivery)
/// - Significant location change monitoring for battery efficiency
/// - Batch updates for multiple jobs
@MainActor
class SnapshotUpdateManager: NSObject {
    static let shared = SnapshotUpdateManager()
    
    private let logger = DebugLogger.shared
    private let backgroundTaskIdentifier = "ai.bananaintelligence.DayStart.snapshot-update"
    
    // Rate limiting state
    private var lastSnapshotUpdate: Date?
    private let updateCooldownInterval: TimeInterval = 3600 // 1 hour
    
    // Location monitoring
    private var locationManager: CLLocationManager?
    private var lastKnownLocation: CLLocation?
    private let significantLocationThreshold: CLLocationDistance = 1000 // 1km
    
    // Background task registration
    private var isBackgroundTaskRegistered = false
    
    override init() {
        super.init()
        setupLocationMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Initialize the snapshot update system
    func initialize() {
        registerBackgroundTaskIfNeeded()
        startSignificantLocationChangeMonitoring()
        scheduleProgressiveUpdatesForUpcomingJobs()
    }
    
    /// Update snapshots for all jobs in next 48 hours (triggered by various events)
    func updateSnapshotsForUpcomingJobs(trigger: UpdateTrigger) async {
        // Check rate limiting (except for preference changes)
        if trigger != .preferencesChanged && !canUpdateSnapshots() {
            logger.log("🔄 Snapshot update skipped due to rate limiting (last: \(lastSnapshotUpdate?.timeIntervalSinceNow ?? 0)s ago)", level: .debug)
            return
        }
        
        logger.log("🔄 Starting snapshot update for trigger: \(trigger.rawValue)", level: .info)
        
        do {
            let jobs = try await getJobsInNext48Hours()
            guard !jobs.isEmpty else {
                logger.log("📅 No jobs found in next 48 hours", level: .debug)
                return
            }
            
            logger.log("📋 Found \(jobs.count) jobs to update in next 48 hours", level: .info)
            
            // Build fresh snapshot
            let snapshot = await SnapshotBuilder.shared.buildSnapshot()
            
            // Update all jobs with fresh snapshot data
            let success = try await SupabaseClient.shared.updateJobSnapshots(
                jobIds: jobs.map { $0.jobId },
                locationData: snapshot.location,
                weatherData: snapshot.weather,
                calendarEvents: snapshot.calendar
            )
            
            if success {
                lastSnapshotUpdate = Date()
                logger.log("✅ Updated \(jobs.count) jobs with fresh snapshot data", level: .info)
                
                // Reschedule progressive updates if needed
                scheduleProgressiveUpdatesForUpcomingJobs()
            } else {
                logger.log("❌ Failed to update job snapshots", level: .error)
            }
            
        } catch {
            logger.logError(error, context: "Failed to update snapshots for upcoming jobs")
        }
    }
    
    /// Handle significant location change
    func handleSignificantLocationChange(_ location: CLLocation) async {
        guard let lastLocation = lastKnownLocation else {
            lastKnownLocation = location
            return
        }
        
        let distance = location.distance(from: lastLocation)
        if distance >= significantLocationThreshold {
            logger.log("📍 Significant location change detected: \(Int(distance))m", level: .info)
            lastKnownLocation = location
            await updateSnapshotsForUpcomingJobs(trigger: .significantLocationChange)
        }
    }
    
    // MARK: - Progressive Updates
    
    private func scheduleProgressiveUpdatesForUpcomingJobs() {
        Task {
            do {
                let jobs = try await getJobsInNext48Hours()
                
                for job in jobs {
                    // Schedule 10-hour update
                    if let update10h = Calendar.current.date(byAdding: .hour, value: -10, to: job.scheduledTime) {
                        scheduleBackgroundUpdate(for: update10h, jobId: job.jobId, type: .tenHoursBefore)
                    }
                    
                    // Schedule 2-hour update
                    if let update2h = Calendar.current.date(byAdding: .hour, value: -2, to: job.scheduledTime) {
                        scheduleBackgroundUpdate(for: update2h, jobId: job.jobId, type: .twoHoursBefore)
                    }
                }
                
                logger.log("📅 Scheduled progressive updates for \(jobs.count) upcoming jobs", level: .info)
                
            } catch {
                logger.logError(error, context: "Failed to schedule progressive updates")
            }
        }
    }
    
    private func scheduleBackgroundUpdate(for date: Date, jobId: String, type: ProgressiveUpdateType) {
        guard isBackgroundTaskRegistered && date > Date() else { return }
        
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = date
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.log("📅 Scheduled \(type.rawValue) update for job \(jobId) at \(date)", level: .debug)
        } catch {
            logger.logError(error, context: "Failed to schedule background update")
        }
    }
    
    // MARK: - Location Monitoring
    
    private func setupLocationMonitoring() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyKilometer // Battery efficient
    }
    
    private func startSignificantLocationChangeMonitoring() {
        guard let locationManager = locationManager else { return }
        
        if locationManager.authorizationStatus == .authorizedAlways ||
           locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.startMonitoringSignificantLocationChanges()
            logger.log("📍 Started monitoring significant location changes", level: .info)
        } else {
            logger.log("📍 Location permission not available for monitoring", level: .debug)
        }
    }
    
    // MARK: - Background Tasks
    
    private func registerBackgroundTaskIfNeeded() {
        guard !isBackgroundTaskRegistered else { return }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { [weak self] task in
            guard let self = self else { return }
            self.handleBackgroundSnapshotUpdate(task: task as! BGProcessingTask)
        }
        
        isBackgroundTaskRegistered = true
        logger.log("✅ Background snapshot update tasks registered", level: .info)
    }
    
    private func handleBackgroundSnapshotUpdate(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                await updateSnapshotsForUpcomingJobs(trigger: .backgroundTask)
                task.setTaskCompleted(success: true)
            } catch {
                logger.logError(error, context: "Background snapshot update failed")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func canUpdateSnapshots() -> Bool {
        guard let lastUpdate = lastSnapshotUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) >= updateCooldownInterval
    }
    
    private func getJobsInNext48Hours() async throws -> [JobInfo] {
        let now = Date()
        let endTime = now.addingTimeInterval(48 * 60 * 60) // 48 hours
        
        let startDateString = ISO8601DateFormatter().string(from: now).prefix(10) // YYYY-MM-DD
        let endDateString = ISO8601DateFormatter().string(from: endTime).prefix(10) // YYYY-MM-DD
        
        // Use existing update_jobs endpoint to query jobs in date range
        let result = try await SupabaseClient.shared.getJobsInDateRange(
            startDate: String(startDateString),
            endDate: String(endDateString)
        )
        
        return result.compactMap { job in
            guard let scheduledAt = job.scheduledAt,
                  let scheduledTime = ISO8601DateFormatter().date(from: scheduledAt),
                  scheduledTime > now && scheduledTime <= endTime else {
                return nil
            }
            
            return JobInfo(
                jobId: job.jobId,
                localDate: job.localDate,
                scheduledTime: scheduledTime
            )
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension SnapshotUpdateManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task {
            await handleSignificantLocationChange(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            startSignificantLocationChangeMonitoring()
        case .denied, .restricted:
            logger.log("📍 Location permission denied/restricted", level: .warning)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Supporting Types

enum UpdateTrigger: String {
    case appForeground = "app_foreground"
    case preferencesChanged = "preferences_changed"
    case dayStartPlayed = "daystart_played"
    case significantLocationChange = "significant_location_change"
    case backgroundTask = "background_task"
}

enum ProgressiveUpdateType: String {
    case tenHoursBefore = "10h_before"
    case twoHoursBefore = "2h_before"
}

struct JobInfo {
    let jobId: String
    let localDate: String
    let scheduledTime: Date
}