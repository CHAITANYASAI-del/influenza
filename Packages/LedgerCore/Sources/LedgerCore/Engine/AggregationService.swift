import Foundation

/// "Where did my money go?" — per currency, never summed across currencies
/// without an explicit FX rate (spec §44, §136, §139).
public struct PeriodSummary: Sendable, Equatable {
    public let currencyCode: String
    public var spent: Decimal = 0          // purchases + fees + bills − linked refunds
    public var moved: Decimal = 0          // transfers (own accounts, card payments, to others)
    public var received: Decimal = 0       // income
    public var refunded: Decimal = 0       // all refunds received
    public var withdrew: Decimal = 0       // ATM → cash
    public var sentToPeople: Decimal = 0   // UPI/bank transfers to other people (family, friends)
    /// Everything that left your hands: spending + money sent to people.
    public var moneyOut: Decimal { spent + sentToPeople }
    public var fees: Decimal = 0
    public var byCategory: [String: Decimal] = [:]   // top-level category → net spend
    public var bySubcategory: [String: Decimal] = [:]
    public var byMerchant: [String: Decimal] = [:]
    public var transactionCount = 0

    public init(currencyCode: String) { self.currencyCode = currencyCode }
}

public enum AggregationService {
    public static func isSpending(_ tx: CanonicalTransaction) -> Bool {
        tx.direction == .debit && !tx.isInternalTransfer && !tx.isCreditCardPayment && !tx.isExcludedByUser
            && [.purchase, .fee, .billPayment].contains(tx.flowType)
    }

    /// A transfer to another person (not your own account, not a card bill).
    public static func isSentToPerson(_ tx: CanonicalTransaction) -> Bool {
        tx.flowType == .transfer && tx.direction == .debit && !tx.isInternalTransfer && !tx.isCreditCardPayment && !tx.isExcludedByUser
            && CategoryTree.node(tx.categoryID)?.topLevelID == "people"
    }

    public static func summaries(_ transactions: some Sequence<CanonicalTransaction>, from: Date, to: Date,
                                 lookup: (UUID) -> CanonicalTransaction?) -> [String: PeriodSummary] {
        var out: [String: PeriodSummary] = [:]
        for tx in transactions where tx.transactionDate >= from && tx.transactionDate < to && !tx.isExcludedByUser {
            var s = out[tx.currencyCode] ?? PeriodSummary(currencyCode: tx.currencyCode)
            s.transactionCount += 1
            let top = CategoryTree.node(tx.categoryID)?.topLevelID ?? "other"
            if isSpending(tx) {
                s.spent += tx.amount
                s.byCategory[top, default: 0] += tx.amount
                s.bySubcategory[tx.categoryID, default: 0] += tx.amount
                s.byMerchant[tx.displayMerchant, default: 0] += tx.amount
                if tx.flowType == .fee { s.fees += tx.amount }
            } else if tx.flowType == .transfer && tx.direction == .debit {
                s.moved += tx.amount
                if isSentToPerson(tx) {
                    s.sentToPeople += tx.amount
                    s.byCategory[top, default: 0] += tx.amount
                    s.bySubcategory[tx.categoryID, default: 0] += tx.amount
                    s.byMerchant[tx.displayMerchant, default: 0] += tx.amount
                }
            } else if tx.flowType == .transfer && tx.direction == .credit && !tx.isInternalTransfer {
                s.received += tx.amount
            } else if tx.flowType == .withdrawal {
                s.withdrew += tx.amount
            } else if tx.isRefund || tx.flowType == .refund {
                s.refunded += tx.amount
                // Linked refunds reduce the spend of the original purchase's category.
                if let purchaseID = tx.refundLinkIDs.first, let purchase = lookup(purchaseID), isSpending(purchase) {
                    let ptop = CategoryTree.node(purchase.categoryID)?.topLevelID ?? "other"
                    s.spent -= tx.amount
                    s.byCategory[ptop, default: 0] -= tx.amount
                    s.bySubcategory[purchase.categoryID, default: 0] -= tx.amount
                    s.byMerchant[purchase.displayMerchant, default: 0] -= tx.amount
                }
            } else if tx.direction == .credit && [.income, .deposit].contains(tx.flowType) {
                s.received += tx.amount
            }
            out[tx.currencyCode] = s
        }
        return out
    }
}

extension LedgerEngine {
    public func summaries(from: Date, to: Date) -> [String: PeriodSummary] {
        AggregationService.summaries(state.transactions.values, from: from, to: to) { self.state.transactions[$0] }
    }
}
