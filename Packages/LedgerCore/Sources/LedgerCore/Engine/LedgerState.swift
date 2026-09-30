import Foundation

/// Everything the ledger knows. Codable so the app can persist it (encrypted,
/// on-device) behind a repository; the engine itself never touches disk.
public struct LedgerState: Codable, Sendable {
    public var schemaVersion = 1
    public var evidence: [UUID: RawEvidence] = [:]
    public var observations: [UUID: FinancialObservation] = [:]
    public var transactions: [UUID: CanonicalTransaction] = [:]
    public var records: [UUID: ReconciliationRecord] = [:]
    public var recurring: [RecurringSeries] = []
    /// merchantKey → categoryID ("Always categorize this merchant this way").
    public var userRules: [String: String] = [:]
    /// Account/card last-4s seen in the user's own alerts & statements.
    public var ownAccountHints: Set<String> = []
    public var importJobs: [ImportJob] = []
    /// Name words the bank uses to greet the user ("Dear Priya", "Hello Rahul Kumar"), with counts.
    public var ownerNameTokens: [String: Int] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, evidence, observations, transactions, records, recurring, userRules, ownAccountHints, importJobs, ownerNameTokens
    }

    /// Tolerates fields added in later versions so an older ledger always opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        evidence = try c.decodeIfPresent([UUID: RawEvidence].self, forKey: .evidence) ?? [:]
        observations = try c.decodeIfPresent([UUID: FinancialObservation].self, forKey: .observations) ?? [:]
        transactions = try c.decodeIfPresent([UUID: CanonicalTransaction].self, forKey: .transactions) ?? [:]
        records = try c.decodeIfPresent([UUID: ReconciliationRecord].self, forKey: .records) ?? [:]
        recurring = try c.decodeIfPresent([RecurringSeries].self, forKey: .recurring) ?? []
        userRules = try c.decodeIfPresent([String: String].self, forKey: .userRules) ?? [:]
        ownAccountHints = try c.decodeIfPresent(Set<String>.self, forKey: .ownAccountHints) ?? []
        importJobs = try c.decodeIfPresent([ImportJob].self, forKey: .importJobs) ?? []
        ownerNameTokens = try c.decodeIfPresent([String: Int].self, forKey: .ownerNameTokens) ?? [:]
    }
}

public enum IngestOutcome: Sendable, Equatable {
    case added(UUID)
    case merged(UUID)
    case duplicate(UUID?)
    case needsReview(UUID)
    case notFinancial(String)

    public var transactionID: UUID? {
        switch self {
        case let .added(id), let .merged(id), let .needsReview(id): id
        case let .duplicate(id): id
        case .notFinancial: nil
        }
    }
}
