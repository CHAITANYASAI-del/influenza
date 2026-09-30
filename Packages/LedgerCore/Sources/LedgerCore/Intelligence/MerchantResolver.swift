import Foundation

/// Raw merchant string → canonical merchant, plus a dictionary category.
/// Bundled seed data (spec §22–24, §93, §124). Raw strings are never discarded.
public struct MerchantMatch: Sendable, Equatable {
    public let name: String
    public let categoryID: String?
    /// Marketplaces sell everything: category must come from items/user, not the name.
    public let isMarketplace: Bool
}

public enum MerchantResolver {
    public static let dictionaryVersion = "2026.09.1"

    private struct Entry { let name: String; let aliases: [String]; let category: String?; let marketplace: Bool }

    // Order matters: more specific entries first (Uber Eats before Uber, Amazon Prime before Amazon).
    private static let entries: [Entry] = [
        .init(name: "Decathlon", aliases: ["decathlon"], category: "shopping.clothing", marketplace: false),
        .init(name: "Damensch", aliases: ["damensch"], category: "shopping.clothing", marketplace: false),
        .init(name: "Tata CLiQ", aliases: ["tatacliq", "tata cliq"], category: "shopping.marketplace", marketplace: true),
        .init(name: "Styli", aliases: ["styli"], category: "shopping.clothing", marketplace: false),
        .init(name: "Playo", aliases: ["playo"], category: "entertainment.events", marketplace: false),
        .init(name: "Anthropic", aliases: ["anthropic", "claude.ai", "claude sub"], category: "bills.software", marketplace: false),
        .init(name: "LinkedIn", aliases: ["linkedin"], category: "bills.software", marketplace: false),
        .init(name: "Freepik", aliases: ["freepik"], category: "bills.software", marketplace: false),
        .init(name: "Google", aliases: ["google one", "google storage", "google cloud", "google play", "google *"], category: "bills.software", marketplace: false),
        .init(name: "iCloud", aliases: ["icloud"], category: "bills.software", marketplace: false),
        .init(name: "Notion", aliases: ["notion"], category: "bills.software", marketplace: false),
        .init(name: "GitHub", aliases: ["github"], category: "bills.software", marketplace: false),
        .init(name: "Figma", aliases: ["figma"], category: "bills.software", marketplace: false),
        .init(name: "Canva", aliases: ["canva"], category: "bills.software", marketplace: false),
        .init(name: "Adobe", aliases: ["adobe"], category: "bills.software", marketplace: false),
        .init(name: "CRED", aliases: ["cred club", "cred.club", "dreamplug"], category: "financial.creditCardPayment", marketplace: false),
        .init(name: "BigBasket", aliases: ["innovative retail", "bbnow", "bb now"], category: "food.groceries", marketplace: false),
        .init(name: "Reliance Jio", aliases: ["reliance jio", "jio infoc"], category: "bills.mobile", marketplace: false),
        .init(name: "Reliance Retail", aliases: ["reliance retail", "reliance smart", "jiomart", "reliance fresh", "reliance trends"], category: "food.groceries", marketplace: false),
        .init(name: "Ratnadeep", aliases: ["ratnadeep"], category: "food.groceries", marketplace: false),
        .init(name: "Karachi Bakery", aliases: ["karachi bakery"], category: "food.bakery", marketplace: false),
        .init(name: "Ibaco", aliases: ["ibaco"], category: "food.other", marketplace: false),
        .init(name: "The Souled Store", aliases: ["souled store", "thesouledstore"], category: "shopping.clothing", marketplace: false),
        .init(name: "Temu", aliases: ["temu"], category: "shopping.marketplace", marketplace: true),
        .init(name: "ixigo", aliases: ["ixigo"], category: "transport.flights", marketplace: false),
        .init(name: "Dr. Agarwal's Eye Hospital", aliases: ["dr agarwals", "dr agarwal"], category: "health.doctor", marketplace: false),
        .init(name: "Walmart+", aliases: ["walmart+", "walmart plus"], category: "bills.software", marketplace: false),
        .init(name: "Paytm", aliases: ["paytm"], category: "shopping.general", marketplace: true),
        .init(name: "PhonePe", aliases: ["phonepe"], category: "shopping.general", marketplace: true),
        .init(name: "Uber Eats", aliases: ["uber eats", "ubereats"], category: "food.delivery", marketplace: false),
        .init(name: "Amazon Prime", aliases: ["amazon prime", "prime video", "primevideo", "amzn prime"], category: "entertainment.streaming", marketplace: false),
        .init(name: "Amazon", aliases: ["amazon", "amzn", "amz mktp", "amazon mktplace", "amazon pay"], category: "shopping.marketplace", marketplace: true),
        .init(name: "Swiggy", aliases: ["swiggy instamart", "instamart"], category: "food.groceries", marketplace: false),
        .init(name: "Swiggy", aliases: ["swiggy", "bundl technologies"], category: "food.delivery", marketplace: false),
        .init(name: "Zomato", aliases: ["zomato", "zomato ltd", "eternal ltd", "eternal limited", "eternal"], category: "food.delivery", marketplace: false),
        .init(name: "Blinkit", aliases: ["blinkit", "grofers"], category: "food.groceries", marketplace: false),
        .init(name: "Zepto", aliases: ["zepto", "kiranakart"], category: "food.groceries", marketplace: false),
        .init(name: "BigBasket", aliases: ["bigbasket", "big basket", "supermarket grocery supplies"], category: "food.groceries", marketplace: false),
        .init(name: "DMart", aliases: ["dmart", "d mart", "avenue supermarts"], category: "food.groceries", marketplace: false),
        .init(name: "Uber", aliases: ["uber"], category: "transport.rideHailing", marketplace: false),
        .init(name: "Ola", aliases: ["ola cabs", "olacabs", "ani technologies", "ola "], category: "transport.rideHailing", marketplace: false),
        .init(name: "Rapido", aliases: ["rapido", "roppen", "rapido invoice"], category: "transport.rideHailing", marketplace: false),
        .init(name: "Lyft", aliases: ["lyft"], category: "transport.rideHailing", marketplace: false),
        .init(name: "IRCTC", aliases: ["irctc"], category: "transport.publicTransit", marketplace: false),
        .init(name: "Flipkart", aliases: ["flipkart", "fkrt"], category: "shopping.marketplace", marketplace: true),
        .init(name: "Myntra", aliases: ["myntra"], category: "shopping.clothing", marketplace: false),
        .init(name: "Ajio", aliases: ["ajio"], category: "shopping.clothing", marketplace: false),
        .init(name: "Nykaa", aliases: ["nykaa"], category: "shopping.beauty", marketplace: false),
        .init(name: "Meesho", aliases: ["meesho"], category: "shopping.marketplace", marketplace: true),
        .init(name: "Netflix", aliases: ["netflix"], category: "entertainment.streaming", marketplace: false),
        .init(name: "Spotify", aliases: ["spotify"], category: "entertainment.music", marketplace: false),
        .init(name: "YouTube Premium", aliases: ["youtube premium", "youtube", "google youtube"], category: "entertainment.streaming", marketplace: false),
        .init(name: "JioHotstar", aliases: ["hotstar", "jiohotstar", "jiocinema"], category: "entertainment.streaming", marketplace: false),
        .init(name: "BookMyShow", aliases: ["bookmyshow", "bigtree"], category: "entertainment.movies", marketplace: false),
        .init(name: "PVR INOX", aliases: ["pvr", "inox"], category: "entertainment.movies", marketplace: false),
        .init(name: "Airtel", aliases: ["airtel", "bharti airtel"], category: "bills.mobile", marketplace: false),
        .init(name: "Jio", aliases: ["reliance jio", "jio prepaid", "jio postpaid", "jio "], category: "bills.mobile", marketplace: false),
        .init(name: "Vi", aliases: ["vodafone idea", "vodafone"], category: "bills.mobile", marketplace: false),
        .init(name: "Apollo Pharmacy", aliases: ["apollo pharmacy", "apollo"], category: "health.pharmacy", marketplace: false),
        .init(name: "Tata 1mg", aliases: ["1mg", "tata 1mg"], category: "health.pharmacy", marketplace: false),
        .init(name: "PharmEasy", aliases: ["pharmeasy"], category: "health.pharmacy", marketplace: false),
        .init(name: "Cult.fit", aliases: ["cult fit", "cultfit", "curefit"], category: "health.fitness", marketplace: false),
        .init(name: "MakeMyTrip", aliases: ["makemytrip", "make my trip"], category: "transport.flights", marketplace: false),
        .init(name: "IndiGo", aliases: ["indigo", "interglobe"], category: "transport.flights", marketplace: false),
        .init(name: "Air India", aliases: ["air india"], category: "transport.flights", marketplace: false),
        .init(name: "Starbucks", aliases: ["starbucks", "tata starbucks"], category: "food.coffee", marketplace: false),
        .init(name: "Third Wave Coffee", aliases: ["third wave coffee"], category: "food.coffee", marketplace: false),
        .init(name: "McDonald's", aliases: ["mcdonald", "mcdonalds", "hardcastle"], category: "food.fastFood", marketplace: false),
        .init(name: "Domino's", aliases: ["domino", "jubilant foodworks"], category: "food.fastFood", marketplace: false),
        .init(name: "KFC", aliases: ["kfc"], category: "food.fastFood", marketplace: false),
        // US
        .init(name: "DoorDash", aliases: ["doordash", "door dash", "dd *", "dd*"], category: "food.delivery", marketplace: false),
        .init(name: "Grubhub", aliases: ["grubhub"], category: "food.delivery", marketplace: false),
        .init(name: "Instacart", aliases: ["instacart"], category: "food.groceries", marketplace: false),
        .init(name: "Whole Foods", aliases: ["whole foods", "wholefds", "wholefoods"], category: "food.groceries", marketplace: false),
        .init(name: "Trader Joe's", aliases: ["trader joe"], category: "food.groceries", marketplace: false),
        .init(name: "Ralphs", aliases: ["ralphs"], category: "food.groceries", marketplace: false),
        .init(name: "Kroger", aliases: ["kroger"], category: "food.groceries", marketplace: false),
        .init(name: "Safeway", aliases: ["safeway"], category: "food.groceries", marketplace: false),
        .init(name: "Walmart", aliases: ["walmart", "wal-mart", "wm supercenter"], category: "shopping.general", marketplace: true),
        .init(name: "Target", aliases: ["target"], category: "shopping.general", marketplace: true),
        .init(name: "Costco", aliases: ["costco"], category: "shopping.general", marketplace: true),
        .init(name: "Apple", aliases: ["apple.com/bill", "apple com bill", "itunes", "apple store", "apple.com"], category: "shopping.electronics", marketplace: true),
        .init(name: "Chipotle", aliases: ["chipotle"], category: "food.fastFood", marketplace: false),
        .init(name: "Shell", aliases: ["shell oil", "shell "], category: "transport.fuel", marketplace: false),
        .init(name: "Chevron", aliases: ["chevron"], category: "transport.fuel", marketplace: false),
        .init(name: "CVS", aliases: ["cvs"], category: "health.pharmacy", marketplace: false),
        .init(name: "Walgreens", aliases: ["walgreens"], category: "health.pharmacy", marketplace: false),
        .init(name: "Airbnb", aliases: ["airbnb"], category: "transport.hotels", marketplace: false),
        .init(name: "Booking.com", aliases: ["booking.com", "booking com"], category: "transport.hotels", marketplace: false),
        .init(name: "ChatGPT", aliases: ["openai", "chatgpt"], category: "entertainment.streaming", marketplace: false),
        .init(name: "Verizon", aliases: ["verizon"], category: "bills.mobile", marketplace: false),
        .init(name: "AT&T", aliases: ["at&t", "att*"], category: "bills.mobile", marketplace: false),
        .init(name: "T-Mobile", aliases: ["t-mobile", "tmobile"], category: "bills.mobile", marketplace: false),
        .init(name: "Comcast Xfinity", aliases: ["comcast", "xfinity"], category: "bills.internet", marketplace: false),
    ]

