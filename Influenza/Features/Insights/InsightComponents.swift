import Charts
import LedgerCore
import SwiftUI

/// 12-month bar strip: the month picker *and* the history at a glance.
struct MonthStrip: View {
    let points: [MonthlyPoint]
    @Binding var selected: Int          // 0 = this month, -1 = last month…
    let currency: String
    @State private var scrubbed: Date?

    private func offset(of date: Date) -> Int {
        Calendar.current.dateComponents([.month], from: Calendar.current.dateInterval(of: .month, for: .now)!.start,
                                        to: Calendar.current.dateInterval(of: .month, for: date)!.start).month ?? 0
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { withAnimation(.snappy) { selected -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                    .disabled(selected <= -(points.count - 1))
                Spacer()
                Text(monthTitle.uppercased()).font(.system(size: 15, weight: .heavy)).tracking(2).contentTransition(.numericText()).animation(.snappy, value: selected)
                Spacer()
                Button { withAnimation(.snappy) { selected += 1 } } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                    .disabled(selected >= 0)
            }
            .buttonStyle(PopButtonStyle(kind: .dark, fullWidth: false))

            Chart(points) { p in
                let isSelected = offset(of: p.monthStart) == selected
                BarMark(x: .value("Month", p.monthStart, unit: .month), y: .value("Spent", p.spent.double), width: .ratio(0.62))
                    .clipShape(.rect(cornerRadius: 5))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Pop.ink) : AnyShapeStyle(Color(hex: "DCDBD7")))
                    .annotation(position: .top, spacing: 3) {
                        if isSelected && p.spent > 0 {
                            Text(Fmt.money(p.spent, currency, compact: true)).font(.system(size: 10, weight: .bold)).foregroundStyle(Pop.ink)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { v in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .chartXSelection(value: $scrubbed)
            .frame(height: 96)
            .onChange(of: scrubbed) { _, date in
                guard let date else { return }
                withAnimation(.snappy) { selected = min(0, offset(of: date)) }
            }
            .sensoryFeedback(.selection, trigger: selected)
            .accessibilityLabel("Monthly spending for the last \(points.count) months")
        }
    }

    private var monthTitle: String {
        let date = Calendar.current.date(byAdding: .month, value: selected, to: .now) ?? .now
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }
}

/// "vs August so far   ↓ ₹2,340" — a quiet list, whole rupees, colour carries the meaning.
struct ComparisonPills: View {
    let comparisons: [Comparison]
    let currency: String

    var body: some View {
        if !comparisons.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(comparisons.enumerated()), id: \.element.id) { i, c in
                    let less = c.delta < 0, same = c.delta.rounded(0) == 0
                    let tone = same ? Pop.ink2 : (less ? Pop.positive : Pop.negative)
                    HStack {
                        Text(c.label.replacingOccurrences(of: "vs ", with: "vs ")).font(.system(size: 13)).foregroundStyle(Pop.ink2)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: same ? "equal" : (less ? "arrow.down.right" : "arrow.up.right")).font(.system(size: 10, weight: .bold))
                            Text(same ? "same" : "\(Fmt.money(abs(c.delta).rounded(0), currency)) \(less ? "less" : "more")")
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(tone)
                    }
                    .padding(.vertical, 11)
                    if i < comparisons.count - 1 { DashedDivider() }
                }
            }
        }
    }
}

/// Category donut: tap a slice (or row) to see it; tap the row to drill in.
struct CategoryDonut: View {
    let byCategory: [(id: String, amount: Decimal)]
    let total: Decimal
    let currency: String
    var showList = true
    let onOpen: (String) -> Void
    @State private var angle: Double?
    @State private var focused: String?

    var body: some View {
        VStack(spacing: 14) {
            Chart(byCategory, id: \.id) { item in
                SectorMark(angle: .value("Spent", item.amount.double), innerRadius: .ratio(0.64), outerRadius: .ratio(focused == item.id ? 1 : 0.92),
                           angularInset: 1.5)
                    .cornerRadius(5)
                    .foregroundStyle(CategoryStyle.tint(item.id).gradient)
                    .opacity(focused == nil || focused == item.id ? 1 : 0.35)
            }
            .chartAngleSelection(value: $angle)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    if let focused, let item = byCategory.first(where: { $0.id == focused }) {
                        Image(systemName: CategoryStyle.symbol(focused)).foregroundStyle(CategoryStyle.tint(focused))
                        Text(CategoryTree.node(focused)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                        MoneyText(amount: item.amount, currency: currency, size: 22)
                        Text(percent(item.amount)).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Spent").font(.caption).foregroundStyle(.secondary)
                        MoneyText(amount: total, currency: currency, size: 22)
                    }
                }
                .animation(.snappy, value: focused)
            }
            .frame(height: 200)
            .onChange(of: angle) { _, value in
                guard let value else { return }
                var running = 0.0
                for item in byCategory {
                    running += item.amount.double
                    if value <= running { withAnimation(.snappy) { focused = focused == item.id ? nil : item.id }; break }
                }
            }
            .sensoryFeedback(.selection, trigger: focused)

            if showList { VStack(spacing: 0) {
                ForEach(byCategory, id: \.id) { item in
                    Button { onOpen(item.id) } label: {
                        HStack(spacing: 12) {
                            CategoryBadge(categoryID: item.id, size: 32)
                            Text(CategoryTree.node(item.id)?.name ?? "Other").font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text(percent(item.amount)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.money(item.amount, currency)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { withAnimation(.snappy) { focused = item.id } })
                }
            } }
        }
    }

    private func percent(_ amount: Decimal) -> String {
        guard total > 0 else { return "" }
        return (amount.double / total.double).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Horizontal brand list: "where it went".
struct BrandCarousel: View {
    let brands: [BrandSpend]
    let currency: String
    let onOpen: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(brands.prefix(12)) { b in
                    Button { onOpen(b.name) } label: {
                        VStack(spacing: 6) {
                            BrandLogo(name: b.name, size: 48)
                            Text(b.name).font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                            Text(Fmt.money(b.amount, currency, compact: true)).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .frame(width: 78)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .popSurface(elevated: true)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// Six-month bars for a category or brand.
struct TrendChart: View {
    let points: [MonthlyPoint]
    let currency: String
    let tint: Color

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Month", p.monthStart, unit: .month), y: .value("Spent", p.spent.double), width: .ratio(0.55))
                .clipShape(.rect(cornerRadius: 4))
                .foregroundStyle(Calendar.current.isDate(p.monthStart, equalTo: points.last?.monthStart ?? .now, toGranularity: .month)
                                 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.35)))
                .annotation(position: .top) {
                    if p.spent > 0 { Text(Fmt.money(p.spent, currency, compact: true)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
                }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true) } }
        .chartYAxis(.hidden)
        .frame(height: 120)
    }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { PopLabel(text: title, color: Pop.ink) }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pop.sheet, in: .rect(cornerRadius: 22))
    }
}
