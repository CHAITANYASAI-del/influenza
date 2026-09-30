import Foundation

/// Compiled-regex cache. Inline `range(of:options:.regularExpression)` recompiles
/// every call, which dominated import time on 10k-row statements.
public enum RX {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func regex(_ pattern: String) -> NSRegularExpression {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        let r = try! NSRegularExpression(pattern: pattern)
        cache[pattern] = r
        return r
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        regex(pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Mentions a currency amount at all — used to keep diagnostics lists relevant.
    public static func looksMoneyish(_ text: String) -> Bool {
        matches(#"(?i)(₹|rs\.?|inr|\$|usd|€|£)\s?\d"#, text)
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        regex(pattern).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
