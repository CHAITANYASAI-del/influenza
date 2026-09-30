import Foundation

/// The reconciliation engine: turns evidence into one canonical ledger.
/// Deterministic for a given input + version (spec §122).
public final class LedgerEngine {
    public static let version = "recon-1.0"

    public private(set) var state: LedgerState
    public var defaultCurrency: String

    // Indexes (rebuilt from state; never persisted).
    private var evidenceByHash: [String: UUID] = [:]
    private var observationBySourceID: [String: UUID] = [:]
    private var observationByFingerprint: [String: UUID] = [:]
    private var transactionsByAmount: [String: Set<UUID>] = [:]
    private var transactionForObservation: [UUID: UUID] = [:]

    // Tuned against the fixture suite (spec §14 says tune, don't treat as truth).
    static let autoMergeThreshold = 0.88
    static let reviewThreshold = 0.50

    public init(state: LedgerState = LedgerState(), defaultCurrency: String) {
        self.state = state
        self.defaultCurrency = defaultCurrency
        rebuildIndexes()
    }

    // MARK: - Ingestion: messages, wallet, receipts, cash

    /// A pasted/shared/automated SMS or email alert.
    @discardableResult
    public func ingestMessage(_ text: String, source: EvidenceSourceType = .smsAlert, receivedAt: Date = .now, countryCode: String? = nil,
                              merchantHint: String? = nil) -> IngestOutcome {
        let normalized = TextNormalization.collapse(text)
        let hash = Hashing.sha256("\(source.rawValue)|\(normalized)")
        if let existing = evidenceByHash[hash] {
            return .duplicate(observationsFor(evidence: existing).first.flatMap { transactionForObservation[$0] })
        }
        learnOwnerName(from: normalized)
        guard case var .financial(parsed) = FinancialMessageParser.parse(normalized, defaultCurrency: defaultCurrency) else {
            if case let .notFinancial(reason) = FinancialMessageParser.parse(normalized, defaultCurrency: defaultCurrency) { return .notFinancial(reason) }
            return .notFinancial("unreadable")
        }
        let evidence = addEvidence(source: source, text: normalized, hash: hash, receivedAt: receivedAt, originalDate: nil,
                                   countryCode: countryCode, fileReference: nil, parser: FinancialMessageParser.version,
                                   status: parsed.isComplete ? .parsed : .partiallyParsed, sourceIdentifier: merchantHint)
        if let hint = parsed.cardLast4 { state.ownAccountHints.insert(hint) }
        // Sending money to yourself (another of your own accounts) is not spending.
        if parsed.direction == .debit, [.transferOut, .purchase].contains(parsed.type), isOwner(parsed.merchantRaw) { parsed.type = .internalTransfer }
        // Merchant emails ("Your Swiggy order… paid ₹452") name the merchant in the sender, not the body.
        // A known merchant sender (Swiggy, Amazon…) beats a restaurant/seller named in the body.
        // Senders like "HDFC Bank InstaAlerts" or "AU Bank Alerts" are the bank, never the merchant.
        let usableHint = merchantHint.flatMap { h in RX.matches(#"(?i)bank|alert|card|credit|noreply|no-reply|notification|statement|upi|payments?$"#, h) ? nil : h }
        let hintIsMerchant = usableHint.flatMap(MerchantResolver.resolve) != nil && (parsed.type == .purchase || parsed.type == .refund)
        let merchant = hintIsMerchant ? usableHint : (parsed.merchantRaw ?? (parsed.type == .purchase ? usableHint : nil))
        let obs = makeObservation(evidence: evidence, source: source, sourceID: nil, accountHint: parsed.cardLast4,
                                  merchantRaw: merchant, money: parsed.money, direction: parsed.direction, date: receivedAt,
                                  postedDate: nil, reference: parsed.reference, last4: parsed.cardLast4, rail: parsed.rail,
                                  type: parsed.type, pending: parsed.pending, items: [], occurrence: 0, minuteBucket: true)
        return process(obs)
    }

    /// Apple Pay / Wallet tap (optional Shortcuts automation, or FinanceKit later).
    @discardableResult
    public func ingestWalletEvent(merchant: String, amountText: String, date: Date = .now) -> IngestOutcome {
        guard let money = AmountParser.firstAmount(in: amountText, defaultCurrency: defaultCurrency)
                ?? AmountParser.number(amountText).map({ Money(abs($0), defaultCurrency) }) else { return .notFinancial("no amount") }
        let text = "\(merchant) \(amountText)"
        let hash = Hashing.sha256("wallet|\(text)|\(Int(date.timeIntervalSince1970 / 60))")
        if evidenceByHash[hash] != nil { return .duplicate(nil) }
        let evidence = addEvidence(source: .walletEvent, text: text, hash: hash, receivedAt: date, originalDate: date, countryCode: nil,
                                   fileReference: nil, parser: FinancialMessageParser.version, status: .parsed)
        let obs = makeObservation(evidence: evidence, source: .walletEvent, sourceID: nil, accountHint: nil, merchantRaw: merchant,
                                  money: money, direction: .debit, date: date, postedDate: nil, reference: nil, last4: nil,
                                  rail: .applePay, type: .purchase, pending: .unknown, items: [], occurrence: 0, minuteBucket: true)
        return process(obs)
    }

    /// Receipt text (pasted, OCR, email). Enriches a matching transaction; if
    /// none exists, becomes a detected transaction itself.
    @discardableResult
    public func ingestReceipt(_ text: String, date: Date = .now) -> IngestOutcome {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = Hashing.sha256("receipt|\(normalized)")
        if let existing = evidenceByHash[hash] {
            return .duplicate(observationsFor(evidence: existing).first.flatMap { transactionForObservation[$0] })
        }
        let receipt = ReceiptParser.parse(normalized, defaultCurrency: defaultCurrency)
        guard let total = receipt.total else { return .notFinancial("no total on receipt") }
        let evidence = addEvidence(source: .receipt, text: normalized, hash: hash, receivedAt: date, originalDate: date, countryCode: nil,
                                   fileReference: nil, parser: FinancialMessageParser.version, status: .parsed)
        let obs = makeObservation(evidence: evidence, source: .receipt, sourceID: nil, accountHint: nil, merchantRaw: receipt.merchantRaw,
                                  money: total, direction: .debit, date: date, postedDate: nil, reference: nil, last4: nil,
                                  rail: .unknown, type: .purchase, pending: .unknown, items: receipt.items, occurrence: 0, minuteBucket: true)
        let outcome = process(obs, receiptDetail: receipt.merchantDetail)
        return outcome
    }

    /// Cash (or any manual) entry: always user-entered, never merged.
    @discardableResult
    public func addManual(amount: Decimal, currency: String, merchant: String?, categoryID: String?, date: Date = .now,
                          isCash: Bool = true, note: String? = nil) -> UUID {
        let source: EvidenceSourceType = isCash ? .manualCash : .manualEntry
        let evidence = addEvidence(source: source, text: nil, hash: Hashing.sha256(UUID().uuidString), receivedAt: .now, originalDate: date,
                                   countryCode: nil, fileReference: nil, parser: "manual", status: .parsed)
        let obs = makeObservation(evidence: evidence, source: source, sourceID: evidence.id.uuidString, accountHint: isCash ? "cash" : nil,
                                  merchantRaw: merchant, money: Money(amount, currency), direction: .debit, date: date, postedDate: nil,
                                  reference: nil, last4: nil, rail: isCash ? .cash : .unknown, type: .purchase, pending: .posted,
                                  items: [], occurrence: 0, minuteBucket: false)
        store(obs)
        var tx = newTransaction(from: obs)
        tx.note = note
        if let categoryID {
            tx.categoryID = categoryID; tx.categoryConfidence = 1; tx.categoryReason = "You chose this category."
            tx.userModifiedFields.insert("category")
        }
        save(tx)
        return tx.id
    }

    // MARK: - Statements

    public struct StatementImportError: Error { public let underlying: Error }

    /// CSV / OFX / QFX / PDF-extracted text. Idempotent: re-importing the same file adds nothing.
    @discardableResult
    public func importStatement(text: String, fileName: String, format: StatementFormat? = nil, fileData: Data? = nil) throws -> ImportJob {
        guard let format = format ?? StatementDetector.detect(fileName: fileName, text: text) else { throw StatementParseError.unsupportedFormat }
        let (source, parserVersion): (EvidenceSourceType, String) = switch format {
        case .csv: (.statementCSV, CSVStatementParser.version)
        case .ofx: (.statementOFX, OFXStatementParser.version)
        case .pdfText: (.statementPDF, TextStatementParser.version)
        }
        var job = ImportJob(id: UUID(), sourceType: source, startedAt: .now, parserVersion: parserVersion)
        let rows: [StatementRow]
        switch format {
        case .csv: rows = try CSVStatementParser.parse(text, defaultCurrency: defaultCurrency)
        case .ofx: rows = try OFXStatementParser.parse(text, defaultCurrency: defaultCurrency)
        case .pdfText: rows = try TextStatementParser.parse(text, defaultCurrency: defaultCurrency)
        }
        job.recordsSeen = rows.count

        let fileHash = Hashing.sha256(fileData ?? Data(text.utf8))
        let evidence: RawEvidence
        if let existing = evidenceByHash[fileHash], let e = state.evidence[existing] { evidence = e }
        else {
            evidence = addEvidence(source: source, text: text, hash: fileHash, receivedAt: .now, originalDate: nil,
                                   countryCode: nil, fileReference: fileName, parser: parserVersion, status: .parsed)
        }

        var occurrences: [String: Int] = [:]
        for row in rows {
            let interpreted = interpretNarration(row.description, direction: row.direction)
            if let hint = row.accountHint { state.ownAccountHints.insert(hint) }
            let baseKey = "\(Int(row.date.timeIntervalSince1970 / 86_400))|\(row.amount.stableString)|\(row.direction.rawValue)|\(row.description)"
            let occurrence = occurrences[baseKey, default: 0]
            occurrences[baseKey] = occurrence + 1
            let obs = makeObservation(
                evidence: evidence, source: source, sourceID: row.reference.map { "\(row.accountHint ?? "")|\($0)" },
                accountHint: row.accountHint, merchantRaw: interpreted.merchant ?? row.description,
                money: Money(row.amount, row.currencyCode), direction: row.direction, date: row.date, postedDate: row.postedDate,
                reference: row.reference ?? interpreted.reference, last4: row.accountHint, rail: interpreted.rail,
                type: interpreted.type, pending: .posted, items: [], occurrence: occurrence, minuteBucket: false)
            let before = state.transactions.count
            switch process(obs) {
            case .added: job.newTransactions += 1
            case .merged: job.mergedIntoExisting += 1
            case .duplicate: job.duplicatesSkipped += 1
            case .needsReview: job.needsReview += 1; job.newTransactions += state.transactions.count > before ? 1 : 0
            case .notFinancial: job.recordsRejected += 1
            }
            job.recordsParsed += 1
        }
        job.transfersExcluded = state.transactions.values.filter { $0.isInternalTransfer || $0.isCreditCardPayment }.count
        job.refundsLinked = state.records.values.filter { $0.relationshipType == .refund }.count
        job.completedAt = .now
        state.importJobs.append(job)
        refreshRecurring()
        return job
    }

    // MARK: - Core pipeline

    private func process(_ obs: FinancialObservation, receiptDetail: String? = nil) -> IngestOutcome {
        // 1. Same-source dedupe.
        if let sid = obs.sourceTransactionID, let existing = observationBySourceID["\(obs.sourceType.rawValue)|\(sid)"] {
            return .duplicate(transactionForObservation[existing])
        }
        if let existing = observationByFingerprint[obs.fingerprint] {
            return .duplicate(transactionForObservation[existing])
        }
        store(obs)

        // 2. Pending → posted.
        if obs.pendingState != .pending, let pendingTx = findPendingTwin(for: obs) {
            attach(obs, to: pendingTx, relationship: .pendingPosted, score: 1, reasons: ["Pending charge posted"])
            return .merged(pendingTx)
        }

        // 3. Receipts enrich an existing transaction.
        if obs.sourceType == .receipt, let (txID, score, reasons) = bestCandidate(for: obs), score >= Self.reviewThreshold {
            attach(obs, to: txID, relationship: .receipt, score: score, reasons: reasons)
            if var tx = state.transactions[txID] {
                tx.merchantDetail = tx.merchantDetail ?? receiptDetail
                recategorize(&tx)
                save(tx)
            }
            return .merged(txID)
        }

        // 4. Cross-source match.
        if obs.sourceType.trustLevel < 5, let (txID, score, reasons) = bestCandidate(for: obs) {
            if score >= Self.autoMergeThreshold {
                attach(obs, to: txID, relationship: .merged, score: score, reasons: reasons)
                return .merged(txID)
            }
            if score >= Self.reviewThreshold {
                var tx = newTransaction(from: obs)
                tx.merchantDetail = receiptDetail
                tx.verificationStatus = .pendingReview
                save(tx)
                addRecord(canonical: tx.id, other: txID, observations: [obs.id], type: .possibleDuplicate, score: score,
                          reasons: reasons + ["Could be the same payment — please confirm"], review: true)
                return .needsReview(tx.id)
            }
        }

        // 5. New canonical transaction + relationships.
        var tx = newTransaction(from: obs)
        tx.merchantDetail = receiptDetail
        save(tx)
        linkTransferIfPossible(tx.id)
        linkRefundIfPossible(tx.id)
        return .added(tx.id)
    }

    private func bestCandidate(for obs: FinancialObservation) -> (UUID, Double, [String])? {
        let window: TimeInterval = (obs.sourceType.isStatement ? 5 : 3) * 86_400
        var best: (UUID, Double, [String])?
        for id in transactionsByAmount[amountKey(obs.money)] ?? [] {
            guard let tx = state.transactions[id], tx.direction == obs.direction, !tx.isExcludedByUser,
                  abs(tx.transactionDate.timeIntervalSince(obs.transactionDate)) <= window else { continue }
            let existing = tx.observationIDs.compactMap { state.observations[$0] }
            // Never merge two records from the same source type (e.g. two statement lines, two alerts).
            if existing.contains(where: { $0.sourceType == obs.sourceType }) { continue }
            if existing.contains(where: { $0.sourceType.trustLevel == 5 }) { continue }   // user-entered stays separate
            if keptSeparate(tx.id, obs) { continue }
            guard let (score, reasons) = score(obs, against: tx, existing: existing) else { continue }
            if best == nil || score > best!.1 { best = (id, score, reasons) }
        }
        return best
    }

    /// Weighted evidence score, or nil on a hard conflict.
    func score(_ obs: FinancialObservation, against tx: CanonicalTransaction, existing: [FinancialObservation]) -> (Double, [String])? {
        var s = 0.0
        var reasons: [String] = []

        let refs = Set(existing.compactMap(\.referenceNumber))
        if let ref = obs.referenceNumber, !refs.isEmpty {
            if refs.contains(ref) { s += 0.50; reasons.append("Same reference number") } else { return nil }
        }
        let cards = Set(existing.compactMap(\.cardLast4))
        if let last4 = obs.cardLast4, !cards.isEmpty {
            if cards.contains(last4) { s += 0.10; reasons.append("Same card/account ending \(last4)") } else { return nil }
        }
        s += 0.30; reasons.append("Same amount")
        s += 0.05

        let obsMerchant = obs.merchantCanonical ?? obs.merchantRaw
        let txMerchant = tx.merchantName ?? tx.merchantRaw
        if isKnownMerchant(obsMerchant), isKnownMerchant(txMerchant) {
            let sim = MerchantResolver.similarity(obsMerchant, txMerchant)
            if sim >= 0.99 { s += 0.35; reasons.append("Same merchant") }
            else if sim >= 0.5 { s += 0.15; reasons.append("Similar merchant name") }
            else if MerchantResolver.resolve(obsMerchant) != nil && MerchantResolver.resolve(txMerchant) != nil { return nil } // Amazon ≠ Target
            else { s -= 0.15 }
        }

        let hours = abs(tx.transactionDate.timeIntervalSince(obs.transactionDate)) / 3600
        if hours <= 24 { s += 0.15; reasons.append("Within a day") }
        else if hours <= 72 { s += 0.08; reasons.append("Within 3 days") }
        else { s += 0.04; reasons.append("Within 5 days") }

        if PaymentRail.compatible(obs.paymentRail, tx.paymentRail) { s += 0.05 }
        else { s -= 0.10 }
        return (min(s, 1), reasons)
    }

    private func isKnownMerchant(_ m: String?) -> Bool {
        guard let m, !m.isEmpty else { return false }
        return !["upi payment", "card payment", "bank debit", "unknown"].contains(m.lowercased())
    }

    private func findPendingTwin(for obs: FinancialObservation) -> UUID? {
        for id in transactionsByAmount[amountKey(obs.money)] ?? [] {
            guard let tx = state.transactions[id], tx.isPending, tx.direction == obs.direction,
                  abs(tx.transactionDate.timeIntervalSince(obs.transactionDate)) <= 7 * 86_400,
                  MerchantResolver.similarity(tx.merchantName ?? tx.merchantRaw, obs.merchantCanonical ?? obs.merchantRaw) >= 0.5 else { continue }
            return id
        }
        return nil
    }

    // MARK: - Who is the user?

    private static let greeting = try! NSRegularExpression(pattern: #"\b(?:Dear|Hello|Hi|Hey)\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,3}?)(?=\s*[,!.:\n]|\s+(?:We|Your|Thank|Thanks|Greetings|Namaskar|This|Here|Please)\b)"#)
    private static let genericSalutations: Set<String> = ["customer", "cardholder", "card", "member", "sir", "madam", "user", "valued", "there", "team", "friend", "upi"]

    /// Banks greet the account holder by name; count those words to learn who "you" are.
    /// Public so sources can pass the greeting line of messages that aren't transactions.
    public func learnOwnerName(fromText text: String) { learnOwnerName(from: text) }

    private func learnOwnerName(from text: String) {
        let range = NSRange(text.startIndex..., in: text)
        for m in Self.greeting.matches(in: text, range: range) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let tokens = text[r].lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 && !Self.genericSalutations.contains($0) }
            guard !tokens.isEmpty, tokens.count <= 4 else { continue }
            for t in tokens { state.ownerNameTokens[t, default: 0] += 1 }
        }
    }

    /// "G CHAITANYA SAI" is the user if every meaningful word is one of the user's greeted names (and there are ≥2).
    public func isOwner(_ name: String?) -> Bool {
        guard let name else { return false }
        let known = Set(state.ownerNameTokens.filter { $0.value >= 2 }.keys)
        let tokens = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 && !["mr", "mrs", "ms"].contains($0) }
        return tokens.count >= 2 && tokens.allSatisfy(known.contains)
    }

