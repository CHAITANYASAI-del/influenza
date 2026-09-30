import LedgerCore
import SwiftUI

enum CategoryStyle {
    static func tint(_ categoryID: String) -> Color {
        switch CategoryTree.node(categoryID)?.topLevelID ?? "other" {
        case "food": Color(hex: "C27A45")
        case "transport": Color(hex: "4F74A8")
        case "shopping": Color(hex: "B0607E")
        case "bills": Color(hex: "B39037")
        case "entertainment": Color(hex: "7E62A8")
        case "health": Color(hex: "B85A48")
        case "education": Color(hex: "3F8C7D")
        case "financial": Color(hex: "8C8C8C")
        case "income": Color(hex: "3C8F63")
        default: Color(hex: "9A9A9A")
        }
    }
    static func hex(_ categoryID: String) -> String {
        ["food": "C27A45", "transport": "4F74A8", "shopping": "B0607E", "bills": "B39037", "entertainment": "7E62A8",
         "health": "B85A48", "education": "3F8C7D", "financial": "8C8C8C", "income": "3C8F63"][CategoryTree.node(categoryID)?.topLevelID ?? "other"] ?? "8E8E93"
    }
    static func symbol(_ categoryID: String) -> String {
        let specific: [String: String] = [
            "food.delivery": "takeoutbag.and.cup.and.straw.fill", "food.groceries": "cart.fill", "food.coffee": "cup.and.saucer.fill",
            "transport.fuel": "fuelpump.fill", "transport.flights": "airplane", "transport.hotels": "bed.double.fill",
            "transport.rideHailing": "car.fill", "transport.publicTransit": "tram.fill", "shopping.electronics": "laptopcomputer",
            "shopping.books": "book.fill", "shopping.clothing": "tshirt.fill", "entertainment.streaming": "play.tv.fill",
            "entertainment.music": "music.note", "bills.mobile": "iphone", "bills.internet": "wifi", "health.pharmacy": "pills.fill",
            "health.fitness": "figure.run", "financial.atm": "banknote.fill", "financial.creditCardPayment": "creditcard.fill",
            "financial.transfer": "arrow.left.arrow.right", "income.salary": "briefcase.fill", "income.refund": "arrow.uturn.backward",
            "food.restaurant": "fork.knife", "food.fastFood": "takeoutbag.and.cup.and.straw.fill", "food.bakery": "birthday.cake.fill",
            "shopping.local": "storefront.fill", "shopping.marketplace": "shippingbox.fill", "shopping.beauty": "sparkles",
            "bills.software": "app.badge.fill", "bills.electricity": "bolt.fill", "bills.rent": "house.fill", "health.doctor": "stethoscope",
            "entertainment.movies": "film.fill", "entertainment.events": "ticket.fill", "entertainment.gaming": "gamecontroller.fill",
            "transport.tolls": "road.lanes", "transport.parking": "parkingsign", "other.unknown": "questionmark.square.dashed",
        ]
        return specific[categoryID] ?? CategoryTree.node(categoryID).flatMap { CategoryTree.node($0.topLevelID)?.symbol } ?? "questionmark"
    }
}

struct CategoryBadge: View {
    let categoryID: String
    var size: CGFloat = 40
    var body: some View { CategoryIcon3D(categoryID: categoryID, size: size) }
}

struct StatusPill: View {
    let status: VerificationStatus
    var body: some View {
        switch status {
        case .verified: EmptyView()
        case .userEntered: EmptyView()
        case .detected: EmptyView()
        case .pendingReview: PopTag(text: "review", color: Pop.negative)
        }
    }
    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule).foregroundStyle(color)
    }
}

struct TransactionRow: View {
    let tx: CanonicalTransaction

    private var signedAmount: Decimal { tx.direction == .credit ? tx.amount : -tx.amount }
    private var excluded: Bool { tx.isInternalTransfer || tx.isExcludedByUser }

    var body: some View {
        HStack(spacing: 14) {
            BrandLogo(name: tx.displayMerchant, categoryID: tx.categoryID, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(tx.displayMerchant).font(.system(size: 16, weight: .semibold)).foregroundStyle(Pop.ink).lineLimit(1)
                    StatusPill(status: tx.verificationStatus)
                }
                Text(subtitle).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Pop.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                MoneyText(amount: excluded ? tx.amount : signedAmount, currency: tx.currencyCode, size: 16, signed: tx.direction == .credit && !excluded)
                    .foregroundStyle(tx.direction == .credit && !excluded ? Pop.positive : Pop.ink)
                    .strikethrough(tx.isExcludedByUser)
                Text(excluded ? "EXCLUDED" : (tx.paymentRail == .unknown ? tx.transactionDate.formatted(.dateTime.day().month(.abbreviated)).uppercased() : tx.paymentRail.displayName.uppercased()))
                    .font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Pop.ink2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tx.displayMerchant), \(CategoryTree.displayName(tx.categoryID)), \(Fmt.spoken(tx.amount, tx.currencyCode)), \(tx.verificationStatus.rawValue)")
    }

    private var subtitle: String {
        var parts = [CategoryTree.node(tx.categoryID)?.name ?? "Other"]
        if let detail = tx.merchantDetail { parts.append(detail) }
        if tx.isRefund && !tx.refundLinkIDs.isEmpty { parts.append("refund linked") }
        return parts.joined(separator: " · ").uppercased()
    }
}

struct AmbientBackground: View {
    var body: some View { Pop.canvas.ignoresSafeArea() }
}

/// Main call to action: CRED's NeoPOP floating button (levitating 3D block + shimmer).
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    var body: some View {
        NeoFloatingButton(title: title, action: action)
            .frame(height: 60)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Grouping per spec §52.
enum TimelineGroup: Int, CaseIterable {
    case today, yesterday, thisWeek, lastWeek, earlier
    var title: String { ["Today", "Yesterday", "This week", "Last week", "Earlier"][rawValue] }

    static func of(_ date: Date, cal: Calendar = .current) -> TimelineGroup {
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        if cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear) { return .thisWeek }
        if let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: .now), cal.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) { return .lastWeek }
        return .earlier
    }
}
