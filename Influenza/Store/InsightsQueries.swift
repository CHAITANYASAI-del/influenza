import UIKit
import Foundation
import LedgerCore
import WidgetKit

/// Month-scoped read models for Insights. Totals come from LedgerCore's
/// aggregation (transfers, card payments, ATM excluded; refunds netted).
struct BrandSpend: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let categoryID: String
    let amount: Decimal
    let count: Int
}

struct Comparison: Identifiable {
    let id: String
    let label: String
    let baseline: Decimal
    let current: Decimal
    var delta: Decimal { current - baseline }
}

extension LedgerStore {
    func monthInterval(_ offset: Int) -> DateInterval {
        let cal = Calendar.current
        let anchor = cal.date(byAdding: .month, value: offset, to: .now) ?? .now
        return cal.dateInterval(of: .month, for: anchor) ?? DateInterval(start: .now, duration: 1)
    }

    /// For the current month everything is "so far": compare against the same number of days in earlier months.
    private func window(_ offset: Int, cutFrom selected: Int) -> DateInterval {
        let m = monthInterval(offset)
        guard selected == 0 else { return m }
        let elapsed = Date.now.timeIntervalSince(monthInterval(0).start)
        return DateInterval(start: m.start, end: min(m.end, m.start.addingTimeInterval(elapsed)))
    }

    func spent(monthOffset offset: Int, selected: Int, currency: String, topLevel: String? = nil, merchant: String? = nil) -> Decimal {
        let w = window(offset, cutFrom: selected)
        let s = summary(from: w.start, to: w.end, currency: currency)
        if let merchant { return s.byMerchant[merchant] ?? 0 }
        if let topLevel { return s.byCategory[topLevel] ?? 0 }
        return s.moneyOut
    }

    /// vs last month · vs 3-month average · vs 6-month average (only months with data count).
    func comparisons(selected: Int, currency: String, topLevel: String? = nil, merchant: String? = nil) -> [Comparison] {
        let current = spent(monthOffset: selected, selected: selected, currency: currency, topLevel: topLevel, merchant: merchant)
        func avg(_ n: Int) -> Decimal? {
            let values = (1...n).map { spent(monthOffset: selected - $0, selected: selected, currency: currency, topLevel: topLevel, merchant: merchant) }
            guard monthsWithData(before: selected, count: n, currency: currency) >= min(n, 2) else { return nil }
            return (values.reduce(0, +) / Decimal(n)).rounded(0)
        }
        let lastName = monthInterval(selected - 1).start.formatted(.dateTime.month(.wide))
        var out: [Comparison] = []
        if monthsWithData(before: selected, count: 1, currency: currency) == 1 {
            out.append(Comparison(id: "m1", label: selected == 0 ? "vs \(lastName) so far" : "vs \(lastName)",
                                  baseline: spent(monthOffset: selected - 1, selected: selected, currency: currency, topLevel: topLevel, merchant: merchant),
                                  current: current))
        }
        if let a3 = avg(3) { out.append(Comparison(id: "m3", label: "vs 3-month avg", baseline: a3, current: current)) }
        if let a6 = avg(6) { out.append(Comparison(id: "m6", label: "vs 6-month avg", baseline: a6, current: current)) }
        return out
    }

    private func monthsWithData(before selected: Int, count: Int, currency: String) -> Int {
        (1...count).filter { i in
            let m = monthInterval(selected - i)
            return engine.state.transactions.values.contains { $0.currencyCode == currency && m.contains($0.transactionDate) }
        }.count
    }

    func series(currency: String, months: Int = 12, topLevel: String? = nil, merchant: String? = nil) -> [MonthlyPoint] {
        _ = revision
        return engine.monthlySpending(currency: currency, months: months) { tx in
            if let merchant, tx.displayMerchant != merchant { return false }
            if let topLevel, CategoryTree.node(tx.categoryID)?.topLevelID != topLevel { return false }
            return true
        }
    }

    func brands(monthOffset: Int, currency: String, topLevel: String? = nil, subcategory: String? = nil) -> [BrandSpend] {
        let m = monthInterval(monthOffset)
        let txs = transactions.filter {
            $0.currencyCode == currency && m.contains($0.transactionDate) && AggregationService.isSpending($0)
                && (topLevel == nil || CategoryTree.node($0.categoryID)?.topLevelID == topLevel)
                && (subcategory == nil || $0.categoryID == subcategory)
        }
        let s = summary(from: m.start, to: m.end, currency: currency)   // net of linked refunds
        return Dictionary(grouping: txs, by: \.displayMerchant).map { name, list in
            BrandSpend(name: name, categoryID: list.first?.categoryID ?? "other.unknown",
                       amount: min(s.byMerchant[name] ?? 0, list.reduce(0) { $0 + $1.amount }), count: list.count)
        }
        .filter { $0.amount > 0 }
        .sorted { $0.amount > $1.amount }
    }

