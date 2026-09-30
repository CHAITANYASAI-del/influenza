import LedgerCore
import SwiftUI

/// FREE-build SMS path (spec §30): copy → open app → paste → local parse → reconcile.
struct PasteAlertSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var outcome: IngestOutcome?
    @FocusState private var focused: Bool

    private var preview: MessageParseResult? { text.isEmpty ? nil : store.preview(text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let outcome { result(outcome) } else { input }
                }
                .padding(20)
            }
            .navigationTitle("Transaction alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .sensoryFeedback(.success, trigger: outcome)
        }
    }

    @ViewBuilder private var input: some View {
        HStack {
            Text("Copy a bank SMS or email alert, then paste it.").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                if let s = strings.first { Task { @MainActor in text = s } }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
        }
        TextField("Or type it here", text: $text, axis: .vertical)
            .lineLimit(3...8)
            .focused($focused)
            .padding(14)
            .popSurface()

        if let preview {
            switch preview {
            case let .financial(p):
                VStack(alignment: .leading, spacing: 10) {
                    Text("Detected").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(Fmt.money(p.money)).font(.system(size: 40, weight: .bold, design: .rounded))
                    HStack(spacing: 8) {
                        Label(p.merchantRaw.map { MerchantResolver.resolve($0)?.name ?? MerchantResolver.cleanDisplayName($0) } ?? "Merchant not yet verified",
                              systemImage: "storefront")
                        if p.rail != .unknown { Text("· \(p.rail.displayName)") }
                    }
                    .font(.subheadline)
                    Text(p.direction == .credit ? "Money in" : "Money out").font(.caption).foregroundStyle(.secondary)
                    PrimaryButton(title: "Add", symbol: "plus") { outcome = store.pasteAlert(text) }
                }
                .padding(18)
                .popSurface()
            case let .notFinancial(reason):
                Label("Not a completed payment (\(reason)). Nothing will be added.", systemImage: "nosign")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        Label("Read on this iPhone. The message is kept only here so you can see where each transaction came from.", systemImage: "lock.fill")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func result(_ o: IngestOutcome) -> some View {
        let tx = o.transactionID.flatMap(store.transaction)
        VStack(spacing: 14) {
            switch o {
            case .added: header("checkmark.circle.fill", .green, "Added")
            case .merged: header("link.circle.fill", .blue, "Matched — already in your ledger")
            case .duplicate: header("equal.circle.fill", .secondary, "You've already added this")
            case .needsReview: header("exclamationmark.circle.fill", .orange, "Added — please check it in Review")
            case .notFinancial: header("nosign", .secondary, "Nothing added")
            }
            if let tx { TransactionRow(tx: tx).padding(14).popSurface() }
            HStack {
                Button("Paste another") { text = ""; outcome = nil }.buttonStyle(PopButtonStyle(kind: .dark, fullWidth: false))
                Button("Done") { dismiss() }.buttonStyle(PopButtonStyle(kind: .primary, fullWidth: false))
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    private func header(_ symbol: String, _ color: Color, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(color).symbolEffect(.bounce, options: .nonRepeating)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
        }
    }
}
