import XCTest
@testable import LedgerCore

/// India & US alert corpus with varied wording (spec §74–75). Each fixture
/// states the expected amount, currency, direction, type and merchant.
final class ParserTests: XCTestCase {
    struct Fixture { let text: String; let amount: Decimal; let currency: String; let direction: Direction; let type: ObservationTransactionType; let merchant: String? }

    static let india: [Fixture] = [
        .init(text: "Rs.1,250.00 spent on HDFC Bank Card x1234 at AMAZON PAY INDIA on 2026-09-27:10:15:32. Avl Lmt: Rs 45,000", amount: 1250, currency: "INR", direction: .debit, type: .purchase, merchant: "Amazon"),
        .init(text: "Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 27/09/26 Ref 426912345678 Not You? Call 18002586161", amount: 250, currency: "INR", direction: .debit, type: .purchase, merchant: "Swiggy"),
        .init(text: "Dear UPI user A/C X1234 debited by 150.0 on date 27Sep26 trf to ZOMATO Refno 426998765432. If not u? call 1800111109. -SBI", amount: 150, currency: "INR", direction: .debit, type: .purchase, merchant: "Zomato"),
        .init(text: "ICICI Bank Acct XX123 debited for Rs 499.00 on 27-Sep-26; NETFLIX credited. UPI:426912345678. Call 18002662 for dispute.", amount: 499, currency: "INR", direction: .debit, type: .purchase, merchant: "Netflix"),
        .init(text: "INR 820.00 debited A/c no. XX1234 27-09-26, 14:02:11 UPI/P2M/426912345678/UBER INDIA Not you? SMS BLOCKUPI", amount: 820, currency: "INR", direction: .debit, type: .purchase, merchant: "Uber"),
        .init(text: "₹1,299 paid to Flipkart via UPI from Kotak A/c X1234. UPI Ref: 426912345111", amount: 1299, currency: "INR", direction: .debit, type: .purchase, merchant: "Flipkart"),
        .init(text: "Your A/c XX5678 is debited with INR 3,000.00 on 20-09-26 by IMPS to RAHUL SHARMA. IMPS Ref 426900001111", amount: 3000, currency: "INR", direction: .debit, type: .transferOut, merchant: nil),
        .init(text: "Rs.5000.00 withdrawn at ATM from A/c XX1111 on 10-09-26. Avl bal Rs 20,000", amount: 5000, currency: "INR", direction: .debit, type: .withdrawal, merchant: nil),
        .init(text: "Your a/c XX1111 is credited with INR 1,50,000.00 on 01-09-26 towards SALARY ACME CORP", amount: 150000, currency: "INR", direction: .credit, type: .salary, merchant: nil),
        .init(text: "Refund of Rs 500.00 from AMAZON has been credited to your A/c XX1111", amount: 500, currency: "INR", direction: .credit, type: .refund, merchant: "Amazon"),
        .init(text: "Rs 2,360.00 debited from A/c XX1111 on 01-09-26 for NEFT to SELF ICICI account", amount: 2360, currency: "INR", direction: .debit, type: .internalTransfer, merchant: nil),
        .init(text: "Annual fee of Rs 590.00 incl GST charged to your SBI Card ending 4455", amount: 590, currency: "INR", direction: .debit, type: .fee, merchant: nil),
        .init(text: "INR 1,23,456.00 spent at MAKEMYTRIP on your ICICI Card XX9876", amount: 123456, currency: "INR", direction: .debit, type: .purchase, merchant: "MakeMyTrip"),
        .init(text: "Axis Bank: Rs 180 debited from A/c XX7788 for UPI txn to RAPIDO on 21-09-26. UPI Ref 426911223344", amount: 180, currency: "INR", direction: .debit, type: .purchase, merchant: "Rapido"),
    ]

