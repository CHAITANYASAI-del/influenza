import Foundation

/// Brand metadata for display: website domain (for the brand's own logo) and
/// brand colour (for the monogram fallback). Bundled, no user data involved.
public struct BrandInfo: Sendable, Equatable {
    public let domain: String?
    public let colorHex: String
}

public enum BrandCatalog {
    private static let brands: [String: BrandInfo] = [
        "Anthropic": .init(domain: "anthropic.com", colorHex: "D97757"), "LinkedIn": .init(domain: "linkedin.com", colorHex: "0A66C2"),
        "Freepik": .init(domain: "freepik.com", colorHex: "1273EB"), "CRED": .init(domain: "cred.club", colorHex: "000000"),
        "Reliance Jio": .init(domain: "jio.com", colorHex: "0F3CC9"), "Reliance Retail": .init(domain: "relianceretail.com", colorHex: "E31E24"),
        "Ratnadeep": .init(domain: "ratnadeepretail.com", colorHex: "E2231A"), "Karachi Bakery": .init(domain: "karachibakery.com", colorHex: "8B1D1D"),
        "The Souled Store": .init(domain: "thesouledstore.com", colorHex: "E11B22"), "Temu": .init(domain: "temu.com", colorHex: "FB7701"),
        "ixigo": .init(domain: "ixigo.com", colorHex: "FC790D"), "Google": .init(domain: "google.com", colorHex: "4285F4"),
        "Notion": .init(domain: "notion.so", colorHex: "000000"), "GitHub": .init(domain: "github.com", colorHex: "181717"),
        "Figma": .init(domain: "figma.com", colorHex: "F24E1E"), "Canva": .init(domain: "canva.com", colorHex: "00C4CC"),
        "Adobe": .init(domain: "adobe.com", colorHex: "FA0F00"), "Paytm": .init(domain: "paytm.com", colorHex: "00BAF2"),
        "PhonePe": .init(domain: "phonepe.com", colorHex: "5F259F"),
        "Tata CLiQ": .init(domain: "tatacliq.com", colorHex: "DA1C5C"), "Decathlon": .init(domain: "decathlon.in", colorHex: "0082C3"),
        "Damensch": .init(domain: "damensch.com", colorHex: "000000"), "Styli": .init(domain: "stylishop.com", colorHex: "000000"),
        "Playo": .init(domain: "playo.co", colorHex: "00B562"), "Walmart+": .init(domain: "walmart.com", colorHex: "0071CE"),
        "Dr. Agarwal's Eye Hospital": .init(domain: "dragarwal.com", colorHex: "0E4C92"), "Ibaco": .init(domain: "ibaco.in", colorHex: "6B2C91"),
        "Swiggy": .init(domain: "swiggy.com", colorHex: "FC8019"), "Zomato": .init(domain: "zomato.com", colorHex: "E23744"),
        "Blinkit": .init(domain: "blinkit.com", colorHex: "F8CB46"), "Zepto": .init(domain: "zeptonow.com", colorHex: "5E17EB"),
        "BigBasket": .init(domain: "bigbasket.com", colorHex: "84C225"), "DMart": .init(domain: "dmart.in", colorHex: "00843D"),
        "Uber": .init(domain: "uber.com", colorHex: "000000"), "Uber Eats": .init(domain: "ubereats.com", colorHex: "06C167"),
        "Ola": .init(domain: "olacabs.com", colorHex: "000000"), "Rapido": .init(domain: "rapido.bike", colorHex: "F9C933"),
        "Lyft": .init(domain: "lyft.com", colorHex: "FF00BF"), "IRCTC": .init(domain: "irctc.co.in", colorHex: "1B3C73"),
        "Amazon": .init(domain: "amazon.in", colorHex: "FF9900"), "Amazon Prime": .init(domain: "primevideo.com", colorHex: "00A8E1"),
        "Flipkart": .init(domain: "flipkart.com", colorHex: "2874F0"), "Myntra": .init(domain: "myntra.com", colorHex: "FF3F6C"),
        "Ajio": .init(domain: "ajio.com", colorHex: "2C4152"), "Nykaa": .init(domain: "nykaa.com", colorHex: "FC2779"),
        "Meesho": .init(domain: "meesho.com", colorHex: "F43397"), "Netflix": .init(domain: "netflix.com", colorHex: "E50914"),
        "Spotify": .init(domain: "spotify.com", colorHex: "1DB954"), "YouTube Premium": .init(domain: "youtube.com", colorHex: "FF0000"),
        "JioHotstar": .init(domain: "hotstar.com", colorHex: "0F1014"), "BookMyShow": .init(domain: "bookmyshow.com", colorHex: "F84464"),
        "PVR INOX": .init(domain: "pvrcinemas.com", colorHex: "FFC72C"), "Airtel": .init(domain: "airtel.in", colorHex: "E40000"),
        "Jio": .init(domain: "jio.com", colorHex: "0F3CC9"), "Vi": .init(domain: "myvi.in", colorHex: "EE2737"),
        "Apollo Pharmacy": .init(domain: "apollopharmacy.in", colorHex: "0A7C8B"), "Tata 1mg": .init(domain: "1mg.com", colorHex: "FF6F61"),
        "PharmEasy": .init(domain: "pharmeasy.in", colorHex: "10847E"), "Cult.fit": .init(domain: "cult.fit", colorHex: "000000"),
        "MakeMyTrip": .init(domain: "makemytrip.com", colorHex: "E73C33"), "IndiGo": .init(domain: "goindigo.in", colorHex: "001B94"),
        "Air India": .init(domain: "airindia.com", colorHex: "DA0A0A"), "Starbucks": .init(domain: "starbucks.com", colorHex: "00704A"),
        "Third Wave Coffee": .init(domain: "thirdwavecoffee.in", colorHex: "1D1D1B"), "McDonald's": .init(domain: "mcdonalds.com", colorHex: "FFC72C"),
        "Domino's": .init(domain: "dominos.co.in", colorHex: "006491"), "KFC": .init(domain: "kfc.co.in", colorHex: "E4002B"),
        "DoorDash": .init(domain: "doordash.com", colorHex: "FF3008"), "Grubhub": .init(domain: "grubhub.com", colorHex: "F63440"),
        "Instacart": .init(domain: "instacart.com", colorHex: "43B02A"), "Whole Foods": .init(domain: "wholefoodsmarket.com", colorHex: "00674B"),
        "Trader Joe's": .init(domain: "traderjoes.com", colorHex: "D21F2B"), "Ralphs": .init(domain: "ralphs.com", colorHex: "E31837"),
        "Kroger": .init(domain: "kroger.com", colorHex: "0F4C92"), "Safeway": .init(domain: "safeway.com", colorHex: "E21A2C"),
        "Walmart": .init(domain: "walmart.com", colorHex: "0071CE"), "Target": .init(domain: "target.com", colorHex: "CC0000"),
        "Costco": .init(domain: "costco.com", colorHex: "005DAA"), "Apple": .init(domain: "apple.com", colorHex: "000000"),
        "Chipotle": .init(domain: "chipotle.com", colorHex: "A81612"), "Shell": .init(domain: "shell.com", colorHex: "FBCE07"),
        "Chevron": .init(domain: "chevron.com", colorHex: "0054A4"), "CVS": .init(domain: "cvs.com", colorHex: "CC0000"),
        "Walgreens": .init(domain: "walgreens.com", colorHex: "E31837"), "Airbnb": .init(domain: "airbnb.com", colorHex: "FF5A5F"),
        "Booking.com": .init(domain: "booking.com", colorHex: "003580"), "ChatGPT": .init(domain: "openai.com", colorHex: "10A37F"),
        "Verizon": .init(domain: "verizon.com", colorHex: "CD040B"), "AT&T": .init(domain: "att.com", colorHex: "00A8E0"),
        "T-Mobile": .init(domain: "t-mobile.com", colorHex: "E20074"), "Comcast Xfinity": .init(domain: "xfinity.com", colorHex: "000000"),
    ]

