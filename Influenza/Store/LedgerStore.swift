import Foundation
import LedgerCore
import Observation

/// App-facing façade over LedgerCore. Views never parse, reconcile or persist;
/// they call use-case methods here (spec §39).
@MainActor
@Observable
final class LedgerStore {
    static let shared = LedgerStore()

    private(set) var engine: LedgerEngine
    /// Bumped on every change so SwiftUI re-reads derived data.
    private(set) var revision = 0
    private(set) var lastImport: ImportJob?
    var loadError: String?

    @ObservationIgnored private let repository = LedgerRepository()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var widgetTask: Task<Void, Never>?

    private init() {
        let currency = Fmt.defaultCurrency
        do {
            engine = LedgerEngine(state: try repository.load() ?? LedgerState(), defaultCurrency: currency)
        } catch {
            engine = LedgerEngine(defaultCurrency: currency)
            loadError = "Your ledger couldn't be read. A backup was kept."
            repository.quarantineCorruptFile()
        }
    }

    // MARK: Read models

    var transactions: [CanonicalTransaction] {
        _ = revision
        return engine.state.transactions.values.sorted { $0.transactionDate > $1.transactionDate }
    }

    func transaction(_ id: UUID) -> CanonicalTransaction? { _ = revision; return engine.state.transactions[id] }
    var reviewItems: [ReconciliationRecord] { _ = revision; return engine.reviewItems }
    var uncategorized: [CanonicalTransaction] {
        transactions.filter { $0.categoryID == "other.unknown" && AggregationService.isSpending($0) && !$0.userModifiedFields.contains("category") }
    }
    var reviewCount: Int { reviewItems.count + uncategorized.count }
    var recurring: [RecurringSeries] { _ = revision; return engine.state.recurring }
    var isEmpty: Bool { _ = revision; return engine.state.transactions.isEmpty }
    var currencies: [String] {
        _ = revision
        let counts = Dictionary(grouping: engine.state.transactions.values, by: \.currencyCode).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    func summary(month offset: Int = 0, currency: String, throughSameDay: Bool = false) -> PeriodSummary {
        _ = revision
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .month, value: offset, to: .now), let month = cal.dateInterval(of: .month, for: anchor) else {
            return PeriodSummary(currencyCode: currency)
        }
        var end = month.end
        if throughSameDay, offset != 0, let same = cal.date(byAdding: .month, value: offset, to: .now) { end = min(month.end, same) }
        return engine.summaries(from: month.start, to: end)[currency] ?? PeriodSummary(currencyCode: currency)
    }

    func summary(from: Date, to: Date, currency: String) -> PeriodSummary {
        _ = revision
        return engine.summaries(from: from, to: to)[currency] ?? PeriodSummary(currencyCode: currency)
    }

    func explanation(_ id: UUID) -> (evidence: [(RawEvidence, FinancialObservation)], records: [ReconciliationRecord]) {
        _ = revision
        return engine.explanation(for: id)
    }

    // MARK: Use cases

    @discardableResult
    func pasteAlert(_ text: String, source: EvidenceSourceType = .smsAlert) -> IngestOutcome {
        defer { changed() }
        engine.defaultCurrency = Fmt.defaultCurrency
        return engine.ingestMessage(text, source: source, receivedAt: .now)
    }

    /// Automatic email capture. Evidence is the focused transaction sentence only.
    @discardableResult
    func ingestEmail(_ focusedText: String, date: Date, senderName: String?) -> IngestOutcome {
        defer { changed() }
        engine.defaultCurrency = Fmt.defaultCurrency
        return engine.ingestMessage(focusedText, source: .emailAlert, receivedAt: date, merchantHint: senderName)
    }

    func learnOwner(from text: String) { engine.learnOwnerName(fromText: text) }

    @discardableResult
    func reclassifyOwnerTransfers() -> Int {
        let n = engine.reclassifyOwnerTransfers()
        if n > 0 { changed() }
        return n
    }

    /// Parse without saving, for the "Detected ₹1,299 · Amazon · UPI" preview.
    func preview(_ text: String) -> MessageParseResult {
        FinancialMessageParser.parse(text, defaultCurrency: Fmt.defaultCurrency)
    }

    @discardableResult
    func addReceipt(_ text: String, date: Date = .now) -> IngestOutcome {
        defer { changed() }
        engine.defaultCurrency = Fmt.defaultCurrency
        return engine.ingestReceipt(text, date: date)
    }

    @discardableResult
    func walletTap(merchant: String, amount: String) -> IngestOutcome {
        defer { changed() }
        return engine.ingestWalletEvent(merchant: merchant, amountText: amount, date: .now)
    }

    @discardableResult
    func addCash(amount: Decimal, currency: String, merchant: String?, categoryID: String?, date: Date) -> UUID {
        defer { changed() }
        return engine.addManual(amount: amount, currency: currency, merchant: merchant, categoryID: categoryID, date: date, isCash: true)
    }

    func importStatement(text: String, fileName: String, format: StatementFormat?, data: Data?) throws -> ImportJob {
        engine.defaultCurrency = Fmt.defaultCurrency
        let job = try engine.importStatement(text: text, fileName: fileName, format: format, fileData: data)
        lastImport = job
        changed()
        return job
    }

