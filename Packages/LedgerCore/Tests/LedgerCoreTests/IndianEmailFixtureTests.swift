import XCTest
@testable import LedgerCore

/// Real-world Indian bank/card email formats (Kotak, HDFC, AU, CRED, merchants),
/// anonymized: names, account numbers and references changed.
final class IndianEmailFixtureTests: XCTestCase {
    private func parse(_ subject: String, _ body: String) -> ParsedFinancialText? {
        guard let f = EmailAlertExtractor.focus(subject: subject, body: body),
              case let .financial(p) = FinancialMessageParser.parse(f, defaultCurrency: "INR") else { return nil }
        return p
    }
    private func merchant(_ p: ParsedFinancialText?) -> String? { MerchantResolver.resolve(p?.merchantRaw)?.name ?? p?.merchantRaw }

    func testKotakUPIIgnoresEmailerBoilerplate() throws {
        let p = try XCTUnwrap(parse("Payment of INR 334.65 successful", "If you are unable to view the below e-mailer, please click here . Dear customer, You have successfully made a UPI payment of INR 334.65 towards Zomatofood through the Kotak811 App."))
        XCTAssertEqual(merchant(p), "Zomato")
        XCTAssertEqual(p.type, .purchase)
    }

    func testAUCardUPIMerchantsKeepFullName() throws {
        let a = try XCTUnwrap(parse("AU Bank Credit Card Transaction Alert", "Dear Customer, Namaskar! INR 239.00 were spent on your AU Bank Credit Card xx1111 at UPI/RATNADEEP_SUPERMAR on 26-09-2026 at 08:15:11 am."))
        XCTAssertEqual(merchant(a), "Ratnadeep")
        let b = try XCTUnwrap(parse("AU Bank Credit Card Transaction Alert", "Dear Customer, Namaskar! INR 600.00 were spent on your AU Bank Credit Card xx1111 at UPI/SOORYA HOSPITALS on 23-09-2026 at 12:34:04 pm."))
        XCTAssertEqual(b.merchantRaw, "SOORYA HOSPITALS")
        let c = try XCTUnwrap(parse("AU Bank Credit Card Transaction Alert", "Dear Customer, INR 105.60 were spent on your AU Bank Credit Card xx1111 at WALMART+ MEMBER 2026 on 19-02-2026 at 07:34:08 pm."))
        XCTAssertEqual(merchant(c), "Walmart+")
    }

    func testHDFCVPAFormats() throws {
        let a = try XCTUnwrap(parse("You have done a UPI txn", "Dear Customer, Rs.404.00 is debited from your account ending 1234 towards VPA cp.zepto13a87@axisb (Zepto) on 11-08-26."))
        XCTAssertEqual(merchant(a), "Zepto")
        let b = try XCTUnwrap(parse("You have done a UPI txn", "Dear Customer, Rs.4798.00 has been debited from account 1234 to VPA shop1.payu@hdfcbank THESOULEDSTORE COM on 05-11-25."))
        XCTAssertEqual(merchant(b), "The Souled Store")
        XCTAssertEqual(b.type, .purchase)
    }

    func testCREDIsCardBillNotSpending() throws {
        let p = try XCTUnwrap(parse("You have done a UPI txn", "Dear Customer, Rs.27882.90 is debited from your account ending 1234 towards VPA cred.club@axisb (CRED Club) on 31-07-26."))
        XCTAssertEqual(p.type, .creditCardPayment)
    }

    func testUPIToAPersonIsATransfer() throws {
        let p = try XCTUnwrap(parse("You have done a UPI txn", "Dear Customer, Rs.6317.00 is debited from your account ending 1234 towards VPA rahul.k-2@okicici (RAHUL KUMAR) on 18-06-26."))
        XCTAssertEqual(p.type, .transferOut)
    }

