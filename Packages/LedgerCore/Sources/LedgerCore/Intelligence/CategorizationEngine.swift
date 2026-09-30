import Foundation

public struct CategoryDecision: Sendable, Equatable {
    public let categoryID: String
    public let confidence: Double
    public let reason: String
}

/// Deterministic pipeline (spec §26):
/// user rule → flow type → receipt items → merchant dictionary → keywords → fallback.
public enum CategorizationEngine {
    public static let rulesVersion = "cat-1.0"

    public static func categorize(merchantRaw: String?, merchantName: String?, flow: FlowType, type: ObservationTransactionType,
                                  items: [ReceiptItem], userRules: [String: String], rail: PaymentRail = .unknown) -> CategoryDecision {
        let key = MerchantResolver.key(merchantName ?? merchantRaw)
        if let rule = userRules[key], !key.isEmpty {
            return .init(categoryID: rule, confidence: 1, reason: "You chose this category for \(merchantName ?? "this merchant").")
        }

        switch type {
        case .creditCardPayment: return .init(categoryID: "financial.creditCardPayment", confidence: 0.99, reason: "Credit-card bill payment — not counted as spending.")
        case .internalTransfer: return .init(categoryID: "financial.transfer", confidence: 0.95, reason: "Moved to your own account — not spending.")
        case .transferOut:
            return .init(categoryID: "people.other", confidence: 0.7,
                         reason: "Money sent to a person. Mark them as Family or Friends once and Influenza remembers.")
        case .transferIn: return .init(categoryID: "financial.transfer", confidence: 0.8, reason: "Money received.")
        case .withdrawal: return .init(categoryID: "financial.atm", confidence: 0.99, reason: "Cash withdrawal — becomes cash, not spending.")
        case .fee: return .init(categoryID: "financial.bankFee", confidence: 0.9, reason: "Bank or card fee.")
        case .salary: return .init(categoryID: "income.salary", confidence: 0.95, reason: "Salary credit.")
        case .interest: return .init(categoryID: "income.interest", confidence: 0.95, reason: "Interest credit.")
        case .cashback: return .init(categoryID: "income.cashback", confidence: 0.95, reason: "Cashback.")
        case .refund: return .init(categoryID: "income.refund", confidence: 0.9, reason: "Refund.")
        case .income, .deposit: return .init(categoryID: "income.other", confidence: 0.7, reason: "Money received.")
        default: break
        }

        let match = MerchantResolver.resolve(merchantName) ?? MerchantResolver.resolve(merchantRaw)

        if !items.isEmpty, let fromItems = ItemVocabulary.category(for: items) {
            return .init(categoryID: fromItems.id, confidence: fromItems.confidence,
                         reason: "Receipt items (\(items.prefix(2).map(\.name).joined(separator: ", "))) indicate \(CategoryTree.displayName(fromItems.id)).")
        }
        if let match, let cat = match.categoryID {
            return match.isMarketplace
                ? .init(categoryID: cat, confidence: 0.5, reason: "\(match.name) sells many kinds of things — add a receipt or pick a category to be precise.")
                : .init(categoryID: cat, confidence: 0.95, reason: "\(match.name) is a known \(CategoryTree.displayName(cat)) merchant.")
        }
        if let (cat, word) = KeywordRules.match(merchantRaw ?? merchantName ?? "") {
            return .init(categoryID: cat, confidence: 0.75, reason: "Description mentions “\(word)”.")
        }
        if type == .billPayment { return .init(categoryID: "bills.insurance", confidence: 0.4, reason: "Direct debit — probably a bill.") }
        if let name = merchantName ?? merchantRaw, MerchantNames.looksLikePerson(name) || rail == .upi {
            return .init(categoryID: "other.local", confidence: 0.45,
                         reason: "A local shop or service paid by UPI. Pick a category once and Influenza remembers \(name).")
        }
        return .init(categoryID: "other.unknown", confidence: 0.2, reason: "Unknown merchant.")
    }
}

/// Product vocabulary for marketplace receipts (Amazon, Walmart, Target, Flipkart…).
enum ItemVocabulary {
    static let groups: [(String, [String])] = [
        ("shopping.electronics", ["macbook", "laptop", "iphone", "ipad", "phone", "charger", "headphone", "earbuds", "airpods", "cable", "usb", "monitor", "keyboard", "mouse", "tv", "television", "speaker", "camera", "power bank", "adapter", "ssd", "hdmi", "watch", "case"]),
        ("shopping.books", ["book", "novel", "paperback", "hardcover", "kindle edition", "notebook"]),
        ("shopping.personalCare", ["detergent", "soap", "shampoo", "conditioner", "toothpaste", "toothbrush", "tissue", "toilet paper", "dish", "cleaner", "handwash", "deodorant", "razor", "sanitizer", "diaper", "wipes", "laundry"]),
        ("food.groceries", ["milk", "eggs", "egg", "bread", "vegetable", "vegetables", "fruit", "fruits", "rice", "flour", "atta", "dal", "butter", "cheese", "chicken", "paneer", "yogurt", "curd", "banana", "apple", "onion", "tomato", "potato", "oil", "sugar", "cereal", "coffee beans", "tea"]),
        ("shopping.clothing", ["shirt", "t-shirt", "tshirt", "jeans", "dress", "shoes", "sneakers", "jacket", "kurta", "saree", "socks", "trousers", "hoodie"]),
        ("shopping.beauty", ["lipstick", "serum", "moisturizer", "moisturiser", "sunscreen", "perfume", "foundation", "mascara", "face wash"]),
        ("shopping.home", ["pillow", "bedsheet", "towel", "lamp", "chair", "table", "curtain", "cookware", "pan", "bottle", "storage", "bulb"]),
    ]

