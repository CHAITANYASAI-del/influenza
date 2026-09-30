import SwiftUI
import UIKit
import WidgetKit

/// Read-only consumer of the app's prepared snapshot (spec §55–61). Styled like the
/// app: off-white canvas, big serif money, letter-spaced small caps, category coins.
private enum W {
    static let canvas = Color(hex: "F2F1EE")
    static let sheet = Color.white
    static let ink = Color(hex: "111111")
    static let ink2 = Color(hex: "7A7A7A")
    static let hairline = Color(hex: "E4E4E1")
    static let positive = Color(hex: "0E9F6E")
    static let negative = Color(hex: "E0662A")
}

struct SpendEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendEntry { SpendEntry(date: .now, snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (SpendEntry) -> Void) {
        completion(SpendEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendEntry>) -> Void) {
        completion(Timeline(entries: [SpendEntry(date: .now, snapshot: WidgetSnapshot.read())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

/// ₹10.7K style for tight spaces.
enum Short {
    static func money(_ v: Decimal, _ currency: String) -> String {
        let d = (v as NSDecimalNumber).doubleValue
        return d >= 10_000 ? d.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0...1)))
                           : SharedFormat.money(v, currency)
    }
}

// MARK: - Pieces

private struct Caps: View {
    let text: String
    var color: Color = W.ink2
    var size: CGFloat = 10
    var body: some View {
        Text(text.uppercased()).font(.system(size: size, weight: .semibold)).tracking(size * 0.18).foregroundStyle(color).lineLimit(1)
    }
}

/// "₹24,860" — bold serif, rupees only (paise are noise at a glance).
private struct Amount: View {
    let value: Decimal
    let currency: String
    let size: CGFloat
    var body: some View {
        Text(SharedFormat.money(value, currency))
            .font(.system(size: size, weight: .semibold, design: .serif))
            .foregroundStyle(W.ink)
            .monospacedDigit()
            .minimumScaleFactor(0.55).lineLimit(1)
            .contentTransition(.numericText(value: (value as NSDecimalNumber).doubleValue))
            .privacySensitive()
    }
}

private struct Delta: View {
    let s: WidgetSnapshot
    var compact = false
    var body: some View {
        if s.lastMonthSameDay > 0 {
            let d = s.monthSpend - s.lastMonthSameDay
            HStack(spacing: 3) {
                Image(systemName: d <= 0 ? "arrow.down.right" : "arrow.up.right").font(.system(size: 9, weight: .heavy))
                Text("\(Short.money(abs(d), s.currency)) \(d <= 0 ? "less" : "more")\(compact ? "" : " than last month")".uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1)
            }
            .foregroundStyle(d <= 0 ? W.positive : W.negative)
            .lineLimit(1).minimumScaleFactor(0.7)
            .privacySensitive()
        }
    }
}

private struct Coin: View {
    let symbol: String
    let hex: String
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Color(hex: hex))
            .frame(width: size, height: size)
            .background(Color(hex: hex).opacity(0.14), in: .circle)
            .overlay(Circle().stroke(W.hairline, lineWidth: 0.5))
    }
}

private struct BrandCoin: View {
    let brand: WidgetSnapshot.Brand
    var size: CGFloat = 26
    var body: some View {
        Group {
            if let file = brand.logoFile, let url = WidgetSnapshot.containerURL?.appending(path: file),
               let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(String(brand.name.prefix(1))).font(.system(size: size * 0.45, weight: .bold, design: .serif)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: brand.colorHex))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().stroke(W.hairline, lineWidth: 0.5))
    }
}

private struct CategoryBar: View {
    let s: WidgetSnapshot
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            let total = max(s.topCategories.reduce(Decimal(0)) { $0 + $1.amount }, 1)
            HStack(spacing: 2) {
                ForEach(s.topCategories, id: \.self) { c in
                    Capsule().fill(LinearGradient(colors: [Color(hex: c.colorHex).opacity(0.8), Color(hex: c.colorHex)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(4, (g.size.width - CGFloat(s.topCategories.count) * 2) * CGFloat((c.amount / total as NSDecimalNumber).doubleValue)))
                }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: s.topCategories.map { ($0.amount as NSDecimalNumber).doubleValue })
    }
}

private struct CategoryRow: View {
    let c: WidgetSnapshot.Category
    let currency: String
    var size: CGFloat = 13
    /// Share of the month (0…1); draws a slim bar under the row when set.
    var share: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Coin(symbol: c.symbol, hex: c.colorHex, size: size + 8)
                Text(c.name).font(.system(size: size, weight: .medium)).foregroundStyle(W.ink).lineLimit(1).minimumScaleFactor(0.8)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(Short.money(c.amount, currency))
                    .font(.system(size: size + 1, weight: .semibold, design: .serif)).foregroundStyle(W.ink).monospacedDigit()
                    .lineLimit(1).fixedSize()
                    .privacySensitive()
            }
            if let share {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "E8E7E3"))
                        Capsule().fill(LinearGradient(colors: [Color(hex: c.colorHex).opacity(0.75), Color(hex: c.colorHex)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, g.size.width * share))
                    }
                }
                .frame(height: 4)
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: share)
            }
        }
    }
}

