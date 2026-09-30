import LedgerCore
import SwiftUI

/// Spec §52, §96, §97: grouped timeline, offline search, filters.
struct TransactionsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", spending = "Spending", income = "Income", transfers = "Transfers", refunds = "Refunds", recurring = "Recurring", review = "Needs review"
        var id: String { rawValue }
    }

    private var filtered: [CanonicalTransaction] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return store.transactions.filter { tx in
            let passes: Bool = switch filter {
            case .all: true
            case .spending: AggregationService.isSpending(tx)
            case .income: tx.direction == .credit && [.income, .deposit].contains(tx.flowType)
            case .transfers: tx.flowType == .transfer || tx.isInternalTransfer
            case .refunds: tx.isRefund
            case .recurring: tx.recurringSeriesID != nil
            case .review: tx.verificationStatus == .pendingReview || tx.categoryID == "other.unknown"
            }
            guard passes else { return false }
            guard !q.isEmpty else { return true }
            return tx.displayMerchant.lowercased().contains(q)
                || CategoryTree.displayName(tx.categoryID).lowercased().contains(q)
                || tx.paymentRail.displayName.lowercased().contains(q)
                || "\(tx.amount)".contains(q)
                || (tx.merchantRaw?.lowercased().contains(q) ?? false)
                || (tx.note?.lowercased().contains(q) ?? false)
                || (tx.merchantDetail?.lowercased().contains(q) ?? false)
        }
    }

    /// Today / Yesterday / This week / Last week, then one section per month with its total.
    private var sections: [(key: String, order: Date, items: [CanonicalTransaction])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { tx -> String in
            let g = TimelineGroup.of(tx.transactionDate)
            if g != .earlier { return "0\(g.rawValue)|\(g.title)" }
            let m = cal.dateInterval(of: .month, for: tx.transactionDate)!.start
            return "1" + String(format: "%012d", 9_999_999_999 - Int(m.timeIntervalSince1970)) + "|\(m.formatted(.dateTime.month(.wide).year()))"
        }
        return grouped.map { (key: $0.key, order: $0.value.first?.transactionDate ?? .now, items: $0.value) }.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases) { f in
                                Button(f.rawValue) { withAnimation(.snappy) { filter = f } }
                                    .font(.subheadline.weight(.medium))
                                    .buttonStyle(PopButtonStyle(kind: .dark, fullWidth: false))
                                    .tint(filter == f ? .accentColor : nil)
                                    .opacity(filter == f ? 1 : 0.75)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
                }
                ForEach(sections, id: \.key) { section in
                    Section {
                        ForEach(section.items) { tx in
                            NavigationLink { TransactionDetailView(id: tx.id) } label: { TransactionRow(tx: tx) }
                        }
                    } header: {
                        HStack {
                            Text(section.key.split(separator: "|").last.map(String.init) ?? "")
                            Spacer()
                            let spent = section.items.filter { AggregationService.isSpending($0) && $0.currencyCode == Fmt.defaultCurrency }
                                .reduce(Decimal(0)) { $0 + $1.amount }
                            if spent > 0 { Text("Spent \(Fmt.money(spent, Fmt.defaultCurrency))").monospacedDigit() }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Transactions")
            .searchable(text: $query, prompt: "Amazon, food, 1299, UPI…")
            .sensoryFeedback(.selection, trigger: filter)
        }
    }
}
