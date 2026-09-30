import Foundation

/// Bank/card CSV exports: auto delimiter, header detection (skips preamble
/// rows common in Indian bank exports), signed or debit/credit columns.
public enum CSVStatementParser {
    public static let version = "csv-1.0"

    public static func parse(_ text: String, defaultCurrency: String) throws -> [StatementRow] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw StatementParseError.empty }
        let delimiter = detectDelimiter(lines.prefix(20))
        let rows = lines.map { split($0, delimiter) }

        guard let headerIndex = rows.prefix(40).firstIndex(where: isHeader) else { throw StatementParseError.noHeader }
        let header = rows[headerIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func matches(_ h: String, _ name: String) -> Bool {
            // Short tokens ("dr", "cr", "amt") must be whole words: "cr" must not match "description".
            name.count <= 3 ? h == name || RX.matches("\\b\(name)\\b", h) : h.contains(name)
        }
        func col(_ names: [String], excluding: [String] = []) -> Int? {
            header.firstIndex { h in names.contains { matches(h, $0) } && !excluding.contains { matches(h, $0) } }
        }
        let dateCol = col(["transaction date", "txn date", "trans date", "value date", "date"], excluding: ["post", "value date"]) ?? col(["date"])
        let postCol = col(["posted date", "posting date", "post date", "value date"])
        let descCol = col(["description", "narration", "particulars", "details", "merchant", "payee", "name", "remarks", "transaction details", "memo"])
        let debitCol = col(["debit", "withdrawal", "withdrawals", "dr", "paid out", "money out"], excluding: ["credit", "card"])
        let creditCol = col(["credit", "deposit", "deposits", "cr", "paid in", "money in"], excluding: ["debit", "card"])
        let amountCol = col(["amount", "transaction amount", "amt"], excluding: ["balance"])
        let typeCol = col(["type", "dr/cr", "cr/dr", "debit/credit"], excluding: ["transaction type code"])
        let refCol = col(["reference", "ref no", "ref", "chq", "cheque", "utr", "transaction id"])
        let currencyCol = col(["currency"])
        guard let dateCol, let descCol, amountCol != nil || debitCol != nil || creditCol != nil else { throw StatementParseError.noHeader }

        let body = rows[(headerIndex + 1)...]
        let dayFirst = StatementDates.dayFirst(samples: body.compactMap { $0[safe: dateCol] }, currency: defaultCurrency)

        var parsed: [StatementRow] = []
        for row in body {
            guard let dateText = row[safe: dateCol], let date = StatementDates.parse(dateText, dayFirst: dayFirst) else { continue }
            let description = TextNormalization.collapse(row[safe: descCol] ?? "")
            let currency = row[safe: currencyCol ?? -1].flatMap { AmountParser.currencyCode($0.trimmingCharacters(in: .whitespaces)) } ?? defaultCurrency

            var signed: Decimal?
            if let d = debitCol, let v = row[safe: d].flatMap(AmountParser.number), v != 0 { signed = -abs(v) }
            if signed == nil, let c = creditCol, let v = row[safe: c].flatMap(AmountParser.number), v != 0 { signed = abs(v) }
            if signed == nil, let a = amountCol, let v = row[safe: a].flatMap(AmountParser.number) {
                signed = v
                if let t = typeCol, let kind = row[safe: t]?.lowercased() {
                    if kind.hasPrefix("d") || kind.contains("debit") || kind.contains("sale") || kind.contains("purchase") { signed = -abs(v) }
                    else if kind.hasPrefix("c") || kind.contains("credit") || kind.contains("payment") || kind.contains("return") { signed = abs(v) }
                }
            }
            guard let value = signed, value != 0 else { continue }
            parsed.append(StatementRow(
                date: date,
                postedDate: postCol.flatMap { row[safe: $0] }.flatMap { StatementDates.parse($0, dayFirst: dayFirst) },
                description: description, amount: abs(value), direction: value < 0 ? .debit : .credit,
                currencyCode: currency, reference: refCol.flatMap { row[safe: $0] }.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 },
                accountHint: nil, transactionTypeHint: typeCol.flatMap { row[safe: $0] }))
        }
        guard !parsed.isEmpty else { throw StatementParseError.noTransactions }
        return normalizeCardSignConvention(parsed)
    }

    /// Some card exports (e.g. Amex) list purchases as positive and payments as
    /// negative. If "payment" rows are the only debits and most rows are credits, flip.
    private static func normalizeCardSignConvention(_ rows: [StatementRow]) -> [StatementRow] {
        let credits = rows.filter { $0.direction == .credit }
        let debits = rows.filter { $0.direction == .debit }
        let debitsArePayments = !debits.isEmpty && debits.allSatisfy { $0.description.lowercased().range(of: #"payment|thank you|autopay"#, options: .regularExpression) != nil }
        guard credits.count >= debits.count * 2, debitsArePayments else { return rows }
        return rows.map { var r = $0; r.direction = r.direction == .debit ? .credit : .debit; return r }
    }

    private static func isHeader(_ cells: [String]) -> Bool {
        let joined = cells.joined(separator: "|").lowercased()
        let hasDate = joined.contains("date")
        let hasMoney = ["amount", "debit", "credit", "withdrawal", "deposit"].contains { joined.contains($0) }
        let hasDesc = ["description", "narration", "particulars", "details", "merchant", "payee", "name", "memo", "remarks"].contains { joined.contains($0) }
        return hasDate && hasMoney && hasDesc
    }

    private static func detectDelimiter(_ lines: ArraySlice<String>) -> Character {
        let candidates: [Character] = [",", ";", "\t", "|"]
        return candidates.max { a, b in
            lines.map { $0.filter { $0 == a }.count }.reduce(0, +) < lines.map { $0.filter { $0 == b }.count }.reduce(0, +)
        } ?? ","
    }

    /// RFC-4180-ish split with quoted fields.
    static func split(_ line: String, _ delimiter: Character) -> [String] {
        var fields: [String] = [], current = "", inQuotes = false
        var iterator = line.makeIterator()
        while let ch = iterator.next() {
            if ch == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" { current.append("\"") } else { inQuotes = false; if next == delimiter { fields.append(current); current = "" } else { current.append(next) } }
                } else { inQuotes.toggle() }
            } else if ch == delimiter && !inQuotes {
                fields.append(current); current = ""
            } else { current.append(ch) }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
