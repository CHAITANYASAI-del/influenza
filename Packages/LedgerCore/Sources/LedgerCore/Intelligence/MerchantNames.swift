import Foundation

/// Heuristics about merchant *names* (not categories).
public enum MerchantNames {
    /// Words that mark a business, in English and common Indian shop naming.
    static let businessWords: Set<String> = [
        "store", "stores", "mart", "super", "supermarket", "supermar", "market", "foods", "food", "cafe", "bakery", "hotel", "hotels",
        "hospital", "hospitals", "pharma", "pharmacy", "medical", "medicals", "retail", "traders", "trading", "enterprises", "enterprise",
        "solutions", "services", "pvt", "ltd", "llp", "limited", "company", "co", "restaurant", "bhavan", "vilas", "center", "centre",
        "coconuts", "sweets", "arena", "sports", "tech", "technologies", "motors", "moto", "mobiles", "mobile", "cell", "town", "health",
        "clinic", "labs", "lab", "salon", "studio", "fitness", "gym", "kitchen", "biryani", "tiffins", "tiffin", "juice", "chai", "tea",
        "point", "house", "palace", "dhaba", "mess", "agency", "agencies", "electricals", "electronics", "fashion", "garments", "textiles",
        "jewellers", "opticals", "travels", "tours", "school", "college", "academy", "institute", "chart", "chaat", "family", "bar",
        "pub", "brewery", "lounge", "wines", "liquor", "petroleum", "fuels", "filling", "station", "parking", "infoc", "infocomm",
        "communications", "digital", "systems", "india", "global", "international", "cafe", "coffee", "pizza", "burger", "shop",
        "shoppe", "private", "www", "com", "net", "org", "in", "pay", "payments", "online", "app", "bazaar", "bazar", "general", "provision", "provisions", "kirana", "dairy", "milk", "fruits", "vegetables", "meat",
        "chicken", "fish", "bakers", "cakes", "icecream", "creamery", "diagnostics", "dental", "eye", "care", "hardware", "paints",
        "furniture", "decor", "books", "stationery", "xerox", "print", "prints", "photo", "gifts", "toys", "footwear", "shoes",
    ]
    static let honorifics: Set<String> = ["mr", "mrs", "ms", "miss", "shri", "sri.", "smt", "kumari"]

    public static func looksLikePerson(_ name: String) -> Bool {
        if MerchantResolver.resolve(name) != nil { return false }
        if name.lowercased().contains(".com") || name.lowercased().contains("www") { return false }
        let tokens = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard (1...5).contains(tokens.count), tokens.allSatisfy({ $0.count >= 2 }) else { return false }
        if tokens.contains(where: businessWords.contains) { return false }
        if KeywordRules.match(name) != nil { return false }
        if let first = tokens.first, honorifics.contains(first) { return true }
        return tokens.count >= 2   // "Rahul Sharma", "Kona Lakshmi"
    }
}