    /// One precompiled regex per entry (word-bounded aliases), built once.
    private static let compiled: [(Entry, NSRegularExpression?, [String])] = entries.map { e in
        let words = e.aliases.filter { !($0.hasSuffix(" ") || $0.hasSuffix("*")) }
        let literal = e.aliases.filter { $0.hasSuffix(" ") || $0.hasSuffix("*") }
        // Long aliases also match glued names ("zomatofood", "swiggyinstamart"); short ones need whole words.
        let pattern = words.map { w in "\\b\(NSRegularExpression.escapedPattern(for: w))" + (w.count >= 5 ? "" : "\\b") }.joined(separator: "|")
        return (e, words.isEmpty ? nil : try? NSRegularExpression(pattern: pattern), literal)
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: MerchantMatch?] = [:]

    public static func resolve(_ raw: String?) -> MerchantMatch? {
        guard let raw, !raw.isEmpty else { return nil }
        lock.lock()
        if let hit = cache[raw] { lock.unlock(); return hit }
        lock.unlock()
        let text = " " + raw.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) + " "
        let range = NSRange(text.startIndex..., in: text)
        var result: MerchantMatch?
        for (e, regex, literal) in compiled where literal.contains(where: text.contains) || regex?.firstMatch(in: text, range: range) != nil {
            result = MerchantMatch(name: e.name, categoryID: e.category, isMarketplace: e.marketplace)
            break
        }
        lock.lock()
        if cache.count > 20_000 { cache.removeAll(keepingCapacity: true) }
        cache[raw] = result
        lock.unlock()
        return result
    }

    /// Display name when the dictionary doesn't know the merchant.
    public static func cleanDisplayName(_ raw: String) -> String {
        var s = TextNormalization.stripIdentifiers(raw)
        let noise = #"(?i)\b(upi|p2m|p2a|pos|ecom|purchase|payment|debit|credit|card|visa|mastercard|rupay|pvt|ltd|llc|inc|private|limited|india|in|com|www|sq|tst|paypal)\b"#
        s = RX.replace(noise, in: s, with: " ")
        s = TextNormalization.collapse(s).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return s.isEmpty ? TextNormalization.titleCase(TextNormalization.collapse(raw)) : TextNormalization.titleCase(s)
    }

    /// Stable key for user rules & matching.
    public static func key(_ raw: String?) -> String {
        guard let raw else { return "" }
        if let match = resolve(raw) { return match.name.lowercased() }
        return TextNormalization.tokens(cleanDisplayName(raw)).prefix(3).joined(separator: " ")
    }

    static func similarity(_ a: String?, _ b: String?) -> Double {
        let ka = key(a), kb = key(b)
        guard !ka.isEmpty, !kb.isEmpty else { return 0 }
        if ka == kb { return 1 }
        if ka.contains(kb) || kb.contains(ka) { return 0.8 }
        let ta = Set(ka.split(separator: " ")), tb = Set(kb.split(separator: " "))
        return Double(ta.intersection(tb).count) / Double(max(ta.union(tb).count, 1))
    }
}
