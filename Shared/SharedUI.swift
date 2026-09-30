import SwiftUI

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum SharedFormat {
    static func money(_ amount: Decimal, _ currency: String, compact: Bool = false) -> String {
        if compact && abs(amount) >= 100_000 {
            return (amount as NSDecimalNumber).doubleValue.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0...1)))
        }
        var v = amount, r = Decimal()
        NSDecimalRound(&r, &v, 0, .plain)
        return r.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}
