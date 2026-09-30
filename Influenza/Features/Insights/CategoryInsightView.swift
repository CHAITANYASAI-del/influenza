import LedgerCore
import SwiftUI

/// Food → subcategories → brands (Swiggy ₹4,200 · 14 orders · avg ₹300) → payments.
struct CategoryInsightView: View {
    @Environment(LedgerStore.self) private var store
    let topLevelID: String
    @State var month: Int
    let currency: String
    @State private var subcategory: String?

    var body: some View {
        let m = store.monthInterval(month)
        let s = store.summary(from: m.start, to: m.end, currency: currency)
        let total = s.byCategory[topLevelID] ?? 0
        let subs = s.bySubcategory.filter { CategoryTree.node($0.key)?.topLevelID == topLevelID && $0.value > 0 }.sorted { $0.value > $1.value }
        let brands = store.brands(monthOffset: month, currency: currency, topLevel: topLevelID, subcategory: subcategory)
        let txs = store.transactions(monthOffset: month, currency: currency) {
            CategoryTree.node($0.categoryID)?.topLevelID == topLevelID && (subcategory == nil || $0.categoryID == subcategory)
                && (AggregationService.isSpending($0) || $0.isRefund || AggregationService.isSentToPerson($0))
        }
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    MonthHeader(month: $month, date: m.start)
                    HStack(spacing: 14) {
                        CategoryBadge(categoryID: topLevelID, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            PopLabel(text: CategoryTree.node(topLevelID)?.name ?? "")
                            MoneyText(amount: total, currency: currency, size: 32).foregroundStyle(Pop.ink)
                        }
                    }
                    ComparisonPills(comparisons: store.comparisons(selected: month, currency: currency, topLevel: topLevelID), currency: currency)
                }
                Card(title: "Last 6 months") {
                    TrendChart(points: store.series(currency: currency, months: 6, topLevel: topLevelID), currency: currency, tint: CategoryStyle.tint(topLevelID))
                }
                if subs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(nil, "All", total)
                            ForEach(subs, id: \.key) { chip($0.key, CategoryTree.node($0.key)?.name ?? "", $0.value) }
                        }
                    }
                }
                if !brands.isEmpty {
                    Card(title: "Brands") {
                        ForEach(brands) { b in
                            NavigationLink(value: InsightRoute.brand(b.name, month: month)) {
                                HStack(spacing: 12) {
                                    BrandLogo(name: b.name, size: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(b.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                            Spacer()
                                            Text(Fmt.money(b.amount, currency)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                                        }
                                        GeometryReader { g in
                                            Capsule().fill(Color(hex: BrandCatalog.info(for: b.name).colorHex).gradient)
                                                .frame(width: max(4, g.size.width * CGFloat(b.amount.double / max(brands[0].amount.double, 1))))
                                        }
                                        .frame(height: 5)
                                        Text("\(b.count) payment\(b.count == 1 ? "" : "s") · avg \(Fmt.money(b.amount / Decimal(b.count), currency))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Card(title: "Payments") {
                    if txs.isEmpty { Text("No payments this month.").foregroundStyle(.secondary) }
                    ForEach(txs) { tx in
                        NavigationLink { TransactionDetailView(id: tx.id) } label: { TransactionRow(tx: tx) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(AmbientBackground())
        .navigationTitle(CategoryTree.node(topLevelID)?.name ?? "Category")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: month)
        .animation(.smooth, value: subcategory)
    }

    private func chip(_ id: String?, _ title: String, _ amount: Decimal) -> some View {
        Button { subcategory = id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(Fmt.money(amount, currency, compact: true)).font(.caption2).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(subcategory == id ? .white : .primary)
        }
        .buttonStyle(.plain)
        .popSurface(elevated: true)
    }
}

struct BrandInsightView: View {
    @Environment(LedgerStore.self) private var store
    let name: String
    @State var month: Int
    let currency: String

    var body: some View {
        let m = store.monthInterval(month)
        let s = store.summary(from: m.start, to: m.end, currency: currency)
        let txs = store.transactions(monthOffset: month, currency: currency) { $0.displayMerchant == name }
        let spent = s.byMerchant[name] ?? 0
        let count = txs.filter(AggregationService.isSpending).count
        let allTime = store.transactions.filter { $0.displayMerchant == name && $0.currencyCode == currency && AggregationService.isSpending($0) }
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    MonthHeader(month: $month, date: m.start)
                    HStack(spacing: 14) {
                        BrandLogo(name: name, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            PopLabel(text: name)
                            MoneyText(amount: spent, currency: currency, size: 30).foregroundStyle(Pop.ink)
                            if count > 0 {
                                Text("\(count) payment\(count == 1 ? "" : "s") · avg \(Fmt.money(spent / Decimal(count), currency))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ComparisonPills(comparisons: store.comparisons(selected: month, currency: currency, merchant: name), currency: currency)
                }
                Card(title: "Last 6 months") {
                    TrendChart(points: store.series(currency: currency, months: 6, merchant: name), currency: currency,
                               tint: Color(hex: BrandCatalog.info(for: name).colorHex))
                    LabeledContent("All time", value: "\(Fmt.money(allTime.reduce(0) { $0 + $1.amount }, currency)) · \(allTime.count) payments")
                        .font(.footnote)
                }
                Card(title: "Payments") {
                    if txs.isEmpty { Text("No payments this month.").foregroundStyle(.secondary) }
                    ForEach(txs) { tx in
                        NavigationLink { TransactionDetailView(id: tx.id) } label: { TransactionRow(tx: tx) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(AmbientBackground())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: month)
    }
}

/// ‹  SEPTEMBER 2026  ›
struct MonthHeader: View {
    @Binding var month: Int
    let date: Date
    var body: some View {
        HStack {
            Button { withAnimation(.snappy) { month -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
            Spacer()
            PopLabel(text: date.formatted(.dateTime.month(.wide).year()), color: Pop.ink)
            Spacer()
            Button { withAnimation(.snappy) { month += 1 } } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                .disabled(month >= 0).opacity(month >= 0 ? 0.25 : 1)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Pop.ink)
        .buttonStyle(.plain)
    }
}
