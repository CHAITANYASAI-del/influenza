import XCTest
@testable import LedgerCore

final class MonthlyTests: XCTestCase {
    func testMonthlySeriesSeparatesMonths() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        try e.importStatement(text: csv([
            "05/07/2026,SWIGGY,-300.00", "20/07/2026,ZOMATO,-200.00", "05/08/2026,SWIGGY,-450.00", "03/09/2026,UBER INDIA,-120.00",
            "10/09/2026,CC PAYMENT ICICI CREDIT CARD,-5000.00",
        ]), fileName: "m.csv")
        let series = e.monthlySpending(currency: "INR", months: 3, endingAt: day("2026-09-15"))
        XCTAssertEqual(series.map(\.spent), [500, 450, 120], "card payment excluded; each month separate")
        let food = e.monthlySpending(currency: "INR", months: 3, endingAt: day("2026-09-15")) { CategoryTree.node($0.categoryID)?.topLevelID == "food" }
        XCTAssertEqual(food.map(\.spent), [500, 450, 0])
    }
}
