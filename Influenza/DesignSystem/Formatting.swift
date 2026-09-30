import Foundation
import LedgerCore

/// All currency formatting goes through here (spec §95). Decimal in, never Double.
enum Fmt {
    static var defaultCurrency: String {
        UserDefaults.standard.string(forKey: "defaultCurrency") ?? Locale.current.currency?.identifier ?? "USD"
    }

    static func money(_ amount: Decimal, _ currency: String, signed: Bool = false, compact: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: currency)
        let whole = amount == amount.rounded(0)
        var text: String
        if compact && abs(amount) >= 100_000 {
            text = (amount as NSDecimalNumber).doubleValue.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0...1)))
        } else {
            text = amount.formatted(style.precision(.fractionLength(whole ? 0 : 2)))
        }
        if signed && amount > 0 { text = "+" + text }
        return text
    }

    static func money(_ m: LedgerCore.Money) -> String { money(m.amount, m.currencyCode) }

    /// VoiceOver: "one thousand two hundred ninety-nine rupees".
    static func spoken(_ amount: Decimal, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).presentation(.fullName))
    }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self, out = Decimal()
        NSDecimalRound(&out, &value, scale, .plain)
        return out
    }
    var double: Double { (self as NSDecimalNumber).doubleValue }
}
