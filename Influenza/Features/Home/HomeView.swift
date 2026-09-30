import LedgerCore
import SwiftUI

enum InsightRoute: Hashable {
    case category(String, month: Int)
    case brand(String, month: Int)
    case person(String, month: Int)
    case recurring
}

/// CRED-style home: the month's number up top, icon tabs, a white sheet below.
struct HomeView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(GmailSource.self) private var gmail
    @State private var currency = Fmt.defaultCurrency
    @State private var month = 0
    @State private var tab: HomeTab = .categories
    @State private var path: [InsightRoute] = []

    enum HomeTab: String, CaseIterable, Identifiable {
        case categories, brands, people, trend
        var id: String { rawValue }
        var symbol: String {
            switch self { case .categories: "square.grid.2x2"; case .brands: "bag"; case .people: "person.2"; case .trend: "chart.bar" }
        }
    }

    private var summary: PeriodSummary {
        let m = store.monthInterval(month)
        return store.summary(from: m.start, to: m.end, currency: currency)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if store.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        hero
                        tabs
                        sheet
                    }
                }
            }
            .refreshable { await gmail.sync(userInitiated: true) }
            .background(Pop.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { SyncToast() }
            .navigationDestination(for: InsightRoute.self) { route in
                switch route {
                case let .category(id, m): CategoryInsightView(topLevelID: id, month: m, currency: currency)
                case let .brand(name, m): BrandInsightView(name: name, month: m, currency: currency)
                case let .person(name, m): PersonInsightView(name: name, month: m, currency: currency)
                case .recurring: RecurringView()
                }
            }
            .onAppear { if let first = store.currencies.first, !store.currencies.contains(currency) { currency = first } }
        }
    }

    // MARK: Hero

    private var monthName: String {
        let d = store.monthInterval(month).start
        return d.formatted(Calendar.current.isDate(d, equalTo: .now, toGranularity: .year) ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    private var hero: some View {
        let s = summary
        let comps = store.comparisons(selected: month, currency: currency)
        return VStack(spacing: 14) {
            HStack {
                Button { withAnimation(.snappy) { month -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                Spacer()
                PopLabel(text: "money out in \(monthName)\(month == 0 ? " so far" : "")", color: Pop.ink)
                Spacer()
                Button { withAnimation(.snappy) { month += 1 } } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .disabled(month >= 0).opacity(month >= 0 ? 0.25 : 1)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Pop.ink)

            MoneyText(amount: s.moneyOut, currency: currency, size: 46)
                .foregroundStyle(Pop.ink)
                .contentTransition(.numericText(value: s.moneyOut.double))
                .animation(.snappy, value: s.moneyOut)
                .accessibilityLabel("Money out \(Fmt.spoken(s.moneyOut, currency))")

            if let first = comps.first, first.delta.rounded(0) != 0 {
                let less = first.delta < 0
                HStack(spacing: 5) {
                    Image(systemName: less ? "arrow.down.right" : "arrow.up.right").font(.system(size: 10, weight: .bold))
                    Text("\(Fmt.money(abs(first.delta).rounded(0), currency)) \(less ? "less" : "more") than last month".uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(1.2)
                }
                .foregroundStyle(less ? Pop.positive : Pop.negative)
            }
            syncLine
            HStack(spacing: 0) {
                stat("spent", s.spent)
                statDivider
                stat("to people", s.sentToPeople)
                statDivider
                stat("received", s.received)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 18)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -60, month < 0 { withAnimation(.snappy) { month += 1 } }
            if v.translation.width > 60 { withAnimation(.snappy) { month -= 1 } }
        })
        .sensoryFeedback(.selection, trigger: month)
    }

    private var cardBills: Decimal {
        let m = store.monthInterval(month)
        return store.transactions.filter { $0.isCreditCardPayment && $0.direction == .debit && $0.currencyCode == currency && m.contains($0.transactionDate) }
            .reduce(0) { $0 + $1.amount }
    }

    @ViewBuilder private var syncLine: some View {
        switch gmail.status {
        case .syncing:
            EmptyView()
        case .needsReconnect:
            PopLink(title: "reconnect gmail", symbol: "arrow.clockwise") { Task { await gmail.connect() } }
        case .notConnected:
            PopLink(title: "turn on automatic tracking", symbol: "bolt") { Task { await gmail.connect() } }
        default:
            EmptyView()
        }
    }

    private func stat(_ title: String, _ value: Decimal) -> some View {
        VStack(spacing: 4) {
            MoneyText(amount: value, currency: currency, size: 15).foregroundStyle(Pop.ink)
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Pop.ink2)
        }
        .frame(maxWidth: .infinity)
    }
    private var statDivider: some View { Rectangle().fill(Pop.hairline).frame(width: 1, height: 28) }

    // MARK: Tabs (thin icons + small caps + underline)

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases) { t in
                Button { withAnimation(.snappy) { tab = t } } label: {
                    VStack(spacing: 8) {
                        Image(systemName: t.symbol).font(.system(size: 22, weight: .light))
                        Text(t.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6)
                        Rectangle().fill(tab == t ? Pop.ink : .clear).frame(width: 22, height: 2)
                    }
                    .foregroundStyle(tab == t ? Pop.ink : Pop.ink2.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 10)
        .sensoryFeedback(.selection, trigger: tab)
    }

    // MARK: White sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch tab {
            case .categories: categoriesList
            case .brands: brandsList
            case .people: peopleList
            case .trend: trendPanel
            }
            highlights
            quickActions
            Color.clear.frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pop.sheet, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .animation(.smooth, value: tab)
        .animation(.smooth, value: month)
    }

    private func row<Leading: View>(_ leading: Leading, title: String, subtitle: String, amount: Decimal, tint: Color = Pop.ink,
                                    last: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    leading
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Pop.ink).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Pop.ink2)
                        }
                        Text(subtitle.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Pop.ink2)
                    }
                    Spacer()
                    MoneyText(amount: amount, currency: currency, size: 17).foregroundStyle(tint)
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if !last { DashedDivider() }
        }
        .padding(.horizontal, 22)
    }

    private var categoriesList: some View {
        let s = summary
        let cats = s.byCategory.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        return VStack(spacing: 0) {
            if !cats.isEmpty {
                CategoryDonut(byCategory: cats.map { (id: $0.key, amount: $0.value) }, total: s.moneyOut, currency: currency, showList: false) { _ in }
                    .padding(.horizontal, 22).padding(.top, 22)
            }
            ForEach(Array(cats.enumerated()), id: \.element.key) { i, c in
                let count = store.transactions(monthOffset: month, currency: currency) {
                    CategoryTree.node($0.categoryID)?.topLevelID == c.key && (AggregationService.isSpending($0) || AggregationService.isSentToPerson($0))
                }.count
                row(CategoryIcon3D(categoryID: c.key, size: 44), title: CategoryTree.node(c.key)?.name ?? "Other",
                    subtitle: "\(percent(c.value, of: s.moneyOut)) · \(count) paid", amount: c.value,
                    last: i == cats.count - 1) { path.append(.category(c.key, month: month)) }
            }
            if cats.isEmpty { emptyTab("No spending in \(monthName).") }
        }
        .padding(.top, 8)
    }

    private var brandsList: some View {
        let brands = store.brands(monthOffset: month, currency: currency)
        return VStack(spacing: 0) {
            ForEach(Array(brands.prefix(30).enumerated()), id: \.element.id) { i, b in
                row(BrandLogo(name: b.name, categoryID: b.categoryID, size: 44), title: b.name,
                    subtitle: "\(b.count) paid",
                    amount: b.amount, last: i == min(brands.count, 30) - 1) { path.append(.brand(b.name, month: month)) }
            }
            if brands.isEmpty { emptyTab("No brand payments in \(monthName).") }
        }
        .padding(.top, 8)
    }

    private var peopleList: some View {
        let people = store.people(monthOffset: month, currency: currency)
        return VStack(spacing: 0) {
            ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                row(PersonAvatar(name: p.name, size: 44), title: p.name,
                    subtitle: p.received > 0 && p.sent > 0 ? "sent \(Fmt.money(p.sent, currency)) · got \(Fmt.money(p.received, currency))"
                        : (p.sent > 0 ? "sent · \(p.count) time\(p.count == 1 ? "" : "s")" : "received · \(p.count) time\(p.count == 1 ? "" : "s")"),
                    amount: p.sent > 0 ? -p.sent : p.received, tint: p.sent > 0 ? Pop.ink : Pop.positive,
                    last: i == people.count - 1) { path.append(.person(p.name, month: month)) }
            }
            if people.isEmpty { emptyTab("No money sent to or from people in \(monthName).") }
        }
        .padding(.top, 8)
    }

    private var trendPanel: some View {
        let comps = store.comparisons(selected: month, currency: currency)
        let usual = (comps.first { $0.id == "m6" } ?? comps.first { $0.id == "m3" } ?? comps.first { $0.id == "m1" })?.baseline
        return VStack(alignment: .leading, spacing: 22) {
            MonthStrip(points: store.series(currency: currency, months: 12), selected: $month, currency: currency)
            SpendMeter(spent: summary.spent, usual: usual, currency: currency,
                       caption: usual == nil ? "Your usual appears after a couple of months" : "compared with your usual")
                .frame(maxWidth: .infinity)
            ComparisonPills(comparisons: comps, currency: currency)
        }
        .padding(22)
    }

    private func emptyTab(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Pop.ink2).frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func percent(_ v: Decimal, of total: Decimal) -> String {
        total > 0 ? (v.double / total.double).formatted(.percent.precision(.fractionLength(0))) : ""
    }

    // MARK: Highlights & quick actions

    @ViewBuilder private var highlights: some View {
        let items = highlightItems
        if !items.isEmpty {
            Rectangle().fill(Pop.hairline).frame(height: 1).padding(.top, 10)
            VStack(alignment: .leading, spacing: 16) {
                PopLabel(text: "highlights", color: Pop.ink)
                ForEach(items, id: \.self) { Text($0).font(.system(size: 15)).foregroundStyle(Pop.ink) }
            }
            .padding(22)
        }
    }

    private var highlightItems: [String] {
        var out: [String] = []
        let cats = summary.byCategory.filter { $0.value > 0 }
        let changes = cats.map { ($0.key, $0.value - store.spent(monthOffset: month - 1, selected: month, currency: currency, topLevel: $0.key)) }
        if let (id, d) = changes.max(by: { abs($0.1) < abs($1.1) }), d != 0, store.spent(monthOffset: month - 1, selected: month, currency: currency) > 0 {
            out.append("\(Fmt.money(abs(d).rounded(0), currency)) \(d > 0 ? "more" : "less") on \((CategoryTree.node(id)?.name ?? "other").lowercased()) than last month.")
        }
        if let top = store.brands(monthOffset: month, currency: currency).first {
            out.append("Top brand: \(top.name) · \(Fmt.money(top.amount.rounded(0), currency)).")
        }
        let rec = store.recurring.filter { $0.currencyCode == currency }
        if month == 0, let next = rec.first {
            out.append("\(next.merchantName) repeats \(next.cadence.rawValue) · next around \(next.nextExpectedDate.formatted(.dateTime.day().month(.abbreviated))).")
        }
        return Array(out.prefix(2))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(Pop.hairline).frame(height: 1).padding(.horizontal, -22)
            PopLabel(text: "quick actions", color: Pop.ink).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NeoButton(title: "add cash", symbol: "banknote") { model.sheet = .cash }.frame(width: 124, height: 42)
                    NeoButton(title: "import statement", symbol: "doc.text") { model.sheet = .importStatement }.frame(width: 172, height: 42)
                    NeoButton(title: "paste alert", symbol: "text.bubble") { model.sheet = .pasteAlert }.frame(width: 132, height: 42)
                    if store.reviewCount > 0 {
                        NeoButton(title: "review \(store.reviewCount)", symbol: "checkmark.circle") { model.selectedTab = 2 }.frame(width: 120, height: 42)
                    }
                }
                .padding(.vertical, 6).padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 22).padding(.top, 4)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 120)
            PopLabel(text: "where did your money go?", color: Pop.ink)
            Text("Nothing here yet").font(Pop.heading(30)).foregroundStyle(Pop.ink)
            Text(gmail.isConnected ? "Pull down to check your email again, or add cash." : "Connect Gmail and Influenza finds your transactions automatically.")
                .font(.subheadline).foregroundStyle(Pop.ink2).multilineTextAlignment(.center)
            if !gmail.isConnected { PrimaryButton(title: "Continue with Google") { Task { await gmail.connect() } }.padding(.top, 8) }
            Button { model.sheet = .cash } label: { Label("add cash", systemImage: "banknote") }
                .buttonStyle(PopButtonStyle(kind: .secondary, fullWidth: false))
        }
        .padding(28)
    }
}

