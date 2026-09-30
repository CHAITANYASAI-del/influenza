import XCTest
@testable import LedgerCore

final class StatementTests: XCTestCase {
    func testIndianBankCSVWithPreambleAndDebitCreditColumns() throws {
        let file = """
        HDFC BANK Ltd.
        Statement of account for XXXXXX1234
        Period: 01/09/2026 to 30/09/2026

        Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
        01/09/26,SALARY SEP ACME CORP,NEFT123456,01/09/26,,"1,50,000.00","1,70,000.00"
        03/09/26,UPI-SWIGGY-swiggy@icici-426912345678,426912345678,03/09/26,452.00,,"1,69,548.00"
        05/09/26,ATM WDL MG ROAD,000123,05/09/26,"5,000.00",,"1,64,548.00"
        07/09/26,CC PAYMENT ICICI CREDIT CARD,IB12345,07/09/26,"25,000.00",,"1,39,548.00"
        """
        let e = LedgerEngine(defaultCurrency: "INR")
        let job = try e.importStatement(text: file, fileName: "hdfc.csv")
        XCTAssertEqual(job.recordsSeen, 4)
        let s = try XCTUnwrap(e.summaries(from: day("2026-09-01", "00:00"), to: day("2026-10-01", "00:00"))["INR"])
        XCTAssertEqual(s.spent, 452)
        XCTAssertEqual(s.received, 150000)
        XCTAssertEqual(s.withdrew, 5000)
        XCTAssertEqual(s.moved, 25000)
        XCTAssertEqual(e.liveTransactions.first { $0.amount == 452 }?.merchantName, "Swiggy")
    }

    func testSemicolonEuropeanCSV() throws {
        let file = "Datum;Beschreibung;Betrag\n01.09.2026;REWE Markt Berlin;-12,50\n02.09.2026;Gehalt;2.500,00"
        let e = LedgerEngine(defaultCurrency: "EUR")
        _ = try? e.importStatement(text: file, fileName: "de.csv")
        // German headers aren't in the vocabulary yet → clear error rather than garbage.
        XCTAssertTrue(e.liveTransactions.isEmpty)
        let english = "Date;Description;Amount\n01.09.2026;REWE Markt Berlin;-12,50\n02.09.2026;Salary;2.500,00"
        try e.importStatement(text: english, fileName: "de.csv")
        XCTAssertEqual(e.spent("EUR"), Decimal(string: "12.5"))
    }

    func testAmexPositivePurchases() throws {
        let file = csv([
            "09/03/2026,WHOLE FOODS MARKET,56.20",
            "09/05/2026,NETFLIX.COM,15.99",
            "09/10/2026,AUTOPAY PAYMENT - THANK YOU,-500.00",
        ])
        let e = LedgerEngine(defaultCurrency: "USD")
        try e.importStatement(text: file, fileName: "amex.csv")
        XCTAssertEqual(e.spent("USD"), Decimal(string: "72.19"))
    }

    func testOFX() throws {
        let ofx = """
        OFXHEADER:100
        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>USD<BANKACCTFROM><ACCTID>123456789</BANKACCTFROM>
        <BANKTRANLIST>
        <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260915120000<TRNAMT>-42.18<FITID>A1<NAME>DOORDASH*CHIPOTLE</STMTTRN>
        <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260916120000<TRNAMT>-15.99<FITID>A2<NAME>NETFLIX.COM</STMTTRN>
        <STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20260917120000<TRNAMT>3200.00<FITID>A3<NAME>PAYROLL ACME</STMTTRN>
        </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """
        let e = LedgerEngine(defaultCurrency: "USD")
        let job = try e.importStatement(text: ofx, fileName: "chase.qfx")
        XCTAssertEqual(job.newTransactions, 3)
        XCTAssertEqual(e.spent("USD"), Decimal(string: "58.17"))
        let again = try e.importStatement(text: ofx.replacingOccurrences(of: "OFXHEADER:100", with: "OFXHEADER:100 "), fileName: "chase2.qfx")
        XCTAssertEqual(again.newTransactions, 0, "FITID makes re-import idempotent even for a different file")
    }

    func testPDFTextStatement() throws {
        let text = """
        ICICI Bank Credit Card Statement
        Date        Transaction Details                 Amount
        02/09/2026  SWIGGY BANGALORE                     452.00
        04/09/2026  AMAZON PAY INDIA                   1,299.00
        08/09/2026  PAYMENT RECEIVED - THANK YOU      25,000.00 Cr
        12/09/2026  UBER INDIA SYSTEMS                   318.50
        """
        let e = LedgerEngine(defaultCurrency: "INR")
        let job = try e.importStatement(text: text, fileName: "icici.pdf", format: .pdfText)
        XCTAssertEqual(job.recordsSeen, 4)
        XCTAssertEqual(e.spent("INR"), Decimal(string: "2069.5"))
    }
}

final class RecurringTests: XCTestCase {
    func testMonthlySubscription() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        try e.importStatement(text: csv([
            "05/06/2026,NETFLIX.COM,-649.00", "05/07/2026,NETFLIX.COM,-649.00", "05/08/2026,NETFLIX.COM,-649.00", "05/09/2026,NETFLIX.COM,-649.00",
            "07/09/2026,SWIGGY,-300.00", "19/09/2026,SWIGGY,-410.00",
        ]), fileName: "r.csv")
        e.refreshRecurring(now: day("2026-09-20"))
        let netflix = try XCTUnwrap(e.state.recurring.first { $0.merchantName == "Netflix" })
        XCTAssertEqual(netflix.cadence, .monthly)
        XCTAssertEqual(netflix.kind, .fixedRecurring)
        XCTAssertEqual(Calendar.current.component(.month, from: netflix.nextExpectedDate), 10)
        XCTAssertNil(e.state.recurring.first { $0.merchantName == "Swiggy" })
    }
}