    func testForexMarkupSubjectIsStillAPurchase() throws {
        let p = try XCTUnwrap(parse("Important: Forex Conversion Markup Fee on cross border transaction using Debit Card Transaction",
            "Dear Customer, Thank you for choosing HDFC Bank! Recent International Transaction Alert: Your HDFC Bank Debit Card ending in XX1234 was used for an international purchase of INR 1556.34 on 08/10/2025."))
        XCTAssertEqual(p.type, .purchase)
        XCTAssertEqual(p.money.amount.stableString, "1556.34")
    }

    func testPaymentMadeUsingCreditCardIsAPurchase() throws {
        let p = try XCTUnwrap(parse("A payment was made using your Credit Card", "Dear Customer, We would like to inform you that Rs. 1000.00 has been debited from your HDFC Bank Credit Card ending 1234 towards ERCPRO PVT LTD OP ECIL on 27 Aug, 2026 at 15:17:03 ."))
        XCTAssertEqual(p.type, .purchase)
    }

    func testDebitCardAtAppleDotComUS() throws {
        let p = try XCTUnwrap(parse("Rs.97748.02 debited via Debit Card **1234", "Dear Customer, Rs.97748.02 is debited from your HDFC Bank Debit Card ending 1234 at APPLE.COM/US on 08 Oct, 2025 at 01:52:30."))
        XCTAssertEqual(merchant(p), "Apple")
    }

    func testInvoiceUsesTotalNotLineItem() throws {
        let p = try XCTUnwrap(parse("Rapido Invoice", "Bill Details Ride Charge ₹ 135.64 Booking Fees & Convenience Charges ₹ 2.36 Total Amount ₹ 138.00 (Inclusive of Taxes) You Paid Using QR Pay ₹ 138.00"))
        XCTAssertEqual(p.money.amount, 138)
        XCTAssertEqual(p.type, .purchase)
        XCTAssertEqual(merchant(p), "Rapido")
    }

    func testMerchantSayingWeReceivedPaymentIsYourSpend() throws {
        let p = try XCTUnwrap(parse("ixigo Booking Invoice", "Booking Confirmed Hi, Thanks for booking your flight via ixigo. We have received the payment of Rs. 6199 for your flight booking."))
        XCTAssertEqual(p.direction, .debit)
        XCTAssertEqual(merchant(p), "ixigo")
    }

    func testNewslettersAndOrderStatusRejected() {
        XCTAssertNil(parse("Got credit limit increase", "u/someone 1d ago I spent $3000 to build my dream game on Claude Code."))
        XCTAssertNil(parse("Groww Digest", "Tata Power signed a Rs 1,200 crore power purchase agreement with Tata Power Mumbai."))
        XCTAssertNil(parse("Your Myntra exchange order item has been shipped", "X Luxe Shirts Worth ₹592.00 In exchange for VASTRADO Shirt ₹443.00"))
        XCTAssertNil(parse("Your wish list calling?", "Shop with ₹3,15,000 from Kotak Personal Loan. Keep every purchase well planned."))
    }

    func testCardReversalLinksBackToPurchase() {
        let e = LedgerEngine(defaultCurrency: "INR")
        e.ingestMessage("AU Bank Credit Card Transaction Alert. Dear Customer, USD 64.20 were spent on your AU Bank Credit Card xx9921 at DOORDASH on 01-07-2026 at 01:00:00 am.",
                        source: .emailAlert, receivedAt: day("2026-07-01"))
        e.ingestMessage("Transaction on your AU Bank Credit Card is reversed. Dear Customer, USD 64.20 spent on your AU Bank Credit Card XX9921 is credited back to your Card.",
                        source: .emailAlert, receivedAt: day("2026-07-03"))
        XCTAssertEqual(e.spent("USD"), 0)
        XCTAssertTrue(e.liveTransactions.contains { $0.isRefund && !$0.refundLinkIDs.isEmpty })
    }

    func testBankSenderIsNeverTheMerchant() {
        let e = LedgerEngine(defaultCurrency: "INR")
        let o = e.ingestMessage("You have done a UPI txn. Dear Customer, Rs.1000.00 has been debited from account 1234 to account ******* on 15-10-25.",
                                source: .emailAlert, receivedAt: day("2026-09-01"), merchantHint: "HDFC Bank InstaAlerts")
        XCTAssertNotEqual(e.tx(o)?.merchantName, "HDFC Bank InstaAlerts")
    }
}