/// Initials avatar for people.
struct PersonAvatar: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        let words = name.split(separator: " ").filter { !["mr", "mrs", "ms"].contains($0.lowercased()) }
        CoinFrame(size: size) {
            Text(String(words.prefix(2).compactMap(\.first)).uppercased())
                .font(.system(size: size * 0.36, weight: .semibold, design: .serif))
                .foregroundStyle(Pop.ink)
                .frame(width: size, height: size)
                .background(Color(hex: BrandCatalog.info(for: name).colorHex).opacity(0.14))
                .background(Pop.sheet)
        }
    }
}

struct PersonInsightView: View {
    @Environment(LedgerStore.self) private var store
    let name: String
    @State var month: Int
    let currency: String

    var body: some View {
        let m = store.monthInterval(month)
        let txs = store.transactions(monthOffset: month, currency: currency) { ($0.merchantName ?? $0.merchantRaw) == name && $0.flowType == .transfer }
        let all = store.transactions.filter { ($0.merchantName ?? $0.merchantRaw) == name && $0.flowType == .transfer && $0.currencyCode == currency }
        let sent = txs.filter { $0.direction == .debit }.reduce(Decimal(0)) { $0 + $1.amount }
        let got = txs.filter { $0.direction == .credit }.reduce(Decimal(0)) { $0 + $1.amount }
        ScrollView {
            VStack(spacing: 18) {
                PersonAvatar(name: name, size: 72)
                Text(name).font(Pop.heading(24)).foregroundStyle(Pop.ink)
                HStack {
                    Button { withAnimation { month -= 1 } } label: { Image(systemName: "chevron.left") }
                    PopLabel(text: m.start.formatted(.dateTime.month(.wide).year()), color: Pop.ink).frame(maxWidth: .infinity)
                    Button { withAnimation { month += 1 } } label: { Image(systemName: "chevron.right") }.disabled(month >= 0)
                }
                .foregroundStyle(Pop.ink).padding(.horizontal, 20)
                HStack(spacing: 0) {
                    VStack(spacing: 4) { MoneyText(amount: sent, currency: currency, size: 26); PopLabel(text: "you sent") }.frame(maxWidth: .infinity)
                    Rectangle().fill(Pop.hairline).frame(width: 1, height: 36)
                    VStack(spacing: 4) { MoneyText(amount: got, currency: currency, size: 26).foregroundStyle(Pop.positive); PopLabel(text: "you got") }.frame(maxWidth: .infinity)
                }
                if let latest = all.first(where: { $0.direction == .debit }) {
                    HStack(spacing: 10) {
                        ForEach([("people.family", "family"), ("people.friends", "friends"), ("people.other", "other")], id: \.0) { id, title in
                            Button { store.setCategory(latest.id, id, always: true) } label: {
                                Label(title, systemImage: latest.categoryID == id ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(PopButtonStyle(kind: .secondary, fullWidth: false))
                        }
                    }
                }
                PopLabel(text: "all time · sent \(Fmt.money(all.filter { $0.direction == .debit }.reduce(0) { $0 + $1.amount }, currency)) · got \(Fmt.money(all.filter { $0.direction == .credit }.reduce(0) { $0 + $1.amount }, currency))")
                VStack(spacing: 0) {
                    ForEach(Array(txs.enumerated()), id: \.element.id) { i, tx in
                        NavigationLink { TransactionDetailView(id: tx.id) } label: { TransactionRow(tx: tx) }.buttonStyle(.plain)
                        if i < txs.count - 1 { DashedDivider() }
                    }
                    if txs.isEmpty { Text("Nothing this month.").foregroundStyle(Pop.ink2).padding(.vertical, 30) }
                }
                .padding(20)
                .background(Pop.sheet, in: .rect(cornerRadius: 22))
            }
            .padding(16)
        }
        .background(Pop.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Small pill at the top: "Syncing…" → "Updated just now · 3 new". Quiet background
/// checks only show it when they actually find something.
struct SyncToast: View {
    @Environment(GmailSource.self) private var gmail
    @State private var visible = false
    @State private var text = ""
    @State private var working = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if visible {
                HStack(spacing: 8) {
                    if working { ProgressView().controlSize(.mini).tint(.white) }
                    else { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)) }
                    Text(text).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Pop.ink, in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: visible)
        .onChange(of: gmail.toastEvent) { _, event in
            guard let event else { return }
            hideTask?.cancel()
            switch event {
            case .started:
                working = true; text = "Syncing…"; visible = true
            case let .finished(added):
                working = false
                text = added > 0 ? "Updated just now · \(added) new" : "Updated just now"
                visible = true
                hideTask = Task { try? await Task.sleep(for: .seconds(2.2)); if !Task.isCancelled { visible = false } }
            }
        }
        .sensoryFeedback(.success, trigger: text) { _, new in new.hasPrefix("Updated") }
    }
}
