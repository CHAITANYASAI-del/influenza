import Foundation

/// Generic parser for text extracted from PDF statements (PDFKit or OCR).
/// A transaction line starts with a date and ends with one or more amounts.
public enum TextStatementParser {
    public static let version = "pdftext-1.0"

    private static let datePrefix = try! NSRegularExpression(pattern: #"^\s*(\d{1,2}[/\-. ](?:\d{1,2}|[A-Za-z]{3})[/\-. ]\d{2,4}|\d{4}-\d{2}-\d{2}|[A-Za-z]{3} \d{1,2},? \d{4})\s+"#)
    private static let trailingAmounts = try! NSRegularExpression(pattern: #"((?:\(?-?[\d,]+\.\d{2}\)?\s*(?:Dr|Cr|DR|CR|-)?\s*){1,3})$"#)
    private static let amountToken = try! NSRegularExpression(pattern: #"\(?-?[\d,]+\.\d{2}\)?\s*(?:Dr|Cr|DR|CR|-)?"#)

    public static func parse(_ text: String, defaultCurrency: String) throws -> [StatementRow] {
        let lines = text.components(separatedBy: .newlines).map(TextNormalization.collapse).filter { !$0.isEmpty }
        let dateSamples = lines.compactMap { line -> String? in
            let ns = line as NSString
            return datePrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        }
        let dayFirst = StatementDates.dayFirst(samples: dateSamples, currency: defaultCurrency)
        let lower = text.lowercased()
        let isCardStatement = lower.contains("credit card") || lower.contains("card statement")

        var rows: [StatementRow] = []
        var previousBalance: Decimal?
        for line in lines {
            let ns = line as NSString
            guard let dm = datePrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let date = StatementDates.parse(ns.substring(with: dm.range(at: 1)), dayFirst: dayFirst),
                  let am = trailingAmounts.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let amountsText = ns.substring(with: am.range(at: 1))
            let tokens = amountToken.matches(in: amountsText, range: NSRange(location: 0, length: (amountsText as NSString).length))
                .map { (amountsText as NSString).substring(with: $0.range).trimmingCharacters(in: .whitespaces) }
            guard let first = tokens.first, var value = AmountParser.number(RX.replace(#"(?i)dr|cr"#, in: first, with: "")) else { continue }
            let descStart = dm.range.location + dm.range.length
            let description = TextNormalization.collapse(ns.substring(with: NSRange(location: descStart, length: max(0, am.range.location - descStart))))
            guard description.filter(\.isLetter).count >= 2 else { continue }

            var direction: Direction
            if RX.matches(#"(?i)cr$"#, first) { direction = .credit }
            else if RX.matches(#"(?i)dr$"#, first) || value < 0 { direction = .debit }
            else if tokens.count >= 2, let balance = AmountParser.number(tokens.last!), let prev = previousBalance {
                direction = balance < prev ? .debit : .credit      // withdrawal/deposit + running balance layout
            } else if description.lowercased().range(of: #"payment|thank you|credited|refund|reversal|cashback"#, options: .regularExpression) != nil {
                direction = .credit
            } else {
                direction = isCardStatement ? .debit : .debit
            }
            if tokens.count >= 2, let balance = AmountParser.number(tokens.last!) { previousBalance = balance }
            value = abs(value)
            guard value > 0 else { continue }
            rows.append(StatementRow(date: date, postedDate: nil, description: description, amount: value, direction: direction,
                                     currencyCode: defaultCurrency, reference: nil, accountHint: nil, transactionTypeHint: nil))
        }
        guard !rows.isEmpty else { throw StatementParseError.noTransactions }
        return rows
    }
}
