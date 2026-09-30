import XCTest
@testable import LedgerCore

/// Spec §77 — marketplaces are categorized by what was bought, not by name.
final class CategorizationTests: XCTestCase {
    private func receipt(_ merchant: String, _ items: [String], total: String) -> String {
        ([merchant] + items.map { "\($0) 10.00" } + ["Total \(total)"]).joined(separator: "\n")
    }

    private func category(_ e: LedgerEngine, _ o: IngestOutcome) -> String? { e.tx(o)?.categoryID }

    func testAmazonByItems() {
        let e = LedgerEngine(defaultCurrency: "USD")
        XCTAssertEqual(category(e, e.ingestReceipt(receipt("Amazon.com", ["Apple MacBook Pro 14"], total: "$1999.00"), date: day("2026-09-01"))), "shopping.electronics")
        XCTAssertEqual(category(e, e.ingestReceipt(receipt("Amazon.com", ["Atomic Habits paperback book"], total: "$18.00"), date: day("2026-09-02"))), "shopping.books")
        XCTAssertEqual(category(e, e.ingestReceipt(receipt("Amazon.com", ["Tide Laundry Detergent", "Dove Soap 4 pack"], total: "$24.00"), date: day("2026-09-03"))), "shopping.personalCare")
    }

    func testWalmartByItems() {
        let e = LedgerEngine(defaultCurrency: "USD")
        XCTAssertEqual(category(e, e.ingestReceipt(receipt("WALMART", ["Great Value Milk", "Large Eggs 12ct", "Fresh Vegetables"], total: "$21.00"), date: day("2026-09-04"))), "food.groceries")
        XCTAssertEqual(category(e, e.ingestReceipt(receipt("WALMART", ["Sony Headphones WH-CH520"], total: "$48.00"), date: day("2026-09-05"))), "shopping.electronics")
    }

    func testMixedBasketStaysGeneral() {
        let e = LedgerEngine(defaultCurrency: "USD")
        let o = e.ingestReceipt(receipt("TARGET", ["Milk", "Eggs", "Detergent", "Headphones", "Towel"], total: "$84.42"), date: day("2026-09-06"))
        XCTAssertEqual(category(e, o), "shopping.general")
    }

