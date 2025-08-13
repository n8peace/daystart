import Foundation

@MainActor
class AudioDownloader: NSObject {
    static let shared = AudioDownloader()
    
    private let logger = DebugLogger.shared
    private var activeDownloads: [Date: DownloadTask] = [:]
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Interface
    
    func download(from url: URL, for date: Date) async -> Bool {
        guard !AudioCache.shared.hasAudio(for: date) else {
            logger.log("Audio already cached for \(date)", level: .debug)
            return true
        }
        
        // Cancel any existing download for this date
        if let existingTask = activeDownloads[date] {
            existingTask.task.cancel()
            activeDownloads.removeValue(forKey: date)
        }
        
        logger.log("Starting audio download for \(date) from \(url.absoluteString)", level: .info)
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.logError(NSError(domain: "DownloadError", code: 1), context: "Invalid response type")
                return false
            }
            
            guard httpResponse.statusCode == 200 else {
                logger.logError(NSError(domain: "DownloadError", code: httpResponse.statusCode), context: "HTTP error: \(httpResponse.statusCode)")
                return false
            }
            
            // Validate audio data
            guard isValidAudioData(data) else {
                logger.logError(NSError(domain: "DownloadError", code: 2), context: "Invalid audio data received")
                return false
            }
            
            // Cache the audio
            guard AudioCache.shared.cacheAudio(data: data, for: date) != nil else {
                logger.logError(NSError(domain: "DownloadError", code: 3), context: "Failed to cache audio data")
                return false
            }
            
            logger.log("Successfully downloaded and cached audio for \(date) (\(data.count) bytes)", level: .info)
            return true
            
        } catch {
            logger.logError(error, context: "Failed to download audio for \(date)")
            return false
        }
    }
    
    func downloadWithProgress(
        from url: URL,
        for date: Date,
        onProgress: @escaping (Double) -> Void
    ) async -> Bool {
        guard !AudioCache.shared.hasAudio(for: date) else {
            logger.log("Audio already cached for \(date)", level: .debug)
            onProgress(1.0)
            return true
        }
        
        // Cancel any existing download for this date
        if let existingTask = activeDownloads[date] {
            existingTask.task.cancel()
            activeDownloads.removeValue(forKey: date)
        }
        
        logger.log("Starting audio download with progress for \(date)", level: .info)
        
        return await withCheckedContinuation { continuation in
            // Create custom delegate to track progress
            let delegate = DownloadDelegate(onProgress: onProgress, logger: logger)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
            let progressTask = session.downloadTask(with: url) { [weak self] tempURL, response, error in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    // Remove from active downloads
                    self.activeDownloads.removeValue(forKey: date)
                    
                    if let error = error {
                        self.logger.logError(error, context: "Download failed for \(date)")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    guard let tempURL = tempURL else {
                        self.logger.logError(NSError(domain: "DownloadError", code: 4), context: "No temp file URL")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        self.logger.logError(NSError(domain: "DownloadError", code: 5), context: "Invalid HTTP response")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    do {
                        let data = try Data(contentsOf: tempURL)
                        
                        // Validate audio data
                        guard self.isValidAudioData(data) else {
                            self.logger.logError(NSError(domain: "DownloadError", code: 6), context: "Invalid audio data")
                            continuation.resume(returning: false)
                            return
                        }
                        
                        // Cache the audio
                        guard AudioCache.shared.cacheAudio(data: data, for: date) != nil else {
                            self.logger.logError(NSError(domain: "DownloadError", code: 7), context: "Failed to cache audio")
                            continuation.resume(returning: false)
                            return
                        }
                        
                        onProgress(1.0)
                        self.logger.log("Successfully downloaded with progress for \(date) (\(data.count) bytes)", level: .info)
                        continuation.resume(returning: true)
                        
                    } catch {
                        self.logger.logError(error, context: "Failed to read downloaded file for \(date)")
                        continuation.resume(returning: false)
                    }
                }
            }
            
            activeDownloads[date] = DownloadTask(task: progressTask, date: date, progressCallback: onProgress)
            progressTask.resume()
        }
    }
    
    func cancelDownload(for date: Date) {
        if let downloadTask = activeDownloads[date] {
            downloadTask.task.cancel()
            activeDownloads.removeValue(forKey: date)
            logger.log("Cancelled download for \(date)", level: .info)
        }
    }
    
    func cancelAllDownloads() {
        for (date, downloadTask) in activeDownloads {
            downloadTask.task.cancel()
            logger.log("Cancelled download for \(date)", level: .debug)
        }
        activeDownloads.removeAll()
        logger.log("Cancelled all active downloads", level: .info)
    }
    
    func isDownloading(for date: Date) -> Bool {
        return activeDownloads[date] != nil
    }
    
    func getActiveDownloadCount() -> Int {
        return activeDownloads.count
    }
    
    // MARK: - Private Helpers
    
    private func isValidAudioData(_ data: Data) -> Bool {
        // Check minimum file size (at least 1KB)
        guard data.count > 1024 else {
            return false
        }
        
        // Check for audio file headers
        let prefix = data.prefix(12)
        let headerBytes = Array(prefix)
        
        // M4A/MP4 header
        if headerBytes.count >= 8 && 
           headerBytes[4] == 0x66 && headerBytes[5] == 0x74 && 
           headerBytes[6] == 0x79 && headerBytes[7] == 0x70 {
            return true
        }
        
        // MP3 header
        if headerBytes.count >= 3 &&
           headerBytes[0] == 0xFF && (headerBytes[1] & 0xE0) == 0xE0 {
            return true
        }
        
        // Additional audio format checks could be added here
        logger.log("Audio validation: Unrecognized format, but allowing", level: .debug)
        return true // Allow for now, can be made stricter later
    }
}

// MARK: - Supporting Types

private struct DownloadTask {
    let task: URLSessionDownloadTask
    let date: Date
    let progressCallback: (Double) -> Void
}

// MARK: - Download Delegate for Progress Tracking

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    private let logger: DebugLogger
    
    init(onProgress: @escaping (Double) -> Void, logger: DebugLogger) {
        self.onProgress = onProgress
        self.logger = logger
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.onProgress(progress)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Completion handled in the main download method
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            logger.logError(error, context: "Download completed with error")
        }
    }
}

// MARK: - Download Progress State

enum DownloadState {
    case idle
    case downloading(progress: Double)
    case completed
    case failed(Error)
    case cancelled
}