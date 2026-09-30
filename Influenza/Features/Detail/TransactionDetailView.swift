import LedgerCore
import SwiftUI

/// Spec §50 / §90: every transaction answers "why is this here?".
struct TransactionDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var showCategories = false
    @State private var showEvidence: RawEvidence?
    @State private var confirmDelete = false
    @State private var note = ""

    var body: some View {
        if let tx = store.transaction(id) {
            let explanation = store.explanation(id)
            List {
                Section {
                    VStack(spacing: 10) {
                        CategoryBadge(categoryID: tx.categoryID, size: 56)
                        Text(tx.displayMerchant).font(.title2.bold()).multilineTextAlignment(.center)
                        Text(Fmt.money(tx.direction == .credit ? tx.amount : -tx.amount, tx.currencyCode, signed: tx.direction == .credit))
                            .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                        statusLabel(tx)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button { showCategories = true } label: {
                        LabeledContent("Category") {
                            HStack { Text(CategoryTree.displayName(tx.categoryID)); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                        }
                    }
                    .foregroundStyle(.primary)
                    if let detail = tx.merchantDetail { LabeledContent("Detail", value: detail) }
                    if tx.paymentRail != .unknown { LabeledContent("Paid with", value: tx.paymentRail.displayName + (tx.accountHint.map { " ••\($0)" } ?? "")) }
                    LabeledContent("Date", value: tx.transactionDate.formatted(date: .abbreviated, time: tx.observationIDs.count == 1 && tx.postedDate == nil ? .shortened : .omitted))
                    if let posted = tx.postedDate, !Calendar.current.isDate(posted, inSameDayAs: tx.transactionDate) {
                        LabeledContent("Posted", value: posted.formatted(date: .abbreviated, time: .omitted))
                    }
                    if tx.isInternalTransfer { LabeledContent("Counts as", value: tx.isCreditCardPayment ? "Card payment — not spending" : "Transfer — not spending") }
                    if tx.isExcludedByUser { LabeledContent("Counts as", value: "Ignored by you") }
                }

                Section("Why this category?") {
                    Text(tx.categoryReason).font(.subheadline)
                    if tx.categoryConfidence < 0.6 && !tx.userModifiedFields.contains("category") {
                        Label("Not sure — tap Category to set it once for this merchant.", systemImage: "questionmark.circle").font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section("Matched evidence") {
                    ForEach(explanation.evidence, id: \.1.id) { evidence, obs in
                        Button { showEvidence = evidence } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                VStack(alignment: .leading) {
                                    Text(sourceName(obs.sourceType)).foregroundStyle(.primary)
                                    Text("\(Fmt.money(obs.money)) · \(obs.transactionDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if evidence.rawText != nil { Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(evidence.rawText == nil)
                    }
                    ForEach(explanation.records.filter { !$0.humanReadableReasons.isEmpty && $0.relationshipType != .possibleDuplicate }) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(relationshipTitle(r.relationshipType)).font(.subheadline.weight(.semibold))
                            ForEach(r.humanReadableReasons, id: \.self) { Label($0, systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }

                Section("Note") {
                    TextField("Add a note", text: $note, axis: .vertical)
                        .onSubmit { store.setNote(id, note.isEmpty ? nil : note) }
                        .onDisappear { if note != (tx.note ?? "") { store.setNote(id, note.isEmpty ? nil : note) } }
                }

                Section {
                    if !tx.isInternalTransfer && tx.direction == .debit {
                        Button("Mark as transfer (not spending)", systemImage: "arrow.left.arrow.right") { store.markTransfer(id) }
                    }
                    Button(tx.isExcludedByUser ? "Include in totals" : "Ignore this transaction", systemImage: tx.isExcludedByUser ? "eye" : "eye.slash") {
                        store.setExcluded(id, !tx.isExcludedByUser)
                    }
                    if tx.verificationStatus == .userEntered {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(tx.displayMerchant)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { note = tx.note ?? "" }
            .sheet(isPresented: $showCategories) {
                CategoryPicker(current: tx.categoryID, merchant: tx.displayMerchant) { cat, always in store.setCategory(id, cat, always: always) }
            }
            .sheet(item: $showEvidence) { e in EvidenceSheet(evidence: e) }
            .confirmationDialog("Delete this cash entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.delete(id); dismiss() }
            }
        } else {
            ContentUnavailableView("Transaction removed", systemImage: "tray")
        }
    }

    @ViewBuilder private func statusLabel(_ tx: CanonicalTransaction) -> some View {
        switch tx.verificationStatus {
        case .verified: Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.subheadline.weight(.semibold))
        case .userEntered: Label("Added by you", systemImage: "hand.tap.fill").foregroundStyle(.secondary).font(.subheadline)
        case .detected: Label("Detected from alert — confirms when a statement arrives", systemImage: "text.bubble").foregroundStyle(.blue).font(.footnote)
        case .pendingReview: Label("Needs review", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.subheadline.weight(.semibold))
        }
    }

    private func sourceName(_ s: EvidenceSourceType) -> String {
        switch s {
        case .financeKit: "Apple financial data"
        case .bankFeed: "Bank record"
        case .statementCSV, .statementOFX, .statementPDF: "Statement"
        case .receipt: "Receipt"
        case .smsAlert: "Transaction alert"
        case .emailAlert: "Email alert"
        case .walletEvent: "Apple Pay"
        case .manualCash: "Cash entry"
        case .manualEntry: "Manual entry"
        }
    }

    private func relationshipTitle(_ r: RelationshipType) -> String {
        switch r {
        case .merged: "Matched because"
        case .pendingPosted: "Pending charge posted"
        case .internalTransfer: "Transfer between your accounts"
        case .creditCardPayment: "Credit-card payment"
        case .refund: "Refund linked"
        case .receipt: "Receipt matched"
        case .possibleDuplicate: "Possible duplicate"
        case .userMerged: "You merged these"
        case .userKeptSeparate: "You kept these separate"
        }
    }
}


struct EvidenceSheet: View {
    let evidence: RawEvidence
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(evidence.rawText ?? "").font(.callout.monospaced()).textSelection(.enabled)
                    Divider()
                    LabeledContent("Received", value: evidence.receivedAt.formatted())
                    LabeledContent("Parser", value: evidence.parserVersion)
                    if let file = evidence.fileReference { LabeledContent("File", value: file) }
                    Label("Stored only on this iPhone.", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Source")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct CategoryPicker: View {
    let current: String
    let merchant: String
    let onPick: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var always = true

    var body: some View {
        NavigationStack {
            List {
                Section { Toggle("Always categorize \(merchant) this way", isOn: $always) }
                ForEach(CategoryTree.topLevel) { top in
                    Section(top.name) {
                        ForEach(CategoryTree.all.filter { $0.parentID == top.id }) { node in
                            Button {
                                onPick(node.id, always)
                                dismiss()
                            } label: {
                                HStack {
                                    CategoryBadge(categoryID: node.id, size: 28)
                                    Text(node.name).foregroundStyle(.primary)
                                    Spacer()
                                    if node.id == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
    }
}