final class PeopleTests: XCTestCase {
    func testMoneyToFamilyIsACategoryButNotShopping() {
        let e = LedgerEngine(defaultCurrency: "INR")
        let o = e.ingestMessage("You have done a UPI txn. Dear Customer, Rs.2500.00 is debited from your account ending 1234 towards VPA mom12@superyes (ANITA KUMARI) on 18-09-26.",
                                source: .emailAlert, receivedAt: day("2026-09-18"))
        let id = e.tx(o)!.id
        XCTAssertEqual(e.state.transactions[id]?.categoryID, "people.other")
        e.setCategory(id, to: "people.family", alwaysForMerchant: true)
        let s = e.summaries(from: day("2026-09-01", "00:00"), to: day("2026-10-01", "00:00"))["INR"]!
        XCTAssertEqual(s.spent, 0)
        XCTAssertEqual(s.sentToPeople, 2500)
        XCTAssertEqual(s.moneyOut, 2500)
        XCTAssertEqual(s.byCategory["people"], 2500)
        // Next payment to her is Family automatically.
        let next = e.ingestMessage("You have done a UPI txn. Dear Customer, Rs.500.00 is debited from your account ending 1234 towards VPA mom12@superyes (ANITA KUMARI) on 25-09-26.",
                                   source: .emailAlert, receivedAt: day("2026-09-25"))
        XCTAssertEqual(e.tx(next)?.categoryID, "people.family")
    }
}

final class OwnerAndSubscriptionTests: XCTestCase {
    func testChaiDoesNotMatchChaitra() {
        XCTAssertNil(KeywordRules.match("K CHAITRA RAO"))
        XCTAssertEqual(KeywordRules.match("CHAI POINT")?.0, "food.coffee")
        XCTAssertEqual(KeywordRules.match("LN SPORTS ARENA LLP")?.0, "entertainment.sports")
    }

    func testPaymentToYourselfIsATransfer() {
        let e = LedgerEngine(defaultCurrency: "INR")
        for (i, d) in ["2026-09-01", "2026-09-02"].enumerated() {
            e.ingestMessage("AU Bank Credit Card Transaction Alert. Dear Ravi Kiran, INR 10\(i).00 were spent on your AU Bank Credit Card xx9921 at UPI/ZEPTO on 0\(i + 1)-09-2026.",
                            source: .emailAlert, receivedAt: day(d))
        }
        let o = e.ingestMessage("You have done a UPI txn. Dear Customer, Rs.5000.00 is debited from your account ending 1234 towards VPA rk@okicici (R RAVI KIRAN) on 05-09-26.",
                                source: .emailAlert, receivedAt: day("2026-09-05"))
        let tx = e.tx(o)!
        XCTAssertTrue(tx.isInternalTransfer)
        XCTAssertEqual(tx.categoryID, "financial.transfer")
        let mom = e.ingestMessage("You have done a UPI txn. Dear Customer, Rs.700.00 is debited from your account ending 1234 towards VPA m1@okicici (KIRAN LATHA) on 06-09-26.",
                                  source: .emailAlert, receivedAt: day("2026-09-06"))
        XCTAssertEqual(e.tx(mom)?.categoryID, "people.other", "shares one name word only — a different person")
    }

    func testSameAmountEveryMonthIsASubscription() throws {
        let e = LedgerEngine(defaultCurrency: "INR")
        try e.importStatement(text: csv(["05/07/2026,SOMEAPP SERVICES,-299.00", "05/08/2026,SOMEAPP SERVICES,-299.00", "05/09/2026,SOMEAPP SERVICES,-299.00"]), fileName: "s.csv")
        e.refreshRecurring(now: day("2026-09-10"))
        XCTAssertTrue(e.liveTransactions.allSatisfy { $0.categoryID == "bills.subscriptions" })
    }
}
