import Foundation

enum StatementDebugLogger {
    #if DEBUG
    static var isEnabled = true

    private static let queue = DispatchQueue(label: "StatementDebugLogger.queue")
    private static var sequence: Int = 0
    private static var traceCounts: [String: Int] = [:]

    private static func nextSequenceAndTime() -> (Int, String) {
        queue.sync {
            sequence += 1
            let time = String(format: "%.3f", Date().timeIntervalSince1970)
            return (sequence, time)
        }
    }

    static func log(
        _ message: String,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        guard isEnabled else { return }
        let (sequence, time) = nextSequenceAndTime()
        let fileName = file.split(separator: "/").last ?? ""
        print("[StatementFlow][\(sequence)][\(time)] \(fileName):\(line) \(function) - \(message)")
    }

    static func trace(
        _ message: String,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line,
        limit: Int = 5
    ) {
        guard isEnabled else { return }
        var shouldLog = false
        var shouldSuppressNotice = false

        queue.sync {
            let key = "\(file)#\(function)"
            let count = (traceCounts[key] ?? 0) + 1
            traceCounts[key] = count
            if count <= limit {
                shouldLog = true
            } else if count == limit + 1 {
                shouldLog = true
                shouldSuppressNotice = true
            }
        }

        guard shouldLog else { return }
        if shouldSuppressNotice {
            log("trace suppressed after \(limit) calls", function: function, file: file, line: line)
        } else {
            log(message, function: function, file: file, line: line)
        }
    }
    #else
    static var isEnabled: Bool { false }

    static func log(
        _ message: String,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
    }

    static func trace(
        _ message: String,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line,
        limit: Int = 5
    ) {
    }
    #endif
}
