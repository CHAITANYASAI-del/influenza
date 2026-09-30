import Foundation

/// The only data the widget ever sees (spec §57): small, derived, no merchants'
/// raw text, no account numbers. Written atomically to the App Group container.
struct WidgetSnapshot: Codable, Sendable {
    struct Category: Codable, Sendable, Hashable { let name: String; let symbol: String; let colorHex: String; let amount: Decimal }
    struct Brand: Codable, Sendable, Hashable {
        let name: String; let colorHex: String; let amount: Decimal
        var logoFile: String? = nil
    }

    var generatedAt: Date
    var currency: String
    var monthName: String
    var monthSpend: Decimal
    var todaySpend: Decimal
    var lastMonthSameDay: Decimal
    var topCategories: [Category]
    var topBrands: [Brand]
    var reviewCount: Int
    var nextRecurring: String?
    var hasData: Bool
    var spentOnThings: Decimal? = nil
    /// Money out per day for the last 7 days, oldest first (today last).
    var last7Days: [Decimal]? = nil
    var sentToPeople: Decimal? = nil

    static let appGroup = "group.com.chaitanyasai.influenza"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "widget-snapshot.json")
    }

    static var containerURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) }

    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write() throws {
        guard let url = Self.url else { return }
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static let placeholder = WidgetSnapshot(
        generatedAt: .now, currency: Locale.current.currency?.identifier ?? "INR", monthName: Date.now.formatted(.dateTime.month(.wide)),
        monthSpend: 24_860, todaySpend: 640, lastMonthSameDay: 27_300,
        topCategories: [.init(name: "Food", symbol: "fork.knife", colorHex: "C27A45", amount: 9_420),
                        .init(name: "Shopping", symbol: "bag.fill", colorHex: "B0607E", amount: 7_300),
                        .init(name: "People", symbol: "person.2.fill", colorHex: "6F7FA8", amount: 4_500),
                        .init(name: "Transport", symbol: "car.fill", colorHex: "4F74A8", amount: 3_150)],
        topBrands: [.init(name: "Swiggy", colorHex: "FC8019", amount: 4_200), .init(name: "Amazon", colorHex: "FF9900", amount: 3_900),
                    .init(name: "Uber", colorHex: "000000", amount: 1_850)],
        reviewCount: 2, nextRecurring: "Netflix · 3 Oct", hasData: true,
        last7Days: [820, 240, 1_350, 0, 560, 2_100, 640])
}
