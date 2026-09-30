import Foundation

/// OFX 1.x (SGML) and 2.x (XML) / QFX. FITID is preserved as the source transaction ID.
public enum OFXStatementParser {
    public static let version = "ofx-1.0"

    public static func parse(_ text: String, defaultCurrency: String) throws -> [StatementRow] {
        let currency = value("CURDEF", in: text) ?? defaultCurrency
        let account = value("ACCTID", in: text).map { String($0.suffix(4)) }
        let blocks = text.components(separatedBy: "<STMTTRN>").dropFirst()
        var rows: [StatementRow] = []
        for raw in blocks {
            let block = raw.components(separatedBy: "</STMTTRN>").first ?? raw
            guard let amountText = value("TRNAMT", in: block), let amount = AmountParser.number(amountText), amount != 0,
                  let dateText = value("DTPOSTED", in: block) ?? value("DTUSER", in: block), let date = ofxDate(dateText) else { continue }
            let name = value("NAME", in: block) ?? value("PAYEE", in: block) ?? ""
            let memo = value("MEMO", in: block) ?? ""
            let description = TextNormalization.collapse(memo.isEmpty || memo == name ? name : "\(name) \(memo)")
            rows.append(StatementRow(
                date: value("DTUSER", in: block).flatMap(ofxDate) ?? date, postedDate: date,
                description: description, amount: abs(amount), direction: amount < 0 ? .debit : .credit,
                currencyCode: value("CURRENCY", in: block).map { _ in currency } ?? currency,
                reference: value("FITID", in: block) ?? value("CHECKNUM", in: block),
                accountHint: account, transactionTypeHint: value("TRNTYPE", in: block)))
        }
        guard !rows.isEmpty else { throw StatementParseError.noTransactions }
        return rows
    }

    /// Value of <TAG>value (SGML, no closing tag) or <TAG>value</TAG> (XML).
    static func value(_ tag: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(tag)>") else { return nil }
        let rest = text[start.upperBound...]
        let end = rest.firstIndex(where: { $0 == "<" || $0 == "\n" || $0 == "\r" }) ?? rest.endIndex
        let v = rest[..<end].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    static func ofxDate(_ s: String) -> Date? {
        let digits = String(s.prefix(8))
        return StatementDates.formatter("yyyyMMdd").date(from: digits)
    }
}