    static let us: [Fixture] = [
        .init(text: "Chase: You made a $12.45 transaction with STARBUCKS STORE 123 on your Sapphire card ending in 1234.", amount: 12.45, currency: "USD", direction: .debit, type: .purchase, merchant: "Starbucks"),
        .init(text: "American Express: A charge of $56.20 at WHOLE FOODS MARKET was made on your Card ending 12345.", amount: 56.20, currency: "USD", direction: .debit, type: .purchase, merchant: "Whole Foods"),
        .init(text: "BofA: Debit card purchase of $84.42 at WALMART SUPERCENTER on 09/21. Card ending 5566", amount: 84.42, currency: "USD", direction: .debit, type: .purchase, merchant: "Walmart"),
        .init(text: "Wells Fargo: Card ending 7788 used for $23.10 at LYFT RIDE on 09/22", amount: 23.10, currency: "USD", direction: .debit, type: .purchase, merchant: "Lyft"),
        .init(text: "Capital One: A purchase of $15.99 was made at NETFLIX.COM on your card ending 3344", amount: 15.99, currency: "USD", direction: .debit, type: .purchase, merchant: "Netflix"),
        .init(text: "You sent a Zelle payment to Alex Kim for $40.00. Zelle payment to Alex Kim", amount: 40, currency: "USD", direction: .debit, type: .transferOut, merchant: nil),
        .init(text: "Chase: ATM withdrawal of $200.00 from checking ending 9911", amount: 200, currency: "USD", direction: .debit, type: .withdrawal, merchant: nil),
        .init(text: "Discover: Your payment of $1,250.00 has posted to your card ending 4444. Thank you for your payment", amount: 1250, currency: "USD", direction: .credit, type: .creditCardPayment, merchant: nil),
        .init(text: "Direct deposit of $3,200.00 PAYROLL ACME INC credited to checking ending 9911", amount: 3200, currency: "USD", direction: .credit, type: .salary, merchant: nil),
        .init(text: "Citi: A refund of $19.99 from TARGET was credited to your card ending 1212", amount: 19.99, currency: "USD", direction: .credit, type: .refund, merchant: "Target"),
    ]

    static let rejected: [String] = [
        "123456 is your OTP for txn of Rs 500 at AMAZON. Do not share it with anyone.",
        "Your HDFC Card bill of Rs 12,000 is due on 05-Oct. Minimum amount due Rs 600",
        "Rs 5000 will be debited from your account on 05-Oct towards SIP",
        "Get a pre-approved loan of Rs 5,00,000! Apply now",
        "Your Chase verification code is 482913. Don't share it.",
        "Transaction of $42.18 at DOORDASH was declined on card ending 1234",
        "PAYTM: Rahul has requested money Rs 300 via collect request",
    ]

    func testCorpus() {
        var failures: [String] = []
        for f in Self.india + Self.us {
            let currency = Self.india.contains(where: { $0.text == f.text }) ? "INR" : "USD"
            guard case let .financial(p) = FinancialMessageParser.parse(f.text, defaultCurrency: currency) else {
                failures.append("NOT PARSED: \(f.text)"); continue
            }
            var errs: [String] = []
            if p.money.amount.stableString != f.amount.stableString { errs.append("amount \(p.money.amount)≠\(f.amount)") }
            if p.money.currencyCode != f.currency { errs.append("currency \(p.money.currencyCode)") }
            if p.direction != f.direction { errs.append("direction \(p.direction)") }
            if p.type != f.type { errs.append("type \(p.type)≠\(f.type)") }
            if let m = f.merchant, MerchantResolver.resolve(p.merchantRaw)?.name != m { errs.append("merchant \(p.merchantRaw ?? "nil")≠\(m)") }
            if !errs.isEmpty { failures.append("\(errs.joined(separator: ", ")) ← \(f.text.prefix(60))") }
        }
        let total = Self.india.count + Self.us.count
        let accuracy = Double(total - failures.count) / Double(total)
        print("PARSER ACCURACY: \(total - failures.count)/\(total) = \(Int(accuracy * 100))%")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testRejections() {
        for text in Self.rejected {
            if case .financial = FinancialMessageParser.parse(text, defaultCurrency: "INR") { XCTFail("should reject: \(text)") }
        }
    }

    func testMessyMerchantStrings() {
        let cases: [(String, String)] = [
            ("Amazon*1234", "Amazon"), ("AMZN MKTP US*123", "Amazon"), ("AMAZON INDIA PAYMENTS", "Amazon"), ("UPI-AMAZON-AB1234", "Amazon"),
            ("AMAZON MKTPLACE", "Amazon"), ("DOORDASH*1234", "DoorDash"), ("DoorDash.com", "DoorDash"), ("DD*ORDER123", "DoorDash"),
            ("UBER *TRIP", "Uber"), ("UBER BV", "Uber"), ("UBER.COM", "Uber"), ("UBER INDIA", "Uber"), ("UBER EATS", "Uber Eats"),
            ("WHOLEFDS MKT #102", "Whole Foods"), ("WHOLE FOODS 102", "Whole Foods"),
        ]
        for (raw, expected) in cases { XCTAssertEqual(MerchantResolver.resolve(raw)?.name, expected, raw) }
    }

    func testAmountFormats() {
        XCTAssertEqual(AmountParser.number("1,23,456.00"), 123456)
        XCTAssertEqual(AmountParser.number("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(AmountParser.number("12,50"), 12.5)
        XCTAssertEqual(AmountParser.number("(42.18)"), -42.18)
        XCTAssertEqual(AmountParser.number("1'234.50"), 1234.5)
    }
}