    // MARK: - Transfers & refunds

    private func linkTransferIfPossible(_ id: UUID) {
        guard var tx = state.transactions[id] else { return }
        let transferTypes: Set<ObservationTransactionType> = [.transferOut, .transferIn, .internalTransfer, .creditCardPayment]
        let types = Set(observations(of: tx).map(\.transactionType))
        guard !types.isDisjoint(with: transferTypes) else { return }

        for otherID in transactionsByAmount[amountKey(tx.money)] ?? [] where otherID != id {
            guard var other = state.transactions[otherID], other.direction != tx.direction, other.flowType == .transfer,
                  !other.linkedTransactionIDs.contains(id),
                  abs(other.transactionDate.timeIntervalSince(tx.transactionDate)) <= 72 * 3600 else { continue }
            let otherTypes = Set(observations(of: other).map(\.transactionType))
            let ccPayment = types.contains(.creditCardPayment) || otherTypes.contains(.creditCardPayment)
            let hints = [tx.accountHint, other.accountHint].compactMap { $0 }
            let bothOwned = hints.count == 2 && hints[0] != hints[1] && hints.allSatisfy(state.ownAccountHints.contains)
            guard ccPayment || bothOwned || types.contains(.internalTransfer) || otherTypes.contains(.internalTransfer) else { continue }

            tx.isInternalTransfer = true; other.isInternalTransfer = true
            tx.isCreditCardPayment = ccPayment; other.isCreditCardPayment = ccPayment
            tx.linkedTransactionIDs.append(otherID); other.linkedTransactionIDs.append(id)
            save(tx); save(other)
            addRecord(canonical: id, other: otherID, observations: tx.observationIDs + other.observationIDs,
                      type: ccPayment ? .creditCardPayment : .internalTransfer, score: 0.99,
                      reasons: ["Same amount", "Opposite directions within 3 days", ccPayment ? "Credit-card bill payment" : "Both accounts are yours"], review: false)
            return
        }
    }

