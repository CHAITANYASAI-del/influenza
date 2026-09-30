import LedgerCore
import SwiftUI

/// Spec §49: exceptions only. What we know · why we're unsure · possible match.
struct ReviewView: View {
    @Environment(LedgerStore.self) private var store
    @State private var categorizing: CanonicalTransaction?

    var body: some View {
        NavigationStack {
            List {
                if store.reviewCount == 0 {
                    ContentUnavailableView("All clear", systemImage: "checkmark.circle",
                                           description: Text("Nothing needs your attention."))
                        .listRowBackground(Color.clear)
                }
                if !store.reviewItems.isEmpty {
                    Section("Possible duplicates") {
                        ForEach(store.reviewItems) { record in DuplicateCard(record: record) }
                    }
                }
                if !store.uncategorized.isEmpty {
                    Section {
                        ForEach(store.uncategorized) { tx in
                            Button { categorizing = tx } label: { TransactionRow(tx: tx) }.buttonStyle(.plain)
                        }
                    } header: {
                        Text("Unknown category")
                    } footer: {
                        Text("Pick once — Influenza remembers it for this merchant.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Review")
            .sheet(item: $categorizing) { tx in
                CategoryPicker(current: tx.categoryID, merchant: tx.displayMerchant) { cat, always in store.setCategory(tx.id, cat, always: always) }
            }
        }
    }
}

private struct DuplicateCard: View {
    @Environment(LedgerStore.self) private var store
    let record: ReconciliationRecord

    var body: some View {
        let new = store.transaction(record.canonicalTransactionID)
        let other = record.otherTransactionID.flatMap(store.transaction)
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT WE KNOW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let new { TransactionRow(tx: new) }
            if let other {
                Text("POSSIBLE MATCH").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TransactionRow(tx: other)
            }
            Text("WHY WE'RE UNSURE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(record.humanReadableReasons, id: \.self) { Text("• \($0)").font(.footnote) }
            Group {
                HStack(spacing: 10) {
                    Button { withAnimation { store.resolveReview(record.id, merge: true) } } label: {
                        Label("Same payment", systemImage: "link").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PopButtonStyle(kind: .primary, fullWidth: false))
                    Button { withAnimation { store.resolveReview(record.id, merge: false) } } label: {
                        Label("Different", systemImage: "arrow.left.and.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PopButtonStyle(kind: .dark, fullWidth: false))
                }
            }
            .sensoryFeedback(.success, trigger: store.reviewItems.count)
        }
        .padding(.vertical, 6)
    }
}

