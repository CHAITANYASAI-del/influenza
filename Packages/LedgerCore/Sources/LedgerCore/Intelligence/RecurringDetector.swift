import Foundation

/// Subscriptions & bills without AI (spec §46): merchant + currency + cadence + amount stability.
public enum RecurringDetector {
    public static func detect(_ transactions: [CanonicalTransaction], now: Date = .now) -> [RecurringSeries] {
        let cal = Calendar(identifier: .gregorian)
        let eligible = transactions.filter {
            $0.direction == .debit && !$0.isInternalTransfer && !$0.isExcludedByUser && [.purchase, .billPayment, .fee].contains($0.flowType)
        }
        let groups = Dictionary(grouping: eligible) { "\(MerchantResolver.key($0.merchantName ?? $0.merchantRaw))|\($0.currencyCode)" }
        var result: [RecurringSeries] = []
        for (key, txs) in groups where !key.hasPrefix("|") && txs.count >= 2 {
            let sorted = txs.sorted { $0.transactionDate < $1.transactionDate }
            let gaps = zip(sorted, sorted.dropFirst()).map { $1.transactionDate.timeIntervalSince($0.transactionDate) / 86_400 }
            guard let median = gaps.sorted()[safe: gaps.count / 2],
                  let cadence = Cadence.allCases.first(where: { $0.days.contains(median) }) else { continue }
            let consistent = gaps.filter { cadence.days.contains($0) }.count
            guard Double(consistent) / Double(gaps.count) >= 0.7 else { continue }

            let amounts = sorted.map(\.amount)
            let avg = amounts.reduce(0, +) / Decimal(amounts.count)
            let spread = (amounts.max()! - amounts.min()!) / max(avg, 1)
            let kind: RecurringKind = sorted.count < 3 ? .likelyRecurring : (spread == 0 ? .fixedRecurring : (spread <= 0.25 ? .variableRecurring : .likelyRecurring))
            if sorted.count >= 3 && spread > 0.5 { continue }

            let last = sorted.last!
            let (component, value) = cadence.component
            var next = cal.date(byAdding: component, value: value, to: last.transactionDate)!
            while next < cal.startOfDay(for: now) { next = cal.date(byAdding: component, value: value, to: next)! }
            result.append(RecurringSeries(id: key, merchantName: last.displayMerchant, currencyCode: last.currencyCode, cadence: cadence,
                                          kind: kind, typicalAmount: last.amount, lastDate: last.transactionDate, nextExpectedDate: next,
                                          transactionIDs: sorted.map(\.id)))
        }
        return result.sorted { $0.nextExpectedDate < $1.nextExpectedDate }
    }
}