    private func linkRefundIfPossible(_ id: UUID) {
        guard var refund = state.transactions[id], refund.isRefund else { return }
        let candidates = state.transactions.values.filter { p in
            p.direction == .debit && p.currencyCode == refund.currencyCode && p.flowType == .purchase
                && p.transactionDate <= refund.transactionDate
                && refund.transactionDate.timeIntervalSince(p.transactionDate) <= 180 * 86_400
                && p.amount >= refund.amount
                && MerchantResolver.similarity(p.merchantName ?? p.merchantRaw, refund.merchantName ?? refund.merchantRaw) >= 0.6
                && refundedTotal(p) + refund.amount <= p.amount
        }.sorted { a, b in
            (a.amount == refund.amount ? 0 : 1, -a.transactionDate.timeIntervalSince1970) < (b.amount == refund.amount ? 0 : 1, -b.transactionDate.timeIntervalSince1970)
        }
        var chosen = candidates.first
        if chosen == nil, !isKnownMerchant(refund.merchantName ?? refund.merchantRaw) {
            // "USD 85.89 spent on your card is credited back" — no merchant, so match amount + card.
            chosen = state.transactions.values.filter { p in
                p.direction == .debit && p.flowType == .purchase && p.currencyCode == refund.currencyCode && p.amount == refund.amount
                    && p.transactionDate <= refund.transactionDate && refund.transactionDate.timeIntervalSince(p.transactionDate) <= 60 * 86_400
                    && (refund.accountHint == nil || p.accountHint == refund.accountHint) && p.refundLinkIDs.isEmpty
            }.max { $0.transactionDate < $1.transactionDate }
        }
        guard var purchase = chosen else { return }
        if refund.merchantName == nil { refund.merchantName = purchase.merchantName; refund.merchantRaw = purchase.merchantRaw }
        refund.refundLinkIDs.append(purchase.id)
        purchase.refundLinkIDs.append(refund.id)
        refund.categoryID = purchase.categoryID
        refund.categoryReason = "Refund of \(purchase.displayMerchant) — counted against that spend."
        save(refund); save(purchase)
        addRecord(canonical: purchase.id, other: refund.id, observations: refund.observationIDs, type: .refund, score: 0.95,
                  reasons: ["Same merchant", purchase.amount == refund.amount ? "Same amount" : "Partial refund", "After the purchase"], review: false)
    }

