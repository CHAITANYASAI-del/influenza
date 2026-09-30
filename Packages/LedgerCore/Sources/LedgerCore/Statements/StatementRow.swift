import Foundation

/// One line of an official statement before interpretation.
public struct StatementRow: Sendable, Equatable {
    public var date: Date
    public var postedDate: Date?
    public var description: String
    public var amount: Decimal          // always positive
    public var direction: Direction
    public var currencyCode: String
    public var reference: String?
    public var accountHint: String?
    public var transactionTypeHint: String?
}

public enum StatementParseError: Error, Equatable {
    case empty, unsupportedFormat, noHeader, noTransactions
}

public enum StatementFormat: String, Sendable { case csv, ofx, pdfText }

public enum StatementDetector {
    public static func detect(fileName: String, text: String) -> StatementFormat? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ["ofx", "qfx"].contains(ext) || text.contains("<OFX>") || text.contains("OFXHEADER") { return .ofx }
        if ["csv", "tsv", "txt"].contains(ext) { return .csv }
        if ext == "pdf" { return .pdfText }
        return nil
    }
}

/// Flexible date parsing for statements across India/US/EU conventions.
enum StatementDates {
    private static let formatsDayFirst = ["dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd-MM-yy", "dd.MM.yyyy", "dd MMM yyyy", "dd-MMM-yyyy", "dd-MMM-yy", "dd MMM yy", "d MMM yyyy", "d/M/yyyy"]
    private static let formatsMonthFirst = ["MM/dd/yyyy", "MM/dd/yy", "M/d/yyyy", "M/d/yy", "MM-dd-yyyy", "MMM dd, yyyy", "MMM d, yyyy"]
    private static let formatsISO = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyyMMdd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var lastFormat: String?

    static func formatter(_ f: String) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[f] { return cached }
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = .current
        d.dateFormat = f
        d.isLenient = false
        cache[f] = d
        return d
    }

    /// Decide day-first vs month-first from the whole column, falling back to currency convention.
    static func dayFirst(samples: [String], currency: String) -> Bool {
        for s in samples {
            let parts = s.split(whereSeparator: { "/-. ".contains($0) }).compactMap { Int($0) }
            guard parts.count >= 2, parts[0] <= 31 else { continue }
            if parts[0] > 12 { return true }
            if parts[1] > 12 { return false }
        }
        return currency != "USD"
    }

    static func parse(_ raw: String, dayFirst: Bool) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        // Two-digit years must only match "yy" formats (otherwise "26" parses as year 0026).
        let twoDigitYear = RX.matches(#"^\d{1,2}[/\-. ](\d{1,2}|[A-Za-z]{3})[/\-. ]\d{2}$"#, s)
        // Rows in one statement share a format: try the last one that worked first.
        lock.lock(); let preferred = lastFormat; lock.unlock()
        if let preferred, twoDigitYear == (preferred.contains("yy") && !preferred.contains("yyyy")) || preferred.hasPrefix("yyyy") && !twoDigitYear,
           (preferred.hasPrefix("dd") || preferred.hasPrefix("d/")) == dayFirst || preferred.hasPrefix("yyyy") || preferred.hasPrefix("MMM"),
           let d = formatter(preferred).date(from: s) { return d }
        let ordered = formatsISO + (dayFirst ? formatsDayFirst + formatsMonthFirst : formatsMonthFirst + formatsDayFirst)
        for f in ordered where twoDigitYear == (f.contains("yy") && !f.contains("yyyy")) || f.hasPrefix("yyyy") && !twoDigitYear {
            if let d = formatter(f).date(from: s) {
                lock.lock(); lastFormat = f; lock.unlock()
                return d
            }
        }
        return nil
    }
}