    func resolveReview(_ id: UUID, merge: Bool) { engine.resolveReview(id, merge: merge); changed() }
    func setCategory(_ id: UUID, _ category: String, always: Bool) { engine.setCategory(id, to: category, alwaysForMerchant: always); changed() }
    func renameMerchant(_ id: UUID, _ name: String) { engine.renameMerchant(id, to: name); changed() }
    func markTransfer(_ id: UUID) { engine.markAsTransfer(id); changed() }
    func setExcluded(_ id: UUID, _ excluded: Bool) { engine.setExcluded(id, excluded); changed() }
    func setNote(_ id: UUID, _ note: String?) { engine.setNote(id, note); changed() }
    func delete(_ id: UUID) { engine.deleteTransaction(id); changed() }

    func deleteAll() {
        engine.deleteAll()
        changed(immediate: true)
    }

    /// Re-runs every source through the current parser (spec §121: version everything,
    /// reprocess evidence when logic improves). Cash entries and user rules are kept.
    @discardableResult
    func prepareReprocess() -> (cash: Int, statements: Int) {
        struct Cash { let amount: Decimal; let currency: String; let merchant: String?; let category: String; let date: Date; let note: String? }
        let cash = engine.state.transactions.values.filter { $0.verificationStatus == .userEntered }.map {
            Cash(amount: $0.amount, currency: $0.currencyCode, merchant: $0.merchantName ?? $0.merchantRaw, category: $0.categoryID, date: $0.transactionDate, note: $0.note)
        }
        let statements = engine.state.evidence.values.filter { $0.sourceType.isStatement && $0.rawText != nil }
        let messages = engine.state.evidence.values.filter { [.emailAlert, .smsAlert, .walletEvent, .receipt].contains($0.sourceType) && $0.rawText != nil }
            .sorted { $0.receivedAt < $1.receivedAt }
        engine.reset(keepingUserRules: true)
        for c in cash {
            let id = engine.addManual(amount: c.amount, currency: c.currency, merchant: c.merchant, categoryID: c.category, date: c.date, isCash: true)
            if let note = c.note { engine.setNote(id, note) }
        }
        for s in statements.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            let format: StatementFormat = s.sourceType == .statementOFX ? .ofx : (s.sourceType == .statementPDF ? .pdfText : .csv)
            _ = try? engine.importStatement(text: s.rawText!, fileName: s.fileReference ?? "statement", format: format)
        }
        for m in messages {
            switch m.sourceType {
            case .receipt: engine.ingestReceipt(m.rawText!, date: m.originalDate ?? m.receivedAt)
            case .walletEvent:
                // Stored as "Merchant amount"; the amount is the last token.
                let parts = m.rawText!.split(separator: " ")
                if let amount = parts.last { engine.ingestWalletEvent(merchant: parts.dropLast().joined(separator: " "), amountText: String(amount), date: m.receivedAt) }
            default: engine.ingestMessage(m.rawText!, source: m.sourceType, receivedAt: m.receivedAt, merchantHint: m.sourceIdentifier)
            }
        }
        UserDefaults.standard.set(FinancialMessageParser.version, forKey: "ledgerParserVersion")
        changed(immediate: true)
        return (cash.count, statements.count)
    }

    var needsReprocess: Bool {
        UserDefaults.standard.string(forKey: "ledgerParserVersion") != FinancialMessageParser.version && !isEmpty
    }

    func refreshOnActivate() {
        engine.refreshRecurring()
        revision += 1
        writeWidgetSnapshot()
    }

    // MARK: Export (spec §71)

    func exportCSV() -> Data {
        var lines = ["date,merchant,merchant_detail,amount,currency,direction,flow,category,rail,status,sources,note"]
        let iso = ISO8601DateFormatter()
        for t in transactions {
            let sources = engine.state.transactions[t.id].map { tx in
                tx.observationIDs.compactMap { engine.state.observations[$0]?.sourceType.rawValue }.joined(separator: "+")
            } ?? ""
            let fields = [iso.string(from: t.transactionDate), t.displayMerchant, t.merchantDetail ?? "", "\(t.amount)", t.currencyCode,
                          t.direction.rawValue, t.flowType.rawValue, t.categoryID, t.paymentRail.rawValue, t.verificationStatus.rawValue,
                          sources, t.note ?? ""]
            lines.append(fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(engine.state)
    }

    // MARK: Persistence

    private func changed(immediate: Bool = false) {
        revision += 1
        widgetTask?.cancel()
        widgetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.writeWidgetSnapshot()
        }
        saveTask?.cancel()
        let state = engine.state
        let repository = repository
        saveTask = Task.detached(priority: .utility) {
            if !immediate { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            do { try repository.save(state) } catch { SafeLog.error("ledger save failed", error) }
        }
    }
}

/// Encrypted-at-rest JSON repository with atomic writes (spec §41, §68).
/// NOTE: a SwiftData repository is the planned upgrade for 100k+ ledgers;
/// the engine is persistence-agnostic, so this swaps without touching LedgerCore.
struct LedgerRepository: Sendable {
    private var url: URL {
        URL.applicationSupportDirectory.appending(path: "Ledger", directoryHint: .isDirectory).appending(path: "ledger.json")
    }

    func load() throws -> LedgerState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LedgerState.self, from: Data(contentsOf: url))
    }

    func save(_ state: LedgerState) throws {
        let dir = url.deletingLastPathComponent()
        // "Until first unlock" so the optional Shortcuts action can log while the phone is locked.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func quarantineCorruptFile() {
        let bad = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: bad)
    }
}