    private func refundedTotal(_ purchase: CanonicalTransaction) -> Decimal {
        purchase.refundLinkIDs.compactMap { state.transactions[$0]?.amount }.reduce(0, +)
    }

    // MARK: - Building transactions

    private func newTransaction(from obs: FinancialObservation) -> CanonicalTransaction {
        let flow = flowType(for: obs.transactionType)
        var tx = CanonicalTransaction(
            id: UUID(), amount: obs.amount, currencyCode: obs.currencyCode, direction: obs.direction,
            transactionDate: obs.transactionDate, postedDate: obs.postedDate,
            merchantName: obs.merchantCanonical, merchantDetail: nil, merchantRaw: obs.merchantRaw,
            accountHint: obs.sourceAccountHint ?? obs.cardLast4, paymentRail: obs.paymentRail, flowType: flow,
            categoryID: "other.unknown", categoryConfidence: 0, categoryReason: "",
            verificationStatus: verification(for: [obs]), observationIDs: [obs.id], linkedTransactionIDs: [], recurringSeriesID: nil,
            isInternalTransfer: obs.transactionType == .internalTransfer || obs.transactionType == .creditCardPayment,
            isCreditCardPayment: obs.transactionType == .creditCardPayment,
            isRefund: obs.transactionType == .refund, isPending: obs.pendingState == .pending, refundLinkIDs: [],
            userModifiedFields: [], isExcludedByUser: false, note: nil, createdAt: .now, updatedAt: .now)
        recategorize(&tx)
        return tx
    }

