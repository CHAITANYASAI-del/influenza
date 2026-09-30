import XCTest
@testable import LedgerCore

/// Local-only replay against a ledger exported from the developer's own device.
/// Skipped unless LEDGER_REPLAY points to a file; never committed with data.
final class ReplayTests: XCTestCase {
    func testReplayDeviceEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["LEDGER_REPLAY"] else { throw XCTSkip("no replay file") }
        let old = try JSONDecoder.ledger.decode(LedgerState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let e = LedgerEngine(defaultCurrency: "INR")
        var rejected: [String: Int] = [:]
        for ev in old.evidence.values.sorted(by: { $0.receivedAt < $1.receivedAt }) where ev.sourceType == .emailAlert {
            guard let text = ev.rawText else { continue }
            let focused = EmailAlertExtractor.isTransactional(text) ? text : nil
            guard let focused else { rejected["gate", default: 0] += 1; continue }
            if case let .notFinancial(r) = e.ingestMessage(focused, source: .emailAlert, receivedAt: ev.receivedAt, merchantHint: ev.sourceIdentifier) { rejected[r, default: 0] += 1 }
        }
        e.refreshRecurring()
        let txs = Array(e.state.transactions.values)
        let cats = Dictionary(grouping: txs, by: \.categoryID).mapValues(\.count).sorted { $0.value > $1.value }
        print("REPLAY old=\(old.transactions.count) new=\(txs.count) rejected=\(rejected)")
        print("REPLAY categories:", cats.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        for tx in txs.sorted(by: { $0.categoryID < $1.categoryID }) where ["other.unknown", "shopping.local"].contains(tx.categoryID) || tx.flowType != .purchase {
            print("REPLAY \(tx.categoryID) | \(tx.flowType.rawValue) | \(tx.displayMerchant) | \(tx.amount) \(tx.currencyCode) \(tx.direction.rawValue)")
        }
    }
}

extension JSONDecoder {
    static var ledger: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}