    /// Category used for the placeholder icon when only a name is known.
    public static func defaultCategory(for merchantName: String) -> String {
        MerchantResolver.resolve(merchantName)?.categoryID ?? KeywordRules.match(merchantName)?.0 ?? "other.unknown"
    }

    public static func info(for merchantName: String) -> BrandInfo {
        if let known = brands[merchantName] { return known }
        // Stable pleasant colour for unknown shops, derived from the name (deterministic).
        let palette = ["5B6CFF", "FF7A59", "12B886", "F59F00", "BE4BDB", "15AABF", "E64980", "4C6EF5", "82C91E", "FA5252"]
        let sum = merchantName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return BrandInfo(domain: nil, colorHex: palette[sum % palette.count])
    }
}

/// Month-by-month series used for trend bars and "vs 3/6-month average".
public struct MonthlyPoint: Sendable, Identifiable, Equatable {
    public var id: Date { monthStart }
    public let monthStart: Date
    public let spent: Decimal
}

extension LedgerEngine {
    /// Spending per calendar month for the last `months` months (oldest first), optionally filtered.
    public func monthlySpending(currency: String, months: Int, endingAt anchor: Date = .now, calendar: Calendar = .current,
                                where include: ((CanonicalTransaction) -> Bool)? = nil) -> [MonthlyPoint] {
        guard let current = calendar.dateInterval(of: .month, for: anchor)?.start else { return [] }
        let starts = (0..<months).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
        guard let first = starts.first, let end = calendar.date(byAdding: .month, value: 1, to: current) else { return [] }
        var totals: [Date: Decimal] = [:]
        for tx in state.transactions.values where tx.currencyCode == currency && tx.transactionDate >= first && tx.transactionDate < end {
            guard include?(tx) ?? true else { continue }
            let key = calendar.dateInterval(of: .month, for: tx.transactionDate)!.start
            if AggregationService.isSpending(tx) { totals[key, default: 0] += tx.amount }
            else if tx.isRefund, let p = tx.refundLinkIDs.first.flatMap({ state.transactions[$0] }), AggregationService.isSpending(p) {
                totals[key, default: 0] -= tx.amount
            }
        }
        return starts.map { MonthlyPoint(monthStart: $0, spent: totals[$0] ?? 0) }
    }
}