    private func attach(_ obs: FinancialObservation, to txID: UUID, relationship: RelationshipType, score: Double, reasons: [String]) {
        guard var tx = state.transactions[txID] else { return }
        tx.observationIDs.append(obs.id)
        transactionForObservation[obs.id] = txID
        let all = observations(of: tx)
        // Amount is never changed by lower-trust evidence (exact-amount matching guarantees equality anyway).
        if obs.pendingState != .pending { tx.isPending = false }
        if let posted = obs.postedDate ?? (obs.sourceType.isStatement ? obs.transactionDate : nil) { tx.postedDate = posted }
        // Best merchant: from the most trusted observation that has a recognised one.
        if !tx.userModifiedFields.contains("merchant"),
           let best = all.filter({ $0.merchantCanonical != nil }).min(by: { merchantRank($0) < merchantRank($1) }) {
            tx.merchantName = best.merchantCanonical
            tx.merchantRaw = best.merchantRaw
        }
        if tx.paymentRail == .unknown { tx.paymentRail = obs.paymentRail }
        if tx.accountHint == nil { tx.accountHint = obs.sourceAccountHint ?? obs.cardLast4 }
        tx.verificationStatus = verification(for: all)
        recategorize(&tx)
        tx.updatedAt = .now
        save(tx)
        addRecord(canonical: txID, other: nil, observations: tx.observationIDs, type: relationship, score: score, reasons: reasons, review: false)
    }

