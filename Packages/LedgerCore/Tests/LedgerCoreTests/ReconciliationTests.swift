import XCTest
@testable import LedgerCore

/// Spec §76 — the eight mandatory reconciliation tests, plus §139 currency isolation.
final class ReconciliationTests: XCTestCase {

    // Test 1 — Same purchase, two sources (card alert + bank statement).
    func testSamePurchaseTwoSources() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("Rs.1,299.00 spent on your ICICI Bank Credit Card XX4321 at AMAZON on 12-Sep-26.", receivedAt: day("2026-09-12", "14:10"))
        try e.importStatement(text: csv(["12/09/2026,AMAZON PAY INDIA PVT LTD,-1299.00"]), fileName: "card.csv")
        XCTAssertEqual(e.liveTransactions.count, 1)
        XCTAssertEqual(e.spent("INR"), 1299)
        XCTAssertEqual(e.liveTransactions.first?.verificationStatus, .verified)
    }

    // Test 2 — Internal transfer / credit-card payment.
    func testInternalTransferNotSpending() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("Rs 50,000.00 debited from HDFC Bank A/c XX1111 towards ICICI Credit Card payment on 05-09-26", receivedAt: day("2026-09-05", "09:00"))
        e.ingestMessage("Payment of Rs 50,000.00 received on your ICICI Bank Credit Card XX4321. Thank you.", receivedAt: day("2026-09-05", "11:00"))
        XCTAssertEqual(e.spent("INR"), 0)
        let txs = e.liveTransactions
        XCTAssertEqual(txs.count, 2)
        XCTAssertTrue(txs.allSatisfy { $0.isCreditCardPayment && $0.isInternalTransfer })
        XCTAssertEqual(Set(txs.flatMap(\.linkedTransactionIDs)), Set(txs.map(\.id)))
    }

    // Test 3 — Refund nets to zero.
    func testRefundNetsToZero() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        try e.importStatement(text: csv([
            "01/09/2026,AMAZON INDIA,-500.00",
            "15/09/2026,REFUND AMAZON INDIA,500.00",
        ]), fileName: "bank.csv")
        XCTAssertEqual(e.spent("INR"), 0)
        let refund = try XCTUnwrap(e.liveTransactions.first { $0.isRefund })
        XCTAssertEqual(refund.refundLinkIDs.count, 1)
        XCTAssertEqual(e.liveTransactions.count, 2, "refund record is never deleted")
    }

    // Test 4 — Pending then posted = one transaction.
    func testPendingPosted() {
        let e = LedgerEngine(defaultCurrency: "USD")
        e.ingestMessage("Chase: A pending charge of $42.18 at DOORDASH on card ending 1234 was authorized.", receivedAt: day("2026-09-20", "19:00"))
        e.ingestWalletEvent(merchant: "DoorDash", amountText: "$42.18", date: day("2026-09-21", "08:00"))
        XCTAssertEqual(e.liveTransactions.count, 1)
        XCTAssertFalse(e.liveTransactions[0].isPending)
    }

    // Test 5 — SMS + authoritative record → one verified transaction with ≥2 evidence.
    func testAlertPlusStatementVerified() throws {
        let e = LedgerEngine(defaultCurrency: "USD")
        e.ingestMessage("You made a $42.18 transaction with DOORDASH on your card ending 1234.", receivedAt: day("2026-09-20", "20:00"))
        try e.importStatement(text: csv(["09/20/2026,DD *DOORDASH CHIPOTLE,-42.18"]), fileName: "chase.csv")
        XCTAssertEqual(e.liveTransactions.count, 1)
        let tx = e.liveTransactions[0]
        XCTAssertGreaterThanOrEqual(tx.observationIDs.count, 2)
        XCTAssertEqual(tx.verificationStatus, .verified)
        XCTAssertEqual(tx.merchantName, "DoorDash")
        XCTAssertEqual(tx.categoryID, "food.delivery")
    }

    // Test 6 — Equal amounts, different merchants stay separate.
    func testEqualAmountsDifferentMerchants() throws {
        let e = LedgerEngine(defaultCurrency: "USD")
        e.ingestMessage("You made a $50.00 transaction with AMAZON on your card ending 1234.", receivedAt: day("2026-09-10"))
        try e.importStatement(text: csv(["09/10/2026,TARGET 00012345,-50.00"]), fileName: "b.csv")
        XCTAssertEqual(e.liveTransactions.count, 2)
        XCTAssertEqual(e.spent("USD"), 100)
    }

    // Test 7 — ATM is a withdrawal, not spending.
    func testATMNotSpending() {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("Rs.5000.00 withdrawn at ATM from A/c XX1111 on 10-09-26. Avl bal Rs 20,000", receivedAt: day("2026-09-10"))
        XCTAssertEqual(e.liveTransactions.first?.flowType, .withdrawal)
        XCTAssertEqual(e.spent("INR"), 0)
        XCTAssertEqual(e.summaries(from: day("2026-09-01"), to: day("2026-10-01"))["INR"]?.withdrew, 5000)
    }

    // Test 8 — Double import is idempotent, but identical real rows are kept.
    func testDoubleImportIdempotent() throws {
        let e = LedgerEngine(defaultCurrency: "USD")
        let file = csv([
            "09/01/2026,STARBUCKS 123,-5.00",
            "09/01/2026,STARBUCKS 123,-5.00",   // two genuine coffees
            "09/02/2026,UBER *TRIP,-18.40",
        ])
        let first = try e.importStatement(text: file, fileName: "s.csv")
        XCTAssertEqual(first.newTransactions, 3)
        let second = try e.importStatement(text: file, fileName: "s.csv")
        XCTAssertEqual(second.newTransactions, 0)
        XCTAssertEqual(second.duplicatesSkipped, 3)
        XCTAssertEqual(e.liveTransactions.count, 3)
        // Same SMS pasted twice.
        e.ingestMessage("You paid £4.50 at Pret A Manger using your card ending 1234", receivedAt: day("2026-09-03"))
        let again = e.ingestMessage("You paid £4.50 at Pret A Manger using your card ending 1234", receivedAt: day("2026-09-03"))
        guard case .duplicate = again else { return XCTFail("expected duplicate") }
    }

    // §139 — currencies are never summed.
    func testCurrencyIsolation() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.addManual(amount: 1000, currency: "INR", merchant: "Chai", categoryID: nil, date: day("2026-09-05"))
        e.addManual(amount: 1000, currency: "USD", merchant: "Coffee", categoryID: nil, date: day("2026-09-05"))
        let s = e.summaries(from: day("2026-09-01"), to: day("2026-10-01"))
        XCTAssertEqual(s["INR"]?.spent, 1000)
        XCTAssertEqual(s["USD"]?.spent, 1000)
        XCTAssertEqual(s.count, 2)
    }

    // Spec §100 — UPI SMS with unknown merchant + statement with merchant, joined by UPI reference.
    func testUPIReferenceMerge() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("HDFC Bank: A/c XX1234 debited by INR 1,299.00 for UPI transaction. UPI Ref No 426912345678", receivedAt: day("2026-09-12", "10:00"))
        try e.importStatement(text: csv(["12/09/2026,UPI/P2M/426912345678/AMAZON,-1299.00"]), fileName: "hdfc.csv")
        XCTAssertEqual(e.liveTransactions.count, 1)
        XCTAssertEqual(e.liveTransactions[0].merchantName, "Amazon")
        XCTAssertEqual(e.liveTransactions[0].verificationStatus, .verified)
    }

    // Ambiguous: same amount, unknown merchant, no reference → review, not a silent merge.
    func testAmbiguousGoesToReview() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("Rs 850.00 debited from A/c XX1234 via UPI on 14-09-26", receivedAt: day("2026-09-14", "13:00"))
        let job = try e.importStatement(text: csv(["14/09/2026,UPI/P2M/SOMESHOP,-850.00"]), fileName: "x.csv")
        XCTAssertEqual(job.needsReview, 1)
        XCTAssertEqual(e.reviewItems.count, 1)
        let item = try XCTUnwrap(e.reviewItems.first)
        e.resolveReview(item.id, merge: true)
        XCTAssertEqual(e.liveTransactions.count, 1)
        XCTAssertEqual(e.spent("INR"), 850)
    }

    func testCashIsNeverMerged() {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.addManual(amount: 50, currency: "INR", merchant: "Chai", categoryID: "food.coffee", date: day("2026-09-14", "09:00"))
        e.ingestWalletEvent(merchant: "Chai Point", amountText: "₹50", date: day("2026-09-14", "09:05"))
        XCTAssertEqual(e.liveTransactions.count, 2)
    }
}
