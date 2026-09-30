import Foundation

/// Finds money in free text, worldwide formats. Deterministic.
public enum AmountParser {
    static let symbolCurrencies: [String: String] = [
        "R$": "BRL", "A$": "AUD", "C$": "CAD", "S$": "SGD", "HK$": "HKD", "US$": "USD", "NZ$": "NZD",
        "₹": "INR", "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₩": "KRW", "₦": "NGN",
        "₱": "PHP", "฿": "THB", "₫": "VND", "₺": "TRY", "₪": "ILS", "₽": "RUB", "zł": "PLN",
        "rs": "INR", "rs.": "INR", "inr": "INR", "rm": "MYR", "dhs": "AED", "aed": "AED", "sar": "SAR",
        "usd": "USD", "eur": "EUR", "gbp": "GBP", "kes": "KES", "ksh": "KES", "ngn": "NGN", "pkr": "PKR",
        "lkr": "LKR", "bdt": "BDT", "npr": "NPR", "idr": "IDR", "rp": "IDR", "sgd": "SGD", "cad": "CAD",
        "aud": "AUD", "jpy": "JPY", "chf": "CHF", "zar": "ZAR", "mxn": "MXN", "brl": "BRL",
    ]
    static let isoCodes = Set(Locale.commonISOCurrencyCodes)
    static let amountPattern = #"\d{1,3}(?:[,.' ]\d{2,3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#
    static let currencyToken =
        #"R\$|A\$|C\$|S\$|HK\$|US\$|NZ\$|[₹$€£¥₩₦₱฿₫₺₪₽]|zł|(?i:rs\.?|inr|rm|dhs|aed|sar|usd|eur|gbp|kes|ksh|ngn|pkr|lkr|bdt|npr|idr|rp|sgd|cad|aud|jpy|chf|zar|mxn|brl)(?![a-z])|[A-Z]{3}(?![A-Za-z])"#

    private static let before = try! NSRegularExpression(pattern: "(\(currencyToken))\\s?(\(amountPattern))")
    private static let after = try! NSRegularExpression(pattern: "(\(amountPattern))\\s?(\(currencyToken))")
    private static let bare = try! NSRegularExpression(pattern: "(?i)(?:debited (?:by|for|with)|credited (?:by|with)|spent|paid|of|for)\\s+(\(amountPattern))")

    /// First transaction amount, skipping balances/limits.
    public static func firstAmount(in text: String, defaultCurrency: String) -> Money? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var candidates: [(Int, Money)] = []

        func add(_ m: NSTextCheckingResult, cur: Int, amt: Int) {
            guard let code = currencyCode(ns.substring(with: m.range(at: cur))),
                  let value = number(ns.substring(with: m.range(at: amt))), value > 0 else { return }
            let start = max(0, m.range.location - 22)
            let context = ns.substring(with: NSRange(location: start, length: m.range.location - start)).lowercased()
            if ["bal", "balance", "limit", "avl", "avbl", "available", "lmt"].contains(where: context.contains) { return }
            candidates.append((m.range.location, Money(value, code)))
        }
        before.matches(in: text, range: full).forEach { add($0, cur: 1, amt: 2) }
        after.matches(in: text, range: full).forEach { add($0, cur: 2, amt: 1) }
        if let first = candidates.min(by: { $0.0 < $1.0 }) { return first.1 }

        if let m = bare.firstMatch(in: text, range: full), let value = number(ns.substring(with: m.range(at: 1))), value > 0 {
            return Money(value, defaultCurrency)
        }
        return nil
    }

    public static func currencyCode(_ token: String) -> String? {
        if let code = symbolCurrencies[token] ?? symbolCurrencies[token.lowercased()] { return code }
        return isoCodes.contains(token) ? token : nil
    }

    /// 1,234.56 · 1.234,56 · 1,23,456.00 · 1 234,56 · 1'234.50 · 12,50 · (42.18) · -42.18
    public static func number(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasPrefix("-") || s.hasPrefix("−") { negative = true; s = String(s.dropFirst()) }
        if s.hasSuffix("-") { negative = true; s = String(s.dropLast()) }
        s = s.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !s.isEmpty else { return nil }
        let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (c?, d?):
            s = c > d ? s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                      : s.replacingOccurrences(of: ",", with: "")
        case let (c?, nil):
            let decimals = s.distance(from: c, to: s.endIndex) - 1
            s = (decimals <= 2 && s.filter { $0 == "," }.count == 1) ? s.replacingOccurrences(of: ",", with: ".") : s.replacingOccurrences(of: ",", with: "")
        case let (nil, d?):
            let decimals = s.distance(from: d, to: s.endIndex) - 1
            if s.filter({ $0 == "." }).count > 1 || decimals == 3 { s = s.replacingOccurrences(of: ".", with: "") }
        default: break
        }
        guard let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }
}
