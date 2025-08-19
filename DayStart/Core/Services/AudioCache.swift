import Foundation

@MainActor
class AudioCache {
    static let shared = AudioCache()
    
    private let logger = DebugLogger.shared
    private let fileManager = FileManager.default
    private let cacheDirectoryName = "AudioCache"
    
    private init() {
        setupCacheDirectory()
    }
    
    // MARK: - Cache Directory Setup
    
    private lazy var cacheDirectory: URL = {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent(cacheDirectoryName)
    }()
    
    private func setupCacheDirectory() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                logger.log("Created audio cache directory: \(cacheDirectory.path)", level: .info)
            } catch {
                logger.logError(error, context: "Failed to create audio cache directory")
            }
        }
    }
    
    // MARK: - Public Interface
    
    func hasAudio(for date: Date) -> Bool {
        let filePath = getAudioPath(for: date)
        let exists = fileManager.fileExists(atPath: filePath.path)
        
        if exists {
            logger.log("Audio cache hit for \(date)", level: .debug)
        }
        
        return exists
    }
    
    func getAudioPath(for date: Date) -> URL {
        let filename = audioFilename(for: date)
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    func cacheAudio(data: Data, for date: Date) -> URL? {
        let filePath = getAudioPath(for: date)
        
        do {
            try data.write(to: filePath)
            logger.log("Cached audio for \(date) (\(data.count) bytes)", level: .info)
            return filePath
        } catch {
            logger.logError(error, context: "Failed to cache audio for \(date)")
            return nil
        }
    }
    
    func removeAudio(for date: Date) -> Bool {
        let filePath = getAudioPath(for: date)
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            logger.log("Audio file not found for removal: \(date)", level: .debug)
            return true // Already doesn't exist
        }
        
        do {
            try fileManager.removeItem(at: filePath)
            logger.log("Removed cached audio for \(date)", level: .info)
            return true
        } catch {
            logger.logError(error, context: "Failed to remove cached audio for \(date)")
            return false
        }
    }
    
    func clearOldCache(olderThan days: Int = 7) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var removedCount = 0
        var errorCount = 0
        
        logger.log("Starting cache cleanup - removing files older than \(days) days", level: .info)
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey])
            
            for fileURL in contents {
                guard fileURL.pathExtension == "aac" || fileURL.pathExtension == "mp3" else { continue }
                
                let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = resourceValues.creationDate, creationDate < cutoffDate {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        removedCount += 1
                        logger.log("Removed old cached file: \(fileURL.lastPathComponent)", level: .debug)
                    } catch {
                        logger.logError(error, context: "Failed to remove old cache file: \(fileURL.lastPathComponent)")
                        errorCount += 1
                    }
                }
            }
            
            logger.log("Cache cleanup completed: \(removedCount) files removed, \(errorCount) errors", level: .info)
            
        } catch {
            logger.logError(error, context: "Failed to read cache directory for cleanup")
        }
    }
    
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        } catch {
            logger.logError(error, context: "Failed to calculate cache size")
        }
        
        return totalSize
    }
    
    func getCacheSizeString() -> String {
        let bytes = getCacheSize()
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    func clearAllCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            var removedCount = 0
            
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
                removedCount += 1
            }
            
            logger.log("Cleared all cache: \(removedCount) files removed", level: .info)
            
        } catch {
            logger.logError(error, context: "Failed to clear all cache")
        }
    }
    
    // MARK: - Private Helpers
    
    private func audioFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "daystart-\(formatter.string(from: date)).aac"
    }
    
    // MARK: - Cache Statistics
    
    func getCacheInfo() -> CacheInfo {
        var fileCount = 0
        var totalSize: Int64 = 0
        var oldestFile: Date?
        var newestFile: Date?
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
            
            for fileURL in contents {
                guard fileURL.pathExtension == "aac" || fileURL.pathExtension == "mp3" else { continue }
                
                let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                
                fileCount += 1
                
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
                
                if let creationDate = resourceValues.creationDate {
                    if oldestFile == nil || creationDate < oldestFile! {
                        oldestFile = creationDate
                    }
                    if newestFile == nil || creationDate > newestFile! {
                        newestFile = creationDate
                    }
                }
            }
        } catch {
            logger.logError(error, context: "Failed to get cache info")
        }
        
        return CacheInfo(
            fileCount: fileCount,
            totalSize: totalSize,
            oldestFile: oldestFile,
            newestFile: newestFile
        )
    }
}

// MARK: - Cache Info Structure

struct CacheInfo {
    let fileCount: Int
    let totalSize: Int64
    let oldestFile: Date?
    let newestFile: Date?
    
    var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}