    static func category(for items: [ReceiptItem]) -> (id: String, confidence: Double)? {
        var scores: [String: Int] = [:]
        for item in items {
            let name = " \(item.name.lowercased()) "
            for (cat, words) in groups where words.contains(where: { name.contains(" \($0)") || name.contains("\($0) ") }) {
                scores[cat, default: 0] += 1
                break
            }
        }
        let total = scores.values.reduce(0, +)
        guard total > 0, let best = scores.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(best.value) / Double(total)
        // Mixed baskets: don't pretend. Keep general shopping with receipt detail.
        return share >= 0.6 ? (best.key, 0.6 + 0.35 * share) : ("shopping.general", 0.5)
    }
}

/// Generic keyword rules for merchants not in the dictionary.
enum KeywordRules {
    static let rules: [(String, [String])] = [
        ("food.coffee", ["coffee", "cafe", "café", "espresso", "chai", "tea stall"]),
        ("food.bakery", ["bakery", "bakers", "cake", "patisserie"]),
        ("food.fastFood", ["burger", "pizza", "subway", "taco", "fried chicken", "wendy"]),
        ("food.restaurant", ["bhavan", "vilas", "appetite", "cut cook", "chart cent", "chaat", "restaurant", "resto", "dhaba", "bistro", "diner", "eatery", "kitchen", "biryani", "grill", "bar ", "pub", "brewery"]),
        ("food.groceries", ["coconut", "super market", "supermarket", "grocery", "grocer", "supermarket", "hypermarket", "mart", "kirana", "provision", "vegetable", "fruits", "dairy", "7-eleven", "aldi", "lidl", "tesco", "sainsbury", "carrefour", "lulu"]),
        ("transport.fuel", ["petrol", "diesel", "fuel", "hpcl", "bpcl", "indian oil", "iocl", "gas station", "exxon", "bp "]),
        ("transport.parking", ["parking"]),
        ("transport.tolls", ["toll", "fastag", "e-zpass", "ezpass"]),
        ("transport.publicTransit", ["metro", "railway", "rail", "bus", "transit", "mta", "tfl", "clipper", "redbus"]),
        ("transport.flights", ["airline", "airways", "airport", "flight"]),
        ("transport.hotels", ["hotel", "resort", "inn ", "oyo", "hostel", "lodge", "marriott", "hilton", "hyatt", "taj"]),
        ("transport.rideHailing", ["cab", "taxi", "auto rickshaw"]),
        ("bills.electricity", ["electricity", "power", "bescom", "msedcl", "tata power", "adani electricity", "con edison", "pg&e"]),
        ("bills.water", ["water board", "water supply", "jal"]),
        ("bills.gas", ["lpg", "indane", "bharatgas", "hp gas", "gas bill"]),
        ("bills.internet", ["broadband", "fiber", "fibernet", "internet", "wifi"]),
        ("bills.mobile", ["recharge", "prepaid", "postpaid", "mobile bill"]),
        ("bills.insurance", ["insurance", "lic ", "policy", "premium"]),
        ("bills.rent", ["rent", "nobroker", "landlord", "housing society", "maintenance"]),
        ("bills.software", ["software", "saas", "cloud", "hosting", "domain", "openai", "vercel", "aws", "digitalocean"]),
        ("entertainment.streaming", ["subscription", "streaming", "prime", "disney", "hulu", "hbo", "zee5", "sonyliv"]),
        ("entertainment.sports", ["sports arena", "sports", "arena", "turf", "badminton", "court", "cricket", "football", "futsal", "pickleball", "swimming", "playo", "hudle", "sports club", "box cricket"]),
        ("entertainment.gaming", ["steam", "playstation", "xbox", "nintendo", "epic games", "game"]),
        ("entertainment.movies", ["cinema", "movie", "multiplex", "amc", "cineworld", "cinepolis"]),
        ("entertainment.events", ["ticket", "concert", "event", "ticketmaster", "eventbrite"]),
        ("health.pharmacy", ["pharmacy", "pharma", "chemist", "medical store", "medicos", "drug"]),
        ("health.doctor", ["eye hospital", "hospital", "clinic", "doctor", "diagnostic", "lab ", "pathology", "practo"]),
        ("health.dental", ["dental", "dentist"]),
        ("health.fitness", ["gym", "fitness", "yoga"]),
        ("education.courses", ["udemy", "coursera", "course", "academy", "tuition", "classes"]),
        ("education.fees", ["school", "college", "university", "exam fee"]),
        ("shopping.clothing", ["fashion", "apparel", "clothing", "garments", "footwear", "zara", "h&m", "uniqlo", "nike", "adidas"]),
        ("shopping.electronics", ["electronics", "digital", "croma", "best buy", "mobile store", "mobiles", "cell town", "cell point", "audio store"]),
        ("shopping.home", ["furniture", "ikea", "home centre", "hardware"]),
        ("shopping.general", ["store", "shop", "mall", "retail", "traders", "enterprises"]),
    ]

    /// Whole words only: "chai" must not match "Chaitra", "bar" must not match "Barbeque Nation".
    static func match(_ text: String) -> (String, String)? {
        let t = " " + text.lowercased().replacingOccurrences(of: #"[^a-z0-9&+ ]"#, with: " ", options: .regularExpression) + " "
        for (cat, words) in rules {
            if let w = words.first(where: { t.contains(" " + $0.trimmingCharacters(in: .whitespaces) + " ") }) {
                return (cat, w.trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}