    /// Wallet/receipt names are the cleanest; then dictionary matches from statements; then alerts.
    private func merchantRank(_ o: FinancialObservation) -> Int {
        let resolved = MerchantResolver.resolve(o.merchantRaw) != nil ? 0 : 10
        switch o.sourceType {
        case .walletEvent, .receipt: return resolved + 0
        case .financeKit, .bankFeed: return resolved + 1
        default: return resolved + o.sourceType.trustLevel
        }
    }

    private func recategorize(_ tx: inout CanonicalTransaction) {
        guard !tx.userModifiedFields.contains("category"), tx.refundLinkIDs.isEmpty || !tx.isRefund else { return }
        let obs = observations(of: tx)
        let type = obs.map(\.transactionType).first { $0 != .purchase && $0 != .unknown } ?? obs.first?.transactionType ?? .purchase
        let items = obs.flatMap(\.receiptItems)
        let decision = CategorizationEngine.categorize(merchantRaw: tx.merchantRaw, merchantName: tx.merchantName, flow: tx.flowType,
                                                      type: type, items: items, userRules: state.userRules, rail: tx.paymentRail)
        tx.categoryID = decision.categoryID
        tx.categoryConfidence = decision.confidence
        tx.categoryReason = decision.reason
    }

    private func verification(for obs: [FinancialObservation]) -> VerificationStatus {
        let best = obs.map(\.sourceType.trustLevel).min() ?? 5
        if best <= 2 { return .verified }
        if best == 5 { return .userEntered }
        return .detected
    }

    private func flowType(for type: ObservationTransactionType) -> FlowType {
        switch type {
        case .purchase: .purchase
        case .refund: .refund
        case .transferOut, .transferIn, .internalTransfer, .creditCardPayment: .transfer
        case .withdrawal: .withdrawal
        case .deposit: .deposit
        case .fee: .fee
        case .salary, .interest, .cashback, .income: .income
        case .billPayment: .billPayment
        case .unknown: .unknown
        }
    }

    // MARK: - Observations & evidence

