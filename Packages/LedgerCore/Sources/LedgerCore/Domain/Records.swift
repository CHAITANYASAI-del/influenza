import Foundation

public struct RawEvidence: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let sourceType: EvidenceSourceType
    public let sourceIdentifier: String?
    public let receivedAt: Date
    public let originalDate: Date?
    public let countryCode: String?
    /// Kept on-device so improved parsers can re-process and users can see "why".
    public let rawText: String?
    public let rawDataHash: String
    public let fileReference: String?
    public var parserVersion: String
    public var parseStatus: ParseStatus
}

public struct ReceiptItem: Codable, Sendable, Hashable {
    public let name: String
    public let amount: Decimal?
    public init(name: String, amount: Decimal?) { self.name = name; self.amount = amount }
}

public struct FinancialObservation: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let evidenceID: UUID
    public let sourceType: EvidenceSourceType
    public let sourceTransactionID: String?
    public let sourceAccountHint: String?
    public let merchantRaw: String?
    public let merchantCanonical: String?
    public let amount: Decimal
    public let currencyCode: String
    public let direction: Direction
    public let transactionDate: Date
    public let postedDate: Date?
    public let referenceNumber: String?
    public let authorizationCode: String?
    public let cardLast4: String?
    public let paymentRail: PaymentRail
    public let transactionType: ObservationTransactionType
    public let pendingState: PendingState
    public let countryCode: String?
    public let receiptItems: [ReceiptItem]
    public let parserVersion: String
    public let fingerprint: String

    public var money: Money { Money(amount, currencyCode) }
}

public struct CanonicalTransaction: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var amount: Decimal
    public var currencyCode: String
    public var direction: Direction
    public var transactionDate: Date
    public var postedDate: Date?

    public var merchantName: String?
    public var merchantDetail: String?
    public var merchantRaw: String?
    public var accountHint: String?
    public var paymentRail: PaymentRail
    public var flowType: FlowType

    public var categoryID: String
    public var categoryConfidence: Double
    public var categoryReason: String

    public var verificationStatus: VerificationStatus
    public var observationIDs: [UUID]
    public var linkedTransactionIDs: [UUID]
    public var recurringSeriesID: String?

    public var isInternalTransfer: Bool
    public var isCreditCardPayment: Bool
    public var isRefund: Bool
    public var isPending: Bool
    /// For a purchase: refunds linked to it. For a refund: the purchase it reverses.
    public var refundLinkIDs: [UUID]

    public var userModifiedFields: Set<String>
    /// User chose "Ignore": kept for audit, excluded from all totals.
    public var isExcludedByUser: Bool
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var money: Money { Money(amount, currencyCode) }
    public var displayMerchant: String { merchantName ?? merchantRaw ?? "Unknown" }
}

public enum RelationshipType: String, Codable, Sendable {
    case merged, pendingPosted, internalTransfer, creditCardPayment, refund, receipt, possibleDuplicate, userMerged, userKeptSeparate
}

public struct ReconciliationRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var canonicalTransactionID: UUID
    public var otherTransactionID: UUID?
    public var sourceObservationIDs: [UUID]
    public var relationshipType: RelationshipType
    public var score: Double
    public var humanReadableReasons: [String]
    public var engineVersion: String
    public var createdAt: Date
    public var needsReview: Bool
}

public struct UserCategoryRule: Codable, Sendable, Hashable {
    public let merchantKey: String
    public let categoryID: String
}

public enum RecurringKind: String, Codable, Sendable { case fixedRecurring, variableRecurring, likelyRecurring }
public enum Cadence: String, Codable, Sendable, CaseIterable {
    case weekly, biweekly, monthly, quarterly, annual
    var days: ClosedRange<Double> {
        switch self { case .weekly: 6...8; case .biweekly: 13...16; case .monthly: 26...35; case .quarterly: 84...98; case .annual: 350...380 }
    }
    var component: (Calendar.Component, Int) {
        switch self { case .weekly: (.day, 7); case .biweekly: (.day, 14); case .monthly: (.month, 1); case .quarterly: (.month, 3); case .annual: (.year, 1) }
    }
}

public struct RecurringSeries: Codable, Sendable, Identifiable, Hashable {
    public let id: String            // merchantKey|currency
    public let merchantName: String
    public let currencyCode: String
    public let cadence: Cadence
    public let kind: RecurringKind
    public let typicalAmount: Decimal
    public let lastDate: Date
    public let nextExpectedDate: Date
    public let transactionIDs: [UUID]
}

public struct ImportJob: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let sourceType: EvidenceSourceType
    public let startedAt: Date
    public var completedAt: Date?
    public var recordsSeen = 0
    public var recordsParsed = 0
    public var recordsRejected = 0
    public var newTransactions = 0
    public var mergedIntoExisting = 0
    public var duplicatesSkipped = 0
    public var transfersExcluded = 0
    public var refundsLinked = 0
    public var needsReview = 0
    public var parserVersion: String
}
