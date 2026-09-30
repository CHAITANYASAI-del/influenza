import XCTest
@testable import LedgerCore

final class EmailTests: XCTestCase {
    func testFooterDoesNotVetoAlert() throws {
        let html = """
        <html><body><p>Dear Customer,</p>
        <p>Thank you for using your HDFC Bank Credit Card ending 4321 for Rs 1,299.00 at AMAZON on 12-09-2026 14:10:22.</p>
        <p>Never share your OTP, PIN or CVV with anyone. HDFC Bank never asks for these.</p>
        <p>Get a pre-approved personal loan offer! Apply now.</p></body></html>
        """
        let body = EmailAlertExtractor.plainText(fromHTML: html)
        let focused = try XCTUnwrap(EmailAlertExtractor.focus(subject: "Alert : Update on your HDFC Bank Credit Card", body: body))
        guard case let .financial(p) = FinancialMessageParser.parse(focused, defaultCurrency: "INR") else { return XCTFail(focused) }
        XCTAssertEqual(p.money.amount, 1299)
        XCTAssertEqual(MerchantResolver.resolve(p.merchantRaw)?.name, "Amazon")
    }

    func testMerchantOrderEmailUsesSenderAndMergesWithBankAlert() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("Sent Rs.452.00 From HDFC Bank A/C *1234 To SWIGGY On 03/09/26 Ref 426912345678", receivedAt: day("2026-09-03", "20:01"))
        let focused = try XCTUnwrap(EmailAlertExtractor.focus(subject: "Your order is confirmed", body: "Order #88231 from Meghana Foods. Total paid ₹452.00 via UPI. Enjoy your meal!"))
        e.ingestMessage(focused, source: .emailAlert, receivedAt: day("2026-09-03", "20:00"), merchantHint: "Swiggy")
        XCTAssertEqual(e.liveTransactions.count, 1)
        XCTAssertEqual(e.liveTransactions[0].merchantName, "Swiggy")
    }

    func testNonTransactionalEmailIgnored() {
        XCTAssertNil(EmailAlertExtractor.focus(subject: "Your statement is ready", body: "Your e-statement for August is attached. Log in to view."))
        let promo = EmailAlertExtractor.focus(subject: "Big sale", body: "Flat 50% off! Get cashback of Rs 500 on your first order. Offer valid till Sunday.")
        if let promo, case .financial = FinancialMessageParser.parse(promo, defaultCurrency: "INR") { XCTFail("promo parsed as transaction") }
    }
}