    private func interpretNarration(_ text: String, direction: Direction) -> (merchant: String?, rail: PaymentRail, type: ObservationTransactionType, reference: String?) {
        let lower = text.lowercased()
        let isRefund = RX.matches(#"refund|reversal|reversed|chargeback|\brev\b"#, lower) && direction == .credit
        let rail = FinancialMessageParser.detectRail(lower)
        let type = FinancialMessageParser.detectType(lower, direction: direction, rail: rail, isRefund: isRefund)
        let merchant = FinancialMessageParser.extractMerchant(text, type: type)
        return (merchant, rail, type, FinancialMessageParser.extractReference(text))
    }

    private func makeObservation(evidence: RawEvidence, source: EvidenceSourceType, sourceID: String?, accountHint: String?,
                                 merchantRaw: String?, money: Money, direction: Direction, date: Date, postedDate: Date?,
                                 reference: String?, last4: String?, rail: PaymentRail, type: ObservationTransactionType,
                                 pending: PendingState, items: [ReceiptItem], occurrence: Int, minuteBucket: Bool) -> FinancialObservation {
        let canonical = MerchantResolver.resolve(merchantRaw)?.name ?? merchantRaw.map(MerchantResolver.cleanDisplayName)
        let bucket = minuteBucket ? Int(date.timeIntervalSince1970 / 60) : Int(date.timeIntervalSince1970 / 86_400)
        let fingerprint = Hashing.sha256([
            source.rawValue, sourceID ?? "", accountHint ?? "", "\(bucket)", money.amount.stableString, money.currencyCode,
            MerchantResolver.key(merchantRaw), rail.rawValue, reference ?? "", last4 ?? "", direction.rawValue, "\(occurrence)",
        ].joined(separator: "|"))
        return FinancialObservation(
            id: UUID(), evidenceID: evidence.id, sourceType: source, sourceTransactionID: sourceID, sourceAccountHint: accountHint,
            merchantRaw: merchantRaw, merchantCanonical: canonical, amount: money.amount, currencyCode: money.currencyCode,
            direction: direction, transactionDate: date, postedDate: postedDate, referenceNumber: reference, authorizationCode: nil,
            cardLast4: last4, paymentRail: rail, transactionType: type, pendingState: pending, countryCode: nil,
            receiptItems: items, parserVersion: evidence.parserVersion, fingerprint: fingerprint)
    }

    private func addEvidence(source: EvidenceSourceType, text: String?, hash: String, receivedAt: Date, originalDate: Date?,
                             countryCode: String?, fileReference: String?, parser: String, status: ParseStatus,
                             sourceIdentifier: String? = nil) -> RawEvidence {
        let e = RawEvidence(id: UUID(), sourceType: source, sourceIdentifier: sourceIdentifier, receivedAt: receivedAt, originalDate: originalDate,
                            countryCode: countryCode, rawText: text, rawDataHash: hash, fileReference: fileReference,
                            parserVersion: parser, parseStatus: status)
        state.evidence[e.id] = e
        evidenceByHash[hash] = e.id
        return e
    }

    private func store(_ obs: FinancialObservation) {
        state.observations[obs.id] = obs
        if let sid = obs.sourceTransactionID { observationBySourceID["\(obs.sourceType.rawValue)|\(sid)"] = obs.id }
        observationByFingerprint[obs.fingerprint] = obs.id
    }

    private func save(_ tx: CanonicalTransaction) {
        state.transactions[tx.id] = tx
        transactionsByAmount[amountKey(tx.money), default: []].insert(tx.id)
        for o in tx.observationIDs { transactionForObservation[o] = tx.id }
    }

    private func addRecord(canonical: UUID, other: UUID?, observations: [UUID], type: RelationshipType, score: Double, reasons: [String], review: Bool) {
        let r = ReconciliationRecord(id: UUID(), canonicalTransactionID: canonical, otherTransactionID: other, sourceObservationIDs: observations,
                                     relationshipType: type, score: score, humanReadableReasons: reasons, engineVersion: Self.version,
                                     createdAt: .now, needsReview: review)
        state.records[r.id] = r
    }

    private func keptSeparate(_ txID: UUID, _ obs: FinancialObservation) -> Bool {
        state.records.values.contains { $0.relationshipType == .userKeptSeparate && ($0.canonicalTransactionID == txID || $0.otherTransactionID == txID)
            && $0.sourceObservationIDs.contains(obs.id) }
    }

    func observations(of tx: CanonicalTransaction) -> [FinancialObservation] { tx.observationIDs.compactMap { state.observations[$0] } }
    private func observationsFor(evidence id: UUID) -> [UUID] { state.observations.values.filter { $0.evidenceID == id }.map(\.id) }
    private func amountKey(_ m: Money) -> String { "\(m.currencyCode)|\(m.amount.stableString)" }

    private func rebuildIndexes() {
        evidenceByHash = Dictionary(state.evidence.values.map { ($0.rawDataHash, $0.id) }, uniquingKeysWith: { a, _ in a })
        for o in state.observations.values {
            if let sid = o.sourceTransactionID { observationBySourceID["\(o.sourceType.rawValue)|\(sid)"] = o.id }
            observationByFingerprint[o.fingerprint] = o.id
        }
        for tx in state.transactions.values { save(tx) }
    }

    // MARK: - User actions (spec §49, §92)

    public var reviewItems: [ReconciliationRecord] {
        state.records.values.filter(\.needsReview).sorted { $0.createdAt > $1.createdAt }
    }

    /// Resolve a "possible duplicate" review: merge the two, or keep them apart forever.
    public func resolveReview(_ recordID: UUID, merge: Bool) {
        guard var record = state.records[recordID], record.needsReview else { return }
        record.needsReview = false
        let newID = record.canonicalTransactionID
        if merge, let otherID = record.otherTransactionID, let newTx = state.transactions[newID], var keep = state.transactions[otherID] {
            keep.observationIDs += newTx.observationIDs
            for o in newTx.observationIDs { transactionForObservation[o] = otherID }
            state.transactions[newID] = nil
            transactionsByAmount[amountKey(newTx.money)]?.remove(newID)
            keep.verificationStatus = verification(for: observations(of: keep))
            save(keep)
            record.relationshipType = .userMerged
            record.canonicalTransactionID = otherID
            record.otherTransactionID = nil
        } else if var tx = state.transactions[newID] {
            tx.verificationStatus = verification(for: observations(of: tx))
            save(tx)
            linkTransferIfPossible(newID)
            linkRefundIfPossible(newID)
            record.relationshipType = .userKeptSeparate
        }
        state.records[recordID] = record
    }

    public func setCategory(_ txID: UUID, to categoryID: String, alwaysForMerchant: Bool) {
        guard var tx = state.transactions[txID] else { return }
        tx.categoryID = categoryID
        tx.categoryConfidence = 1
        tx.categoryReason = "You chose this category."
        tx.userModifiedFields.insert("category")
        save(tx)
        guard alwaysForMerchant else { return }
        let key = MerchantResolver.key(tx.merchantName ?? tx.merchantRaw)
        guard !key.isEmpty else { return }
        state.userRules[key] = categoryID
        for var other in state.transactions.values where other.id != txID && !other.userModifiedFields.contains("category")
            && MerchantResolver.key(other.merchantName ?? other.merchantRaw) == key {
            recategorize(&other)
            save(other)
        }
    }

    public func renameMerchant(_ txID: UUID, to name: String) {
        guard var tx = state.transactions[txID] else { return }
        tx.merchantName = name
        tx.userModifiedFields.insert("merchant")
        recategorize(&tx)
        save(tx)
    }

    public func markAsTransfer(_ txID: UUID) {
        guard var tx = state.transactions[txID] else { return }
        tx.flowType = .transfer
        tx.isInternalTransfer = true
        tx.categoryID = "financial.transfer"
        tx.categoryReason = "You marked this as a transfer."
        tx.userModifiedFields.formUnion(["flow", "category"])
        save(tx)
    }

    public func setExcluded(_ txID: UUID, _ excluded: Bool) {
        guard var tx = state.transactions[txID] else { return }
        tx.isExcludedByUser = excluded
        tx.userModifiedFields.insert("excluded")
        save(tx)
    }

    public func setNote(_ txID: UUID, _ note: String?) {
        guard var tx = state.transactions[txID] else { return }
        tx.note = note
        save(tx)
    }

    public func deleteTransaction(_ txID: UUID) {
        guard let tx = state.transactions[txID] else { return }
        state.transactions[txID] = nil
        transactionsByAmount[amountKey(tx.money)]?.remove(txID)
        // Evidence & observations for manual entries go too; source evidence stays for audit.
        for o in observations(of: tx) where o.sourceType.trustLevel == 5 {
            state.observations[o.id] = nil
            state.evidence[o.evidenceID] = nil
        }
    }

    /// Start over but keep what the user taught us ("always categorize X as Y").
    public func reset(keepingUserRules: Bool) {
        let rules = state.userRules, owner = state.ownerNameTokens
        deleteAll()
        if keepingUserRules { state.userRules = rules; state.ownerNameTokens = owner }
    }

    /// Once we know the user's name, fix earlier payments that went to their own other account.
    @discardableResult
    public func reclassifyOwnerTransfers() -> Int {
        var changed = 0
        for (id, var tx) in state.transactions where tx.direction == .debit && !tx.isInternalTransfer && !tx.isCreditCardPayment
            && !tx.userModifiedFields.contains("category") && [.purchase, .transfer].contains(tx.flowType) && isOwner(tx.merchantName ?? tx.merchantRaw) {
            tx.flowType = .transfer
            tx.isInternalTransfer = true
            tx.categoryID = "financial.transfer"
            tx.categoryConfidence = 0.9
            tx.categoryReason = "Sent to your own account — not spending."
            state.transactions[id] = tx
            changed += 1
        }
        return changed
    }

    public func deleteAll() {
        state = LedgerState()
        evidenceByHash = [:]; observationBySourceID = [:]; observationByFingerprint = [:]
        transactionsByAmount = [:]; transactionForObservation = [:]
    }

    /// Everything that explains one transaction (spec §90).
    public func explanation(for txID: UUID) -> (evidence: [(RawEvidence, FinancialObservation)], records: [ReconciliationRecord]) {
        guard let tx = state.transactions[txID] else { return ([], []) }
        let pairs = observations(of: tx).compactMap { o in state.evidence[o.evidenceID].map { ($0, o) } }
        let records = state.records.values.filter { $0.canonicalTransactionID == txID || $0.otherTransactionID == txID }
            .sorted { $0.createdAt < $1.createdAt }
        return (pairs, records)
    }

    // MARK: - Recurring

    public func refreshRecurring(now: Date = .now) {
        state.recurring = RecurringDetector.detect(Array(state.transactions.values), now: now)
        let byTx = Dictionary(state.recurring.flatMap { s in s.transactionIDs.map { ($0, s.id) } }, uniquingKeysWith: { a, _ in a })
        // Same merchant, same amount, every month → a subscription (unless it's a bill, a person, or you chose otherwise).
        let subscriptionSeries = Set(state.recurring.filter { s in
            guard s.cadence == .monthly, Set(s.transactionIDs.compactMap { state.transactions[$0]?.amount }).count == 1 else { return false }
            // Apps and bills: two identical monthly charges are enough. Food/shopping need three (coincidences happen).
            let top = s.transactionIDs.first.flatMap { state.transactions[$0] }.flatMap { CategoryTree.node($0.categoryID)?.topLevelID } ?? "other"
            return s.transactionIDs.count >= (["entertainment", "bills", "other"].contains(top) ? 2 : 3)
        }.map(\.id))
        for (id, var tx) in state.transactions {
            tx.recurringSeriesID = byTx[id]
            let top = CategoryTree.node(tx.categoryID)?.topLevelID ?? "other"
            if let series = byTx[id], subscriptionSeries.contains(series), !tx.userModifiedFields.contains("category"),
               tx.flowType == .purchase, !["bills", "people", "financial", "income", "health", "education"].contains(top) {
                tx.categoryID = "bills.subscriptions"
                tx.categoryConfidence = 0.85
                tx.categoryReason = "Same amount to \(tx.displayMerchant) every month — looks like a subscription."
            }
            state.transactions[id] = tx
        }
    }
}
