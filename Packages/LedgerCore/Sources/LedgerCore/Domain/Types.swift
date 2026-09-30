import Foundation

public enum EvidenceSourceType: String, Codable, Sendable, CaseIterable {
    case financeKit, bankFeed
    case statementCSV, statementOFX, statementPDF
    case receipt
    case smsAlert, emailAlert, walletEvent
    case manualCash, manualEntry

    /// 1 = authoritative … 5 = user input (spec §4).
    public var trustLevel: Int {
        switch self {
        case .financeKit, .bankFeed: 1
        case .statementCSV, .statementOFX, .statementPDF: 2
        case .receipt: 3
        case .smsAlert, .emailAlert, .walletEvent: 4
        case .manualCash, .manualEntry: 5
        }
    }

    public var isStatement: Bool { trustLevel == 2 }
    public var isAlert: Bool { trustLevel == 4 }
}

public enum ParseStatus: String, Codable, Sendable { case parsed, partiallyParsed, notFinancial, failed }
public enum Direction: String, Codable, Sendable { case debit, credit }
public enum PendingState: String, Codable, Sendable { case pending, posted, unknown }

public enum PaymentRail: String, Codable, Sendable, CaseIterable {
    case upi, neft, imps, rtgs, bankTransfer, ach, wire, sepa, directDebit
    case creditCard, debitCard, applePay, appleCash, wallet, atm, pos, ecommerce, cash, cheque, unknown

    public var isCard: Bool { [.creditCard, .debitCard, .applePay, .pos].contains(self) }
    public var isTransferRail: Bool { [.neft, .imps, .rtgs, .bankTransfer, .ach, .wire, .sepa].contains(self) }

    public var displayName: String {
        switch self {
        case .upi: "UPI"; case .neft: "NEFT"; case .imps: "IMPS"; case .rtgs: "RTGS"
        case .bankTransfer: "Bank transfer"; case .ach: "ACH"; case .wire: "Wire"; case .sepa: "SEPA"
        case .directDebit: "Direct debit"; case .creditCard: "Credit card"; case .debitCard: "Debit card"
        case .applePay: "Apple Pay"; case .appleCash: "Apple Cash"; case .wallet: "Wallet"; case .atm: "ATM"
        case .pos: "Card"; case .ecommerce: "Online"; case .cash: "Cash"; case .cheque: "Cheque"; case .unknown: "—"
        }
    }

    static func compatible(_ a: PaymentRail, _ b: PaymentRail) -> Bool {
        if a == .unknown || b == .unknown || a == b { return true }
        if a.isCard && b.isCard { return true }
        return false
    }
}

public enum ObservationTransactionType: String, Codable, Sendable {
    case purchase, refund, transferOut, transferIn, internalTransfer, creditCardPayment
    case withdrawal, deposit, fee, salary, interest, cashback, income, billPayment, unknown
}

public enum FlowType: String, Codable, Sendable, CaseIterable {
    case purchase, transfer, refund, income, fee, withdrawal, deposit, billPayment, loanPayment, investment, adjustment, unknown
}

public enum VerificationStatus: String, Codable, Sendable {
    /// Confirmed by an authoritative or statement source.
    case verified
    /// Entered by the user (cash, manual).
    case userEntered
    /// Seen only in an alert/receipt; real but not yet confirmed by a statement.
    case detected
    /// Needs a human decision (possible duplicate, unclear parse).
    case pendingReview
}

public enum AccountType: String, Codable, Sendable { case checking, savings, creditCard, debitCard, wallet, cash, loan, investment, other }
public enum Ownership: String, Codable, Sendable { case userOwned, external, unknown }