/// Last 7 days as rounded bars; today in ink. Bars grow when the data changes.
private struct WeekBars: View {
    let values: [Decimal]
    var height: CGFloat = 34
    var body: some View {
        let maxV = max(values.map { ($0 as NSDecimalNumber).doubleValue }.max() ?? 0, 1)
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let todayIndex = Calendar.current.component(.weekday, from: .now) - 1
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let isToday = i == values.count - 1
                VStack(spacing: 3) {
                    Capsule()
                        .fill(isToday ? W.ink : Color(hex: "D6D5D0"))
                        .frame(height: max(3, height * CGFloat((v as NSDecimalNumber).doubleValue / maxV)))
                        .frame(height: height, alignment: .bottom)
                    Text(symbols[(todayIndex - (values.count - 1 - i) + 70) % 7])
                        .font(.system(size: 8, weight: isToday ? .bold : .medium)).foregroundStyle(isToday ? W.ink : W.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: values.map { ($0 as NSDecimalNumber).doubleValue })
        .privacySensitive()
    }
}

// MARK: - Families

struct SpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendEntry

    var body: some View {
        if let s = entry.snapshot, s.hasData {
            switch family {
            case .systemSmall: small(s)
            case .systemMedium: medium(s)
            case .systemLarge: large(s)
            case .accessoryRectangular: rectangular(s)
            case .accessoryInline:
                Text("\(SharedFormat.money(s.monthSpend, s.currency, compact: true)) out in \(s.monthName)").privacySensitive()
            default: small(s)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Caps(text: "where did your money go?", color: W.ink)
                Spacer()
                Text("Open Influenza").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(W.ink)
                Caps(text: "your spending appears here")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps(text: "money out · \(s.monthName.prefix(3))", color: W.ink)
            Spacer(minLength: 4)
            Amount(value: s.monthSpend, currency: s.currency, size: 32)
            Delta(s: s, compact: true).padding(.top, 2)
            Spacer(minLength: 8)
            CategoryBar(s: s, height: 8)
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        let top = Array(s.topCategories.prefix(3))
        let total = max(s.monthSpend, 1)
        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Caps(text: "money out · \(s.monthName.prefix(3))", color: W.ink)
                Spacer(minLength: 4)
                Amount(value: s.monthSpend, currency: s.currency, size: 34)
                Delta(s: s, compact: true).padding(.top, 3)
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.offset) { i, c in
                    if i > 0 { Spacer(minLength: 6) }
                    CategoryRow(c: c, currency: s.currency, size: 12, share: (c.amount / total as NSDecimalNumber).doubleValue)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: "money out in \(s.monthName)", color: W.ink)
                Amount(value: s.monthSpend, currency: s.currency, size: 44)
                Delta(s: s)
            }
            if let spent = s.spentOnThings, let people = s.sentToPeople {
                HStack(spacing: 0) {
                    stat("spent", spent, s.currency)
                    Rectangle().fill(W.hairline).frame(width: 1, height: 22)
                    stat("to people", people, s.currency)
                    Rectangle().fill(W.hairline).frame(width: 1, height: 22)
                    stat("today", s.todaySpend, s.currency)
                }
                .padding(.top, 10)
            }
            VStack(spacing: 12) {
                ForEach(s.topCategories, id: \.self) { c in
                    CategoryRow(c: c, currency: s.currency, size: 13, share: (c.amount / max(s.monthSpend, 1) as NSDecimalNumber).doubleValue)
                }
            }
            .padding(.top, 16)
            Spacer(minLength: 10)
            if !s.topBrands.isEmpty {
                Caps(text: "top brands").padding(.bottom, 8)
                HStack(spacing: 10) {
                    ForEach(s.topBrands, id: \.self) { b in
                        HStack(spacing: 6) {
                            BrandCoin(brand: b, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.name).font(.system(size: 11, weight: .medium)).foregroundStyle(W.ink).lineLimit(1)
                                Text(SharedFormat.money(b.amount, s.currency, compact: true))
                                    .font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(W.ink).privacySensitive()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if s.nextRecurring != nil || s.reviewCount > 0 {
                HStack {
                    if let next = s.nextRecurring { Caps(text: "next · \(next)", size: 9) }
                    Spacer()
                    if s.reviewCount > 0 {
                        Link(destination: URL(string: "influenza://review")!) { Caps(text: "\(s.reviewCount) to review", color: W.negative, size: 9) }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func stat(_ title: String, _ value: Decimal, _ currency: String) -> some View {
        VStack(spacing: 2) {
            Text(SharedFormat.money(value, currency, compact: true)).font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(W.ink).privacySensitive()
            Caps(text: title, size: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MONEY OUT · \(s.monthName.prefix(3).uppercased())").font(.system(size: 10, weight: .semibold)).tracking(1.4)
            Text(SharedFormat.money(s.monthSpend, s.currency, compact: true))
                .font(.system(size: 24, weight: .semibold, design: .serif)).privacySensitive()
            if let top = s.topCategories.first { Text("most on \(top.name.lowercased())").font(.caption2).privacySensitive() }
        }
    }
}

struct InfluenzaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InfluenzaSpend", provider: SpendProvider()) { entry in
            SpendWidgetView(entry: entry)
                .containerBackground(for: .widget) { W.canvas }
                .environment(\.colorScheme, .light)
                .widgetURL(URL(string: "influenza://home"))
        }
        .configurationDisplayName("Where did my money go?")
        .description("Money out this month, top categories and brands.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct InfluenzaWidgetBundle: WidgetBundle {
    var body: some Widget { InfluenzaWidget() }
}
