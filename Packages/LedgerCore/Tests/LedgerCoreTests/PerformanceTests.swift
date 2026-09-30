import XCTest
@testable import LedgerCore

final class PerformanceTests: XCTestCase {
    private func statement(_ n: Int) -> String {
        let merchants = ["SWIGGY", "ZOMATO", "UBER INDIA", "AMAZON PAY", "BIGBASKET", "NETFLIX.COM", "SHELL OIL", "STARBUCKS", "BLINKIT", "MYNTRA"]
        var rows = ["Date,Description,Amount"]
        let start = day("2024-01-01").timeIntervalSince1970
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.locale = Locale(identifier: "en_US_POSIX")
        for i in 0..<n {
            let d = Date(timeIntervalSince1970: start + Double(i) * 3_000)
            rows.append("\(f.string(from: d)),\(merchants[i % merchants.count]) \(i % 97),-\(100 + (i * 37) % 4900).\(i % 100 < 10 ? "0" : "")\(i % 100)")
        }
        return rows.joined(separator: "\n")
    }

    func testImport10k() throws {
        for n in [10_000, 50_000] {
            let e = LedgerEngine(defaultCurrency: "INR")
            let t0 = Date()
            let job = try e.importStatement(text: statement(n), fileName: "perf.csv")
            let importTime = Date().timeIntervalSince(t0)
            let t1 = Date()
            _ = e.summaries(from: day("2024-01-01"), to: day("2030-01-01"))
            let aggTime = Date().timeIntervalSince(t1)
            let t2 = Date()
            let again = try e.importStatement(text: statement(n), fileName: "perf.csv")
            let reimport = Date().timeIntervalSince(t2)
            print("PERF \(n): import \(String(format: "%.2f", importTime))s, aggregate \(String(format: "%.3f", aggTime))s, re-import \(String(format: "%.2f", reimport))s, tx=\(e.state.transactions.count)")
            XCTAssertEqual(job.newTransactions + job.needsReview, n)
            XCTAssertEqual(again.newTransactions, 0)
        }
    }
}
