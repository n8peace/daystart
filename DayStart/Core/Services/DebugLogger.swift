import Foundation
import OSLog
import Darwin.Mach

class DebugLogger {
    static let shared = DebugLogger()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.daystart.app", category: "general")
    
    enum LogLevel {
        case debug
        case info
        case warning
        case error
        case fault
        
        var osLogType: OSLogType {
            switch self {
            case .debug:
                return .debug
            case .info:
                return .info
            case .warning:
                return .default
            case .error:
                return .error
            case .fault:
                return .fault
            }
        }
        
        var prefix: String {
            switch self {
            case .debug:
                return "🔍 DEBUG"
            case .info:
                return "ℹ️ INFO"
            case .warning:
                return "⚠️ WARNING"
            case .error:
                return "❌ ERROR"
            case .fault:
                return "💥 FAULT"
            }
        }
    }
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        
        // Use OSLog for system logging
        logger.log(level: level.osLogType, "\(logMessage)")
        
        // Also print to console for debugging
        #if DEBUG
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        print("\(timestamp) \(level.prefix): \(logMessage)")
        #endif
    }
    
    func logError(_ error: Error, context: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        let errorMessage = context.isEmpty ? error.localizedDescription : "\(context): \(error.localizedDescription)"
        log(errorMessage, level: .error, file: file, function: function, line: line)
    }
    
    func logNetworkRequest(_ request: URLRequest, file: String = #file, function: String = #function, line: Int = #line) {
        guard let url = request.url else { return }
        let method = request.httpMethod ?? "GET"
        log("🌐 \(method) \(url.absoluteString)", level: .debug, file: file, function: function, line: line)
    }
    
    func logNetworkResponse(_ response: HTTPURLResponse, data: Data?, file: String = #file, function: String = #function, line: Int = #line) {
        let statusCode = response.statusCode
        let url = response.url?.absoluteString ?? "unknown"
        let dataSize = data?.count ?? 0
        
        let level: LogLevel = statusCode >= 400 ? .error : .debug
        log("🌐 Response: \(statusCode) \(url) (\(dataSize) bytes)", level: level, file: file, function: function, line: line)
    }
    
    func logUserAction(_ action: String, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        var message = "👤 User Action: \(action)"
        if !details.isEmpty {
            let detailsString = details.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            message += " [\(detailsString)]"
        }
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func logPerformance(_ operation: String, duration: TimeInterval, file: String = #file, function: String = #function, line: Int = #line) {
        let formattedDuration = String(format: "%.3f", duration)
        log("⏱️ Performance: \(operation) took \(formattedDuration)s", level: .info, file: file, function: function, line: line)
    }
    
    func logMemoryUsage(file: String = #file, function: String = #function, line: Int = #line) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsage = Double(info.resident_size) / 1024 / 1024 // MB
            log("💾 Memory Usage: \(String(format: "%.2f", memoryUsage)) MB", level: .debug, file: file, function: function, line: line)
        }
    }
    
    // MARK: - Audio Logging
    func logAudioEvent(_ event: String, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        var message = "🔊 Audio: \(event)"
        if !details.isEmpty {
            let detailsString = details.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            message += " [\(detailsString)]"
        }
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    // MARK: - Theme Logging
    func logThemeChange(from oldTheme: String, to newTheme: String, file: String = #file, function: String = #function, line: Int = #line) {
        log("🎨 Theme changed: \(oldTheme) → \(newTheme)", level: .info, file: file, function: function, line: line)
    }
    
    // MARK: - Notification Logging
    func logNotification(_ event: String, identifier: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var message = "🔔 Notification: \(event)"
        if let id = identifier {
            message += " [\(id)]"
        }
        log(message, level: .info, file: file, function: function, line: line)
    }
}

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Convenience Extensions
extension DebugLogger {
    func startPerformanceTimer() -> Date {
        return Date()
    }
    
    func endPerformanceTimer(_ startTime: Date, operation: String, file: String = #file, function: String = #function, line: Int = #line) {
        let duration = Date().timeIntervalSince(startTime)
        logPerformance(operation, duration: duration, file: file, function: function, line: line)
    }
}

// MARK: - Performance Measurement Helper
func measurePerformance<T>(_ operation: String, _ block: () throws -> T) rethrows -> T {
    let startTime = Date()
    let result = try block()
    let duration = Date().timeIntervalSince(startTime)
    DebugLogger.shared.logPerformance(operation, duration: duration)
    return result
}

func measurePerformanceAsync<T>(_ operation: String, _ block: () async throws -> T) async rethrows -> T {
    let startTime = Date()
    let result = try await block()
    let duration = Date().timeIntervalSince(startTime)
    DebugLogger.shared.logPerformance(operation, duration: duration)
    return result
}