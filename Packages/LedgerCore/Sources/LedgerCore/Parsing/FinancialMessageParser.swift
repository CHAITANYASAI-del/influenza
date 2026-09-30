import Foundation

/// Structured reading of one financial text (SMS, email alert, statement narration).
public struct ParsedFinancialText: Sendable, Equatable {
    public var money: Money
    public var direction: Direction
    public var type: ObservationTransactionType
    public var rail: PaymentRail
    public var merchantRaw: String?
    public var reference: String?
    public var cardLast4: String?
    public var pending: PendingState
    public var isComplete: Bool
}

public enum MessageParseResult: Sendable, Equatable {
    case financial(ParsedFinancialText)
    case notFinancial(reason: String)
}

/// Layered, bank-agnostic classifier + extractor. India & US vocab first,
/// works for most English-language alerts worldwide. No AI.
public enum FinancialMessageParser {
    public static let version = "msg-1.2"

    // MARK: Classification vocab

    private static let rejectPatterns: [(String, String)] = [
        (#"\botp\b|one[- ]time password|verification code|security code|\b2fa\b|passcode"#, "one-time password"),
        (#"do not share|never share"#, "security message"),
        (#"will be debited|to be debited|is due|due on|due date|due by|minimum (amount )?due|min amt due|total amount due|bill (is )?generated|statement (is )?generated"#, "bill or reminder"),
        (#"collect request|has requested|requested money|request of"#, "payment request"),
        (#"e-?mandate|autopay (is )?(set|registered|scheduled)|standing instruction (set|registered)"#, "mandate set-up"),
        (#"declined|\bfailed\b|unsuccessful|not processed|could not be processed"#, "failed transaction"),
        (#"pre-?approved|\boffer\b|\bapply now\b|\bloan of\b|\bwin\b|congratulations|reward points|\bcoupon\b"#, "promotion"),
        (#"log(ged)? ?in|new device|password (changed|reset)"#, "login alert"),
    ]

    private static let debitWords = #"\b(debited|debit(ed)? by|spent|paid|sent|purchase[ds]?|withdrawn|withdrawal|charged|was used|used (at|for)|txn of|transaction of|payment of|payment to|dr\.?\b|you paid|you've paid|thank you for using|for using your|was used for|made a upi payment|successfully made|amount paid|total paid|bill payment|receipt from|have done a upi txn|you have paid|money sent|charge of|transaction with|made a .{0,20}transaction|compra|zahlung|achat|paiement|auto-?debit|direct debit|ach debit|zelle payment to)\b"#
    private static let creditWords = #"\b(credited|received|deposited|deposit of|cr\.?\b|refund(ed)?|reversal|reversed|cashback|salary|payment received|thank you for your payment|payment posted|zelle payment from|ach credit|interest (paid|credited))\b"#

    // MARK: Public

    public static func parse(_ raw: String, defaultCurrency: String) -> MessageParseResult {
        let text = TextNormalization.collapse(raw)
        let lower = text.lowercased()

        for (pattern, reason) in rejectPatterns where RX.matches(pattern, lower) {
            // A refund/credit mentioning "failed txn … reversed" is a real credit, keep it.
            if reason == "failed transaction", RX.matches(#"revers|refund"#, lower) { continue }
            return .notFinancial(reason: reason)
        }

        let hasDebit = RX.matches(debitWords, lower)
        let hasCredit = RX.matches(creditWords, lower)
        guard hasDebit || hasCredit else { return .notFinancial(reason: "no money movement") }
        guard var money = AmountParser.firstAmount(in: text, defaultCurrency: defaultCurrency) else {
            return .notFinancial(reason: "no amount")
        }
        // Invoices and receipts list line items first; the total is what was paid.
        let isInvoice = RX.matches(#"invoice|bill details|receipt|total amount|total paid|amount paid|you paid using"#, lower)
        if isInvoice, let r = lower.range(of: #"(total amount paid|total amount|total paid|amount paid|you paid using [a-z ]{0,15}|grand total|order total)\s*:?\s*"#, options: .regularExpression),
           let total = AmountParser.firstAmount(in: String(text[r.lowerBound...]), defaultCurrency: defaultCurrency) {
            money = total
        }

        // "debited … ; NETFLIX credited" is a debit. Refund/reversal wins over "debited" mentions of the original.
        let isRefund = RX.matches(#"refund (of|amount|has been|initiated|processed|completed|credited|for)\b|\brefunded\b|reversal of|towards the reversal|is reversed|been reversed|credited back|chargeback|credited .{0,70}against your recent"#, lower)
        var direction: Direction = (lower.contains("debited") || lower.contains("debit by") || lower.contains("spent") || (hasDebit && !hasCredit)) ? .debit : .credit
        // A merchant saying "we have received your payment" means the user paid.
        if RX.matches(#"(we have|we've|we) received (the |your )?payment|payment (was )?made using your|amount paid|total paid|receipt from"#, lower) { direction = .debit }
        // Card bill: the card side says "payment … credited to your card".
        if RX.matches(#"payment of .{0,30}(was )?credited to your card|bill payment was successful"#, lower) { direction = lower.contains("bill payment was successful") ? .debit : .credit }
        if isRefund { direction = .credit }

        let rail = detectRail(lower)
        var type = detectType(lower, direction: direction, rail: rail, isRefund: isRefund)
        if isInvoice && type == .fee { type = .purchase }
        var merchant = extractMerchant(text, type: type)
        // Merchant emails name the brand up front ("Rapido Invoice", "Your Myntra return…").
        if merchant == nil, [.purchase, .refund].contains(type), let brand = MerchantResolver.resolve(String(text.prefix(90)))?.name { merchant = brand }
        if type == .purchase && direction == .debit && isPersonToPerson(text, merchant: merchant) { type = .transferOut }
        let pending: PendingState = RX.matches(#"\bpending\b|authori[sz](ed|ation)|\bhold\b"#, lower) ? .pending : .unknown

        return .financial(ParsedFinancialText(
            money: money, direction: direction, type: type, rail: rail, merchantRaw: merchant,
            reference: extractReference(text), cardLast4: extractLast4(text), pending: pending,
            isComplete: merchant != nil || [.withdrawal, .creditCardPayment, .salary, .interest, .internalTransfer].contains(type)))
    }

    // MARK: Detection

    static func detectRail(_ l: String) -> PaymentRail {
        if RX.matches(#"\bupi\b|vpa|@ok|@ybl|@paytm|@ibl|@axl|p2m|p2a"#, l) { return .upi }
        if l.contains("neft") { return .neft }
        if l.contains("imps") { return .imps }
        if l.contains("rtgs") { return .rtgs }
        if RX.matches(#"\batm\b|cash withdrawal"#, l) { return .atm }
        if l.contains("apple pay") { return .applePay }
        if l.contains("zelle") || l.contains("wire transfer") { return .bankTransfer }
        if RX.matches(#"\bach\b"#, l) { return .ach }
        if l.contains("direct debit") || l.contains("auto-debit") || l.contains("autodebit") { return .directDebit }
        if l.contains("sepa") { return .sepa }
        if l.contains("debit card") { return .debitCard }
        if RX.matches(#"credit card|\bcard\b|\bcc\b"#, l) { return .creditCard }
        if RX.matches(#"\bpos\b"#, l) { return .pos }
        return .unknown
    }

    static func detectType(_ l: String, direction: Direction, rail: PaymentRail, isRefund: Bool) -> ObservationTransactionType {
        if isRefund { return .refund }
        // Credit-card bill payments: from the bank side, the card side, or via CRED (VPA cred.club / @yescred / @axisb cred).
        let viaCRED = RX.matches(#"cred\.club|@yescred|\(cred club\)|\bcred club\b|towards cred\b"#, l)
        let cardBill = RX.matches(#"towards (your )?(\w+ )?(bank )?credit card( payment| bill)?|credit card (bill|payment) (payment )?(was )?successful|bill payment was successful|cc payment|credit card bill|payment (received|posted) (on|to|for) (your )?(\w+ )?(bank )?(credit )?card|payment of .{0,30}(was )?credited to your card|payment of .{0,40} received on your .{0,20}card|thank you for your payment|autopay payment|payment - thank you|payment thank you"#, l)
        if cardBill || (viaCRED && direction == .debit) { return .creditCardPayment }
        if rail == .atm || l.contains("cash withdrawal") { return direction == .debit ? .withdrawal : .deposit }
        if RX.matches(#"\bself\b|own account|between your accounts|internal transfer"#, l) { return .internalTransfer }
        if direction == .credit {
            if l.contains("salary") || l.contains("payroll") { return .salary }
            if RX.matches(#"interest (paid|credited|earned)|\binterest\b.{0,20}credited"#, l) { return .interest }
            if l.contains("cashback") { return .cashback }
            // Money back from a merchant gateway (payu/razorpay…) is a refund.
            if RX.matches(#"by vpa \S*(payu|razorpay|rzp|paytm-|cashfree|billdesk|ccavenue|juspay)"#, l) { return .refund }
            return rail.isTransferRail || rail == .upi || RX.matches(#"credited to your (hdfc |\w+ )?(bank )?(a/?c|account)"#, l) ? .transferIn : .income
        }
        // Strict fee wording: the fee must be the thing being charged, not a word in a subject line.
        let intlPurchase = RX.matches(#"was used for an international|international (purchase|transaction) alert"#, l)
        if !intlPurchase, RX.matches(#"\b(fee|fees|charges|penalty|surcharge)\s+(of|amounting|for|rs|inr|₹)|(levied|charged|debited)\s.{0,25}\b(fee|charges)\b|annual fee|joining fee|renewal fee|late payment (fee|charge)|finance charges?|gst on (fee|charges)"#, l) { return .fee }
        if RX.matches(#"p2a|\bneft\b|\bimps\b|\brtgs\b|zelle payment to|wire transfer|to account \*|to a/?c \*|a/c \S+ is credited"#, l) { return .transferOut }
        if rail == .directDebit { return .billPayment }
        return .purchase
    }

    // MARK: Extraction

    // Merchant name characters (underscores, +, *, & appear in real alerts) and where a name ends.
    private static let name = #"([A-Za-z0-9][A-Za-z0-9 &'._*+/\-]{1,45}?)"#
    private static let end = #"(?=\s+on\s+(?:\d|date|[A-Za-z]{3}\s)|\s+on\s*$|\s+(?:through|via|using|with|for|ref|refno|upi|avl|avbl|at\s+\d|dated|if|not|call|sms|info|was|is|has|will)\b|\s*[(\n]|[.;,:!]\s|[.;,:!]?\s*$)"#
    private static let notNames: Set<String> = ["view", "be", "your", "you", "the", "our", "us", "avoid", "help", "ensure", "keep", "report", "block",
                                                "call", "check", "know", "receive", "unsubscribe", "account", "a/c", "vpa", "upi", "bank", "card",
                                                "merchant", "customer", "self", "inform", "read", "reach", "contact", "visit", "login",
                                                "rrn", "raise", "reflect", "cancel", "cancellation", "dispute", "original", "hdfc", "kotak", "icici",
                                                "axis", "sbi", "au", "yes", "idfc", "indusind", "federal", "savings", "current", "we", "it", "this"]

    private static let merchantPatterns: [(NSRegularExpression, Bool)] = [   // (regex, creditsOnly)
        (#"(?i)\bvpa\s+\S+\s*\(([^)]{2,45})\)"#, false),
        (#"(?i)\bvpa\s+\S*@\S+\s+([A-Za-z][A-Za-z0-9 &._]{2,45}?)(?=\s+on\b)"#, false),
        (#"(?i)\bat\s+(?:upi[/-](?:p2[ma][/-])?(?:\d+[/-])?)?"# + name + end, false),
        (#"(?i)\btowards\s+(?!vpa\b|your\b|the\b)"# + name + end, false),
        (#";\s*([A-Za-z][A-Za-z0-9 .&*']{2,40}?)\s+credited"#, false),
        (#"(?i)\btransaction with\s+"# + name + end, false),
        (#"(?i)\b(?:paid to|sent to|payment to|trf to|transfer to|receipt from)\s+"# + name + end, false),
        (#"(?i)\bcr-[a-z0-9]+-([A-Za-z][A-Za-z0-9 &.]{2,45}?)-"#, true),
        (#"(?i)\b(?:by|from)\s+(?!your\b|a/c\b|account\b|card\b|bank\b|vpa\b|neft\b|imps\b)"# + name + end, true),
        (#"(?i)\bupi[/-](?:p2[ma][/-])?(?:\d+[/-])?([A-Za-z][A-Za-z0-9 .&_]{2,40}?)(?:[/-]|"# + end + ")", false),
        (#"(?i)\b(?:info|merchant|payee|narration|desc)\s*[:\-]\s*"# + name + end, false),
        (#"(?i)\bpos\s+(?:\d+\s+)?"# + name + end, false),
        (#"(?i)\bto\s+"# + name + end, false),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    static func extractMerchant(_ text: String, type: ObservationTransactionType) -> String? {
        if [.withdrawal, .creditCardPayment, .salary, .interest].contains(type) { return nil }
        let isCredit = [.refund, .transferIn, .income, .cashback, .deposit].contains(type)
        let range = NSRange(text.startIndex..., in: text)
        for (regex, creditsOnly) in merchantPatterns where !creditsOnly || isCredit {
            for m in regex.matches(in: text, range: range) {
                guard let r = Range(m.range(at: 1), in: text) else { continue }
                var candidate = String(text[r]).replacingOccurrences(of: "_", with: " ")
                if candidate.contains("@") {
                    candidate = String(candidate.split(separator: "@").first ?? "").replacingOccurrences(of: #"[._-]"#, with: " ", options: .regularExpression)
                }
                candidate = RX.replace(#"(?i)/(us|in|uk|gb|ie|sg|nl)$"#, in: candidate, with: "")
                candidate = RX.replace(#"(?i)\s+(pending|limited|limi|li|ltd|pvt)$"#, in: candidate, with: "")
                let cleaned = TextNormalization.stripIdentifiers(candidate).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                let first = cleaned.lowercased().split(separator: " ").first.map(String.init) ?? ""
                if RX.matches(#"(?i)\bbank\b"#, cleaned) { continue }
                if notNames.contains(first) || notNames.contains(cleaned.lowercased()) { continue }
                if cleaned.filter(\.isLetter).count >= 3 { return cleaned }
            }
        }
        return nil
    }

    /// Indian UPI: a debit from a bank account to a VPA that looks like a person (not a business) is money sent to someone.
    static func isPersonToPerson(_ text: String, merchant: String?) -> Bool {
        let l = text.lowercased()
        guard RX.matches(#"\bvpa\b|\bupi\b"#, l), !RX.matches(#"credit card|debit card|spent on your"#, l) else { return false }
        if RX.matches(#"vpa\s+\S*(biz|merchant|payu|razorpay|rzp|mswipe|paytmqr|bharatpe|pinelabs|cashfree|billdesk|ezetap|q\d{6,}|\.cf\b|cp\.|swiggy|zomato|zepto)"#, l) { return false }
        guard let merchant else { return false }
        return MerchantNames.looksLikePerson(merchant)
    }

    private static let refRegex = try! NSRegularExpression(pattern: #"(?i)(?:\bref(?:erence)?\.?\s*(?:no\.?|number|id|#)?|\butr\b|\brrn\b|upi\s*(?:ref|txn)?\s*(?:no\.?|id)?|txn\s*id|transaction\s*id)\s*[:#.\-]?\s*([A-Za-z0-9]{6,22})"#)
    private static let last4Regex = try! NSRegularExpression(pattern: #"(?i)(?:ending(?:\s+in)?|[xX*]{1,}|a/c(?:\s*no\.?)?\s*[xX*]*|acct\s*[xX*]*|card\s*(?:no\.?)?\s*[xX*]+)\s*(\d{3,4})\b"#)

    // Statement narrations embed the UPI reference: "UPI/P2M/426912345678/AMAZON", "UPI-SWIGGY-vpa@x-426912345678".
    private static let upiNarrationRef = try! NSRegularExpression(pattern: #"(?i)\bupi[/-](?:p2[ma][/-])?(\d{10,16})\b|\bupi[/-][^\s]*?[/-](\d{12})\b"#)

    static func extractReference(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        if let m = upiNarrationRef.firstMatch(in: text, range: range) {
            for g in 1...2 where m.range(at: g).location != NSNotFound {
                if let r = Range(m.range(at: g), in: text) { return String(text[r]) }
            }
        }
        for m in refRegex.matches(in: text, range: range) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let value = String(text[r])
            if value.contains(where: \.isNumber) { return value.uppercased() }
        }
        return nil
    }

    static func extractLast4(_ text: String) -> String? {
        guard let m = last4Regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r].suffix(4))
    }
}
