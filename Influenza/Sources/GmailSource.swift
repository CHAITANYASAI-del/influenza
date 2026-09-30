import BackgroundTasks
import Foundation
import LedgerCore
import Observation

/// Automatic capture from bank/card/merchant alert emails, read ON the iPhone.
/// Gmail search narrows to transaction-looking mail; each message is reduced to
/// the one sentence describing the payment before it touches the ledger. Nothing
/// is sent anywhere except Google's own API.
@MainActor
@Observable
final class GmailSource {
    static let shared = GmailSource()
    static let refreshTaskID = "com.chaitanyasai.influenza.refresh"

    enum Status: Equatable { case notConnected, idle, syncing(found: Int, processed: Int), needsReconnect, failed(String) }

    private(set) var status: Status = GoogleAuth.shared.isSignedIn ? .idle : .notConnected
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "gmailLastSync") as? Date
    private(set) var lastAdded = 0
    private(set) var recentChecks: [EmailCheck] = {
        guard let data = UserDefaults.standard.data(forKey: "gmailRecentChecks") else { return [] }
        return (try? JSONDecoder().decode([EmailCheck].self, from: data)) ?? []
    }()

    private func record(_ checks: [EmailCheck]) {
        guard !checks.isEmpty else { return }
        recentChecks = Array((checks.sorted { $0.date > $1.date } + recentChecks).prefix(60))
        UserDefaults.standard.set(try? JSONEncoder().encode(recentChecks), forKey: "gmailRecentChecks")
    }

    /// The user says a skipped email *was* a payment: parse it without the transaction gate.
    func addAnyway(_ check: EmailCheck) -> Bool {
        guard let text = check.excerpt else { return false }
        let outcome = LedgerStore.shared.ingestEmail("\(check.subject). \(text)", date: check.date, senderName: check.sender)
        let ok: Bool
        switch outcome { case .added, .merged, .needsReview: ok = true; default: ok = false }
        if ok, let i = recentChecks.firstIndex(of: check) {
            recentChecks[i].outcome = .added
            recentChecks[i].detail = "Added by you"
            recentChecks[i].excerpt = nil
            UserDefaults.standard.set(try? JSONEncoder().encode(recentChecks), forKey: "gmailRecentChecks")
        }
        return ok
    }

    enum ToastEvent: Equatable { case started, finished(added: Int) }
    /// Drives the Home toast. Background polls only emit when something new arrived.
    private(set) var toastEvent: ToastEvent?
    var email: String? { UserDefaults.standard.string(forKey: "googleEmail") }
    var isConnected: Bool { GoogleAuth.shared.isSignedIn }

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var processedIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "gmailProcessedIDs") ?? [])

    /// Transaction-looking mail only. Promotions/social excluded server-side.
    private static let query = #"(debited OR credited OR spent OR "transaction alert" OR txn OR withdrawn OR "payment of" OR "you paid" OR purchase OR refund OR "thank you for using" OR "order confirmed" OR receipt OR "total paid" OR "amount paid" OR "payment successful" OR "paid") -category:promotions -category:social"#

    // MARK: Connect

    func connect() async {
        do {
            _ = try await GoogleAuth.shared.signIn()
            status = .idle
            await sync(firstRun: true)
        } catch GoogleAuth.AuthError.notConfigured {
            status = .failed("Google sign-in isn't set up in this build yet.")
        } catch {
            status = isConnected ? .idle : .notConnected
        }
    }

    func disconnect() async {
        running?.cancel()
        await GoogleAuth.shared.signOut()
        UserDefaults.standard.removeObject(forKey: "gmailLastSync")
        lastSync = nil
        status = .notConnected
    }

    // MARK: Re-read everything with an improved parser

    func rereadAll() async {
        // 1. Instant, deterministic: re-run every stored email through today's parser.
        LedgerStore.shared.prepareReprocess()
        // 2. Then look again at emails the old parser skipped (dedupe drops anything already stored).
        processedIDs = []
        persistProcessed()
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: "gmailLastSync")
        await sync(firstRun: true)
    }

    // MARK: Foreground polling (iOS only lets background refresh run a few times a day)

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func startForegroundPolling(every seconds: Double = 15) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isConnected { await self.sync() }
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopForegroundPolling() { pollTask?.cancel(); pollTask = nil }

    // MARK: Sync

    func syncIfStale() {
        guard isConnected, running == nil else { return }
        if LedgerStore.shared.needsReprocess {
            running = Task { await rereadAll(); running = nil }
            return
        }
        running = Task { await sync(firstRun: false); running = nil }
    }

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "gmailPendingIDs") ?? [])
    @ObservationIgnored private var pendingAttempts: [String: Int] = UserDefaults.standard.dictionary(forKey: "gmailPendingAttempts") as? [String: Int] ?? [:]

    /// Joins a running sync instead of starting a second one. The work runs in a task
    /// owned by GmailSource, so a cancelled caller (pull-to-refresh) never stops it halfway.
    func sync(firstRun: Bool = false, userInitiated: Bool = false) async {
        guard isConnected else { status = .notConnected; return }
        let loud = userInitiated || firstRun
        if loud { toastEvent = .started }
        if let running = syncTask { await running.value } else {
            let task = Task { await self.performSync(firstRun: firstRun) }
            syncTask = task
            await task.value
            syncTask = nil
        }
        if loud || lastAdded > 0 {
            toastEvent = nil   // re-trigger even if the value is the same as last time
            toastEvent = .finished(added: lastAdded)
        }
    }

    private func performSync(firstRun: Bool) async {
        let startedAt = Date.now
        let quiet = !firstRun && lastSync != nil   // background checks don't flash progress UI
        if !quiet { status = .syncing(found: 0, processed: 0) }
        do {
            let token = try await GoogleAuth.shared.validAccessToken()
            let window = lastSync.map { "after:\(Int($0.addingTimeInterval(-2 * 86_400).timeIntervalSince1970))" } ?? "newer_than:1y"
            let listed = try await listMessageIDs(query: "\(Self.query) \(window)", token: token, cap: firstRun ? 5_000 : 1_000)
            // Anything that failed last time is always retried, whatever the date window.
            let ids = Array(Set(listed).union(pendingIDs)).filter { !processedIDs.contains($0) }
            if ids.isEmpty {
                finish(startedAt: startedAt, added: 0)
                return
            }
            if firstRun { status = .syncing(found: ids.count, processed: 0) }
            status = .syncing(found: ids.count, processed: 0)

            var added = 0, processed = 0
            var failed = Set<String>()
            var messages: [GmailMessage] = []
            for batch in ids.chunked(into: 4) {
                let results = await withTaskGroup(of: (String, GmailMessage?).self) { group in
                    for id in batch { group.addTask { (id, await Self.fetchWithRetry(id: id, token: token)) } }
                    return await group.reduce(into: [(String, GmailMessage?)]()) { $0.append($1) }
                }
                for (id, m) in results { if let m { messages.append(m) } else { failed.insert(id) } }
                processed += batch.count
                status = .syncing(found: ids.count, processed: processed)
            }
            // Oldest first so refunds/transfers find their earlier counterparts.
            var checks: [EmailCheck] = []
            for m in messages.sorted(by: { $0.date < $1.date }) {
                LedgerStore.shared.learnOwner(from: m.subject + ". " + String(m.body.prefix(400)))
                var check = EmailCheck(id: m.id, date: m.date, subject: m.subject, sender: m.senderName ?? "", outcome: .skipped, detail: "Not a payment email")
                if let focused = EmailAlertExtractor.focus(subject: m.subject, body: m.body) {
                    let outcome = LedgerStore.shared.ingestEmail(focused, date: m.date, senderName: m.senderName)
                    let tx = outcome.transactionID.flatMap(LedgerStore.shared.transaction)
                    let what = tx.map { "\(Fmt.money($0.amount, $0.currencyCode)) · \($0.displayMerchant)" } ?? ""
                    switch outcome {
                    case .added: added += 1; check.outcome = .added; check.detail = what
                    case .merged: check.outcome = .matched; check.detail = "Matched existing · " + what
                    case .needsReview: added += 1; check.outcome = .added; check.detail = "Needs review · " + what
                    case .duplicate: check.outcome = .duplicate; check.detail = "Already added"
                    case let .notFinancial(reason): check.detail = "Skipped: \(reason)"; check.excerpt = String(m.body.prefix(700))
                    }
                } else {
                    check.excerpt = String(m.body.prefix(700))
                }
                // Only surface emails that look money-related, to keep the list meaningful.
                if check.outcome != .skipped || RX.looksMoneyish(m.subject + " " + m.body.prefix(400)) { checks.append(check) }
                processedIDs.insert(m.id)
            }
            // Give up on an email that failed 3 syncs in a row instead of blocking every future sync.
            for id in failed { pendingAttempts[id, default: 0] += 1 }
            let givenUp = failed.filter { (pendingAttempts[$0] ?? 0) >= 3 }
            for id in givenUp {
                processedIDs.insert(id); pendingAttempts[id] = nil
                checks.append(EmailCheck(id: id, date: .now, subject: "An email couldn't be downloaded", sender: "", outcome: .unreadable, detail: "Skipped after 3 tries"))
            }
            failed.subtract(givenUp)
            for id in pendingAttempts.keys where !failed.contains(id) { pendingAttempts[id] = nil }
            UserDefaults.standard.set(pendingAttempts, forKey: "gmailPendingAttempts")
            record(checks)
            pendingIDs = failed
            UserDefaults.standard.set(Array(failed), forKey: "gmailPendingIDs")
            persistProcessed()
            finish(startedAt: startedAt, added: added)
            if added > 0 { LedgerStore.shared.refreshOnActivate() }
        } catch GoogleAuth.AuthError.reconnectNeeded {
            status = .needsReconnect
        } catch {
            // Listing failed: keep the old lastSync so nothing is skipped.
            status = .failed("Couldn't reach Gmail. Will retry automatically.")
        }
    }

    private func finish(startedAt: Date, added: Int) {
        lastAdded = added
        lastSync = startedAt
        UserDefaults.standard.set(startedAt, forKey: "gmailLastSync")
        status = .idle
    }

    /// Retries rate limits (429) and server errors with backoff instead of silently dropping the email.
    enum FetchError: Error { case retryable, permanent }

    /// Retries only rate limits (429), server errors and network drops, briefly. Anything else fails fast.
    nonisolated private static func fetchWithRetry(id: String, token: String) async -> GmailMessage? {
        var delay: Double = 0.5
        for _ in 0..<3 {
            do { return try await fetch(id: id, token: token) }
            catch FetchError.retryable, is URLError {
                try? await Task.sleep(for: .seconds(delay)); delay *= 2
            } catch { return nil }
        }
        return nil
    }

    // MARK: Background refresh (iOS decides when; typically a few times a day)

    func scheduleBackgroundRefresh() {
        guard isConnected else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Gmail REST

    private func listMessageIDs(query: String, token: String, cap: Int) async throws -> [String] {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            c.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: "500")]
            if let pageToken { c.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
            let json = try await Self.get(c.url!, token: token)
            ids += (json["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil && ids.count < cap
        return Array(ids.prefix(cap))
    }

    nonisolated private static func fetch(id: String, token: String) async throws -> GmailMessage {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full&fields=id,internalDate,payload")!
        let json = try await get(url, token: token)
        let payload = json["payload"] as? [String: Any] ?? [:]
        let headers = Dictionary((payload["headers"] as? [[String: String]] ?? []).compactMap { h in h["name"].map { ($0.lowercased(), h["value"] ?? "") } },
                                 uniquingKeysWith: { a, _ in a })
        let millis = Double(json["internalDate"] as? String ?? "") ?? Date().timeIntervalSince1970 * 1000
        let (plain, html) = bodies(payload)
        let body = plain?.isEmpty == false ? plain! : EmailAlertExtractor.plainText(fromHTML: html ?? "")
        return GmailMessage(id: id, date: Date(timeIntervalSince1970: millis / 1000), subject: headers["subject"] ?? "",
                            senderName: senderName(headers["from"] ?? ""), body: String(body.prefix(20_000)))
    }

    nonisolated static func get(_ url: URL, token: String) async throws -> [String: Any] {
        var r = URLRequest(url: url)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw GoogleAuth.AuthError.reconnectNeeded }
        if status == 429 || status >= 500 { throw FetchError.retryable }
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FetchError.permanent }
        return json
    }

    /// Walks MIME parts; returns (text/plain, text/html).
    nonisolated private static func bodies(_ part: [String: Any]) -> (String?, String?) {
        var plain: String?, html: String?
        func visit(_ p: [String: Any]) {
            let mime = p["mimeType"] as? String ?? ""
            if let body = p["body"] as? [String: Any], let data = (body["data"] as? String).flatMap({ Data(base64URL: $0) }),
               let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                if mime == "text/plain", plain == nil { plain = text }
                if mime == "text/html", html == nil { html = text }
            }
            (p["parts"] as? [[String: Any]])?.forEach(visit)
        }
        visit(part)
        return (plain, html)
    }

    /// "Swiggy <noreply@swiggy.in>" → "Swiggy"; "alerts@hdfcbank.net" → "hdfcbank".
    nonisolated private static func senderName(_ from: String) -> String? {
        if let lt = from.firstIndex(of: "<") {
            let name = from[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !name.isEmpty { return name }
        }
        let domain = from.split(separator: "@").last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "> ")) }
        return domain?.split(separator: ".").first.map(String.init)
    }

    private func persistProcessed() {
        // Bounded so it never grows without limit; evidence hashes still dedupe anything older.
        let recent = processedIDs.count > 20_000 ? Set(processedIDs.shuffled().prefix(15_000)) : processedIDs
        processedIDs = recent
        UserDefaults.standard.set(Array(recent), forKey: "gmailProcessedIDs")
    }
}

/// What happened to one checked email — shown in Settings → Recent emails.
struct EmailCheck: Codable, Identifiable, Hashable {
    enum Outcome: String, Codable { case added, matched, duplicate, skipped, unreadable }
    var id: String
    var date: Date
    var subject: String
    var sender: String
    var outcome: Outcome
    var detail: String
    /// First part of the email, kept only for skipped ones so "Add anyway" can work. On-device only, last 60 emails.
    var excerpt: String?
}

struct GmailMessage: Sendable {
    let id: String
    let date: Date
    let subject: String
    let senderName: String?
    let body: String
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
