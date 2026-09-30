import Foundation

/// Plain-text receipt (pasted, OCR'd, or from an email) → merchant evidence.
public struct ParsedReceipt: Sendable, Equatable {
    public var merchantRaw: String?
    public var merchantDetail: String?
    public var total: Money?
    public var items: [ReceiptItem]
}

public enum ReceiptParser {
    private static let skip = #"(?i)^(sub ?total|total|tax|gst|cgst|sgst|vat|tip|gratuity|service (fee|charge)|delivery (fee|charge)|fees?|discount|change|cash|card|visa|mastercard|amount|balance|paid|order|invoice|receipt|thank|date|time|table|cashier|bill)"#
    private static let lineItem = try! NSRegularExpression(pattern: #"^(?:\d+\s*[xX]\s*)?([A-Za-z][A-Za-z0-9 &'.,/()\-]{1,50}?)\s+[^\dA-Za-z]{0,3}(\d[\d,]*(?:\.\d{1,2})?)\s*$"#)

    public static func parse(_ text: String, defaultCurrency: String) -> ParsedReceipt {
        let lines = text.components(separatedBy: .newlines).map(TextNormalization.collapse).filter { !$0.isEmpty }

        let merchant = lines.prefix(4).first { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && Double(letters) / Double(max(line.count, 1)) > 0.5
                && line.lowercased().range(of: #"receipt|invoice|tax|order #|order no"#, options: .regularExpression) == nil
        }

        var detail: String?
        for line in lines {
            if let r = line.range(of: #"(?i)^(restaurant|store|from|sold by|seller)\s*[:\-]\s*"#, options: .regularExpression) {
                detail = String(line[r.upperBound...]); break
            }
        }

        var total: Money?
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard RX.matches(#"grand total|^total|order total|amount (paid|due)|total paid|net amount|to pay|total charged"#, lower),
                  !lower.contains("subtotal"), !lower.contains("sub total") else { continue }
            let window = line + (i + 1 < lines.count ? " " + lines[i + 1] : "")
            if let m = AmountParser.firstAmount(in: window, defaultCurrency: defaultCurrency) ?? bareNumber(window, defaultCurrency) {
                total = m
            }
        }

        var items: [ReceiptItem] = []
        for line in lines where line != merchant && !RX.matches(skip, line) {
            let ns = line as NSString
            if let m = lineItem.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                items.append(ReceiptItem(name: TextNormalization.collapse(ns.substring(with: m.range(at: 1))),
                                         amount: AmountParser.number(ns.substring(with: m.range(at: 2)))))
            } else if line.filter(\.isLetter).count >= 3, line.count <= 40, !line.contains(where: \.isNumber),
                      !RX.matches(#"(?i)address|street|road|phone|www|http|@"#, line), line != detail {
                items.append(ReceiptItem(name: line, amount: nil))
            }
        }
        return ParsedReceipt(merchantRaw: merchant, merchantDetail: detail, total: total, items: items)
    }

    private static func bareNumber(_ s: String, _ currency: String) -> Money? {
        guard let r = s.range(of: #"\d[\d,]*\.\d{2}"#, options: .regularExpression), let v = AmountParser.number(String(s[r])) else { return nil }
        return Money(v, currency)
    }
}
