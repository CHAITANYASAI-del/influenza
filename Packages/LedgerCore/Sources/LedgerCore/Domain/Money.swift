import Foundation

/// Exact money. Never Double/Float for stored values.
public struct Money: Codable, Hashable, Sendable {
    public let amount: Decimal
    public let currencyCode: String

    public init(_ amount: Decimal, _ currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
    }
}

public enum InvalidMoneyError: Error, Equatable {
    case nonPositive, unknownCurrency(String), currencyMismatch
}

extension Decimal {
    /// Rounded to 2 dp for stable fingerprints/keys.
    var stableString: String {
        var value = self, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