    func transactions(monthOffset: Int, currency: String, where include: (CanonicalTransaction) -> Bool) -> [CanonicalTransaction] {
        let m = monthInterval(monthOffset)
        return transactions.filter { $0.currencyCode == currency && m.contains($0.transactionDate) && include($0) }
    }

    // MARK: Widget (App Group snapshot, spec §55–59)

    func writeWidgetSnapshot() {
        let currency = currencies.first ?? Fmt.defaultCurrency
        let month = summary(month: 0, currency: currency)
        let today = Calendar.current.startOfDay(for: .now)
        let todayS = summary(from: today, to: .now.addingTimeInterval(1), currency: currency)
        let cats = month.byCategory.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(4).map { id, amount in
            WidgetSnapshot.Category(name: CategoryTree.node(id)?.name ?? "Other", symbol: CategoryStyle.symbol(id),
                                    colorHex: CategoryStyle.hex(id), amount: amount)
        }
        let container = WidgetSnapshot.containerURL
        let brandList = brands(monthOffset: 0, currency: currency).prefix(3).map { b -> WidgetSnapshot.Brand in
            var brand = WidgetSnapshot.Brand(name: b.name, colorHex: BrandCatalog.info(for: b.name).colorHex, amount: b.amount)
            // Small logo copy for the widget (it can't read the app's asset catalog).
            let slug = BrandLogo.slug(b.name)
            let cached = URL.cachesDirectory.appending(path: "BrandLogos/\(slug).png")
            if let container, let image = BrandLogo.bundled(b.name) ?? (try? Data(contentsOf: cached)).flatMap(UIImage.init(data:)),
               let small = image.preparingThumbnail(of: CGSize(width: 96, height: 96))?.pngData() {
                let file = "logo-\(slug).png"
                try? small.write(to: container.appending(path: file), options: .atomic)
                brand.logoFile = file
            }
            return brand
        }
        let next = recurring.first { $0.currencyCode == currency }.map { "\($0.merchantName) · \($0.nextExpectedDate.formatted(.dateTime.day().month(.abbreviated)))" }
        var snapshot = WidgetSnapshot(
            generatedAt: .now, currency: currency, monthName: Date.now.formatted(.dateTime.month(.wide)),
            monthSpend: month.moneyOut, todaySpend: todayS.moneyOut,
            lastMonthSameDay: spent(monthOffset: -1, selected: 0, currency: currency),
            topCategories: Array(cats), topBrands: Array(brandList), reviewCount: reviewCount, nextRecurring: next, hasData: !isEmpty)
        snapshot.spentOnThings = month.spent
        snapshot.last7Days = (0..<7).reversed().map { back in
            let start = Calendar.current.date(byAdding: .day, value: -back, to: today)!
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            return summary(from: start, to: end, currency: currency).moneyOut
        }
        snapshot.sentToPeople = month.sentToPeople
        try? snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: People (UPI / bank transfers to and from individuals)

struct PersonFlow: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let sent: Decimal
    let received: Decimal
    let count: Int
}

extension LedgerStore {
    /// Money sent to / received from people this month (not shops, not your own accounts or card bills).
    func people(monthOffset: Int, currency: String) -> [PersonFlow] {
        let m = monthInterval(monthOffset)
        let txs = transactions.filter {
            $0.currencyCode == currency && m.contains($0.transactionDate) && $0.flowType == .transfer
                && !$0.isInternalTransfer && !$0.isCreditCardPayment && !$0.isExcludedByUser
        }
        return Dictionary(grouping: txs) { $0.merchantName ?? $0.merchantRaw ?? "Someone" }.map { name, list in
            PersonFlow(name: name,
                       sent: list.filter { $0.direction == .debit }.reduce(0) { $0 + $1.amount },
                       received: list.filter { $0.direction == .credit }.reduce(0) { $0 + $1.amount },
                       count: list.count)
        }
        .sorted { max($0.sent, $0.received) > max($1.sent, $1.received) }
    }
}
