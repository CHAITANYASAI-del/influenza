import Foundation

/// Bank alert emails wrap one transaction sentence in greetings, security
/// warnings ("never share your OTP") and promotions. Parse only the focused
/// window around the first money movement so footers can't veto a real alert.
public enum EmailAlertExtractor {
    public static func plainText(fromHTML html: String) -> String {
        var s = RX.replace(#"(?is)<(script|style|head)[^>]*>.*?</\1>"#, in: html, with: " ")
        s = RX.replace(#"(?i)<br\s*/?>|</p>|</div>|</tr>|</li>"#, in: s, with: "\n")
        s = RX.replace(#"<[^>]+>"#, in: s, with: " ")
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#8377;": "₹", "&rsquo;": "'", "&#x20B9;": "₹"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    /// Wording that only appears when money actually moved (bank alerts, card alerts, receipts).
    /// Newsletters, digests, order-status and marketing mails that merely mention money fail this.
    static let transactional = #"(?i)(debited|credited)\b.{0,70}\b(a/?c|account|acct|card)\b|\b(a/?c|account|acct|card)\b.{0,70}\b(debited|credited)|spent on your|thank you for using .{0,50}card|was used for|have (successfully )?made (a )?(upi )?payment|payment of .{0,30}(successful|received|credited)|receipt from|amount paid|total paid|paid (on|via|using|with)\b|(we have|we've) received (the |your )?payment|bill payment was successful|refund (amount|of|initiated|processed|credited|has been)|is reversed|has been reversed|you have done a upi txn|transaction alert|txn alert|you (made|paid|sent)\b|charge of|purchase of \S+ at|was charged"#
    static let nonTransactional = #"(?i)exchange (request|order)|out for (delivery|exchange)|has been shipped|is shipped|been delivered|rate your|how was your|share your feedback|terms of service|digest|newsletter|webinar|pre-?approved|personal loan|apply now|wish ?list|price drop|\bsale\b|% off|coupon"#

    public static func isTransactional(_ text: String) -> Bool {
        RX.matches(transactional, text) && !RX.matches(nonTransactional, text)
    }

    /// Returns the ~2 sentences containing the transaction, or nil if the email has none.
    public static func focus(subject: String, body: String) -> String? {
        guard let window = rawFocus(subject: subject, body: body), isTransactional(window) else { return nil }
        return window
    }

    static func rawFocus(subject: String, body: String) -> String? {
        let text = TextNormalization.collapse(body)
        let pattern = #"(?i)\b(debited|credited|spent|paid|sent|purchase|withdrawn|charged|was used|transaction of|txn of|payment of|refund|you made a|thank you for using|for using your|made a upi payment|was used for|amount paid|total paid|receipt from|bill payment|you have done a upi txn)\b"#
        let ns = text as NSString
        let hits = RX.regex(pattern).matches(in: text, range: NSRange(location: 0, length: ns.length))
        for hit in hits {
            let start = max(0, hit.range.location - 220)
            let end = min(ns.length, hit.range.location + 260)
            var window = ns.substring(with: NSRange(location: start, length: end - start))
            // Trim to sentence boundaries so neighbouring footer text stays out.
            if start > 0, let r = window.range(of: #"[.!?]\s+(?=[A-Z₹$])"#, options: .regularExpression), r.lowerBound < window.index(window.startIndex, offsetBy: min(200, window.count)) {
                window = String(window[r.upperBound...])
            }
            // End at the sentence that contains the transaction verb (and its amount).
            let verbOffset = hit.range.location - start
            let wns = window as NSString
            let enders = RX.regex(#"[.!?]\s+(?=[A-Z])"#).matches(in: window, range: NSRange(location: 0, length: wns.length))
            if let cut = enders.first(where: { $0.range.location > verbOffset && AmountParser.firstAmount(in: wns.substring(to: $0.range.location), defaultCurrency: "XXX") != nil }) {
                window = wns.substring(to: cut.range.location + 1)
            }
            if AmountParser.firstAmount(in: window, defaultCurrency: "XXX") != nil { return "\(subject). \(window)" }
        }
        return nil
    }
}
