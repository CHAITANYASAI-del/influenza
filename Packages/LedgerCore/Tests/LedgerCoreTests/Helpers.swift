import Foundation
@testable import LedgerCore

func day(_ s: String, _ time: String = "12:00") -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: "\(s) \(time)")!
}

extension LedgerEngine {
    var liveTransactions: [CanonicalTransaction] { Array(state.transactions.values) }
    func spent(_ currency: String, from: String = "2026-01-01", to: String = "2027-01-01") -> Decimal {
        summaries(from: day(from, "00:00"), to: day(to, "00:00"))[currency]?.spent ?? 0
    }
    func tx(_ outcome: IngestOutcome) -> CanonicalTransaction? { outcome.transactionID.flatMap { state.transactions[$0] } }
}

func csv(_ rows: [String], header: String = "Date,Description,Amount") -> String { ([header] + rows).joined(separator: "\n") }