    func testMarketplaceWithoutReceiptIsLowConfidence() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        let o = e.ingestMessage("₹21,999 paid to Flipkart via UPI. UPI Ref: 426900009999", receivedAt: day("2026-09-07"))
        let tx = try XCTUnwrap(e.tx(o))
        XCTAssertEqual(tx.categoryID, "shopping.marketplace")
        XCTAssertLessThan(tx.categoryConfidence, 0.7)
    }

    func testUberVsUberEats() {
        let e = LedgerEngine(defaultCurrency: "USD")
        XCTAssertEqual(category(e, e.ingestWalletEvent(merchant: "Uber", amountText: "$18.40", date: day("2026-09-08"))), "transport.rideHailing")
        XCTAssertEqual(category(e, e.ingestWalletEvent(merchant: "Uber Eats", amountText: "$31.10", date: day("2026-09-09"))), "food.delivery")
    }

    func testReceiptEnrichesBankTransaction() throws {
        let e = LedgerEngine(defaultCurrency: "USD")
        try e.importStatement(text: csv(["09/20/2026,DOORDASH*ORDER,-42.18"]), fileName: "c.csv")
        let o = e.ingestReceipt("DoorDash\nRestaurant: Chipotle\nBurrito Bowl 28.00\nFees 6.00\nTip 8.18\nTotal $42.18", date: day("2026-09-20", "21:00"))
        guard case .merged = o else { return XCTFail("receipt should enrich, got \(o)") }
        let tx = try XCTUnwrap(e.liveTransactions.first)
        XCTAssertEqual(e.liveTransactions.count, 1)
        XCTAssertEqual(tx.merchantDetail, "Chipotle")
        XCTAssertEqual(tx.amount, Decimal(string: "42.18"), "receipt never overrides the bank amount")
        XCTAssertEqual(tx.categoryID, "food.delivery")
    }

    func testUserRuleAppliesEverywhere() throws {
        let e = LedgerEngine(defaultCurrency: "USD")
        let a = try XCTUnwrap(e.ingestWalletEvent(merchant: "Ralphs #102", amountText: "$30", date: day("2026-09-01")).transactionID)
        e.ingestWalletEvent(merchant: "RALPHS #88", amountText: "$12", date: day("2026-09-05"))
        e.setCategory(a, to: "food.groceries", alwaysForMerchant: true)
        XCTAssertTrue(e.liveTransactions.allSatisfy { $0.categoryID == "food.groceries" })
        let later = e.ingestWalletEvent(merchant: "Ralphs", amountText: "$9", date: day("2026-09-09"))
        XCTAssertEqual(e.tx(later)?.categoryID, "food.groceries")
    }

    /// Category accuracy over a labelled merchant set (spec §47).
    func testCategoryAccuracy() {
        let labelled: [(String, String)] = [
            ("SWIGGY", "food.delivery"), ("ZOMATO LTD", "food.delivery"), ("BLINKIT", "food.groceries"), ("ZEPTO MARKETPLACE", "food.groceries"),
            ("SWIGGY INSTAMART", "food.groceries"), ("BIGBASKET", "food.groceries"), ("UBER INDIA", "transport.rideHailing"), ("OLA CABS", "transport.rideHailing"),
            ("RAPIDO", "transport.rideHailing"), ("MYNTRA", "shopping.clothing"), ("NYKAA", "shopping.beauty"), ("AJIO", "shopping.clothing"),
            ("NETFLIX", "entertainment.streaming"), ("SPOTIFY", "entertainment.music"), ("YOUTUBE PREMIUM", "entertainment.streaming"),
            ("AMAZON PRIME", "entertainment.streaming"), ("DOORDASH", "food.delivery"), ("UBER EATS", "food.delivery"), ("GRUBHUB", "food.delivery"),
            ("INSTACART", "food.groceries"), ("LYFT", "transport.rideHailing"), ("RALPHS", "food.groceries"), ("KROGER", "food.groceries"),
            ("STARBUCKS", "food.coffee"), ("SHELL OIL 123", "transport.fuel"), ("HP PETROL PUMP", "transport.fuel"), ("APOLLO PHARMACY", "health.pharmacy"),
            ("CVS PHARMACY", "health.pharmacy"), ("AIRTEL PREPAID", "bills.mobile"), ("BESCOM ELECTRICITY", "bills.electricity"), ("BOOKMYSHOW", "entertainment.movies"),
            ("IRCTC", "transport.publicTransit"), ("INDIGO", "transport.flights"), ("AIRBNB", "transport.hotels"), ("CULT FIT", "health.fitness"),
            ("SHARMA KIRANA STORE", "food.groceries"), ("CAFE COFFEE DAY", "food.coffee"), ("PARADISE BIRYANI", "food.restaurant"), ("FASTAG TOLL", "transport.tolls"),
            ("ACT FIBERNET", "bills.internet"),
        ]
        var correct = 0
        var misses: [String] = []
        for (raw, expected) in labelled {
            let name = MerchantResolver.resolve(raw)?.name ?? MerchantResolver.cleanDisplayName(raw)
            let d = CategorizationEngine.categorize(merchantRaw: raw, merchantName: name, flow: .purchase, type: .purchase, items: [], userRules: [:])
            if d.categoryID == expected { correct += 1 } else { misses.append("\(raw): \(d.categoryID) ≠ \(expected)") }
        }
        let accuracy = Double(correct) / Double(labelled.count)
        print("CATEGORY ACCURACY: \(correct)/\(labelled.count) = \(Int(accuracy * 100))%")
        XCTAssertGreaterThanOrEqual(accuracy, 0.95, misses.joined(separator: "\n"))
    }
}
