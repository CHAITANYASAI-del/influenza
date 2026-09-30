import OSLog

/// All logging goes through here. Interpolated values are `.private`, so
/// merchant names and amounts are redacted in device logs and sysdiagnoses.
/// There is no third-party analytics/crash SDK in the app at all.
enum SafeLog {
    private static let logger = Logger(subsystem: "com.chaitanyasai.influenza", category: "app")
    static func info(_ event: StaticString) { logger.info("\(event, privacy: .public)") }
    static func error(_ event: StaticString, _ error: Error) {
        logger.error("\(event, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
    }
}
