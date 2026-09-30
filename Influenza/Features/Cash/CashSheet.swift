import LedgerCore
import SwiftUI

/// Spec §18: + Cash → amount → category → optional merchant → Done.
struct CashSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var category = "food.other"
    @State private var currency = Fmt.defaultCurrency
    @State private var date = Date.now
    @State private var recorder = VoiceRecorder()
    @State private var saved = 0
    @FocusState private var amountFocused: Bool

    private let quick: [(String, String)] = [
        ("food.other", "Food"), ("food.coffee", "Coffee"), ("food.groceries", "Groceries"), ("transport.rideHailing", "Auto/Taxi"),
        ("shopping.general", "Shopping"), ("health.pharmacy", "Medicine"), ("bills.rent", "Rent"), ("other.unknown", "Other"),
    ]
    private var amount: Decimal? { AmountParser.number(amountText).map { abs($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(symbol).font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 54, weight: .bold, design: .rounded)).keyboardType(.decimalPad).focused($amountFocused)
                        Button {
                            Task { recorder.isRecording ? recorder.stop() : await recorder.start() }
                        } label: {
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .frame(width: 44, height: 44)
                                .foregroundStyle(recorder.isRecording ? .white : .primary)
                        }
                        .popSurface(tint: Pop.pink)
                        .accessibilityLabel("Say the amount")
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .popSurface()

                    if recorder.isRecording || recorder.errorMessage != nil {
                        Text(recorder.errorMessage ?? (recorder.transcript.isEmpty ? "Listening… try “fifty rupees chai”" : recorder.transcript))
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(quick, id: \.0) { id, title in
                            Button { category = id } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: CategoryStyle.symbol(id))
                                    Text(title).font(.caption)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(category == id ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .popSurface(elevated: true)
                        }
                    }
                    .sensoryFeedback(.selection, trigger: category)

                    TextField("Where? (optional)", text: $merchant)
                        .padding(14).popSurface(elevated: true)
                    DatePicker("When", selection: $date, in: ...Date.now)
                        .padding(.horizontal, 16).padding(.vertical, 6).popSurface()
                }
                .padding(20)
            }
            .navigationTitle("Add cash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save).buttonStyle(PopButtonStyle(kind: .primary, fullWidth: false)).disabled((amount ?? 0) <= 0)
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .onAppear { amountFocused = true }
            .onChange(of: recorder.isRecording) { _, isRecording in
                guard !isRecording, let entry = LocalQuickEntryParser().parse(recorder.transcript, defaultCurrency: currency) else { return }
                amountText = "\(entry.amount)"
                currency = entry.currencyCode
                if entry.merchant != "Cash" { merchant = entry.merchant }
            }
            .onDisappear { recorder.stop() }
        }
    }

    private var symbol: String {
        Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: currency])).currencySymbol ?? currency
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        store.addCash(amount: amount, currency: currency, merchant: name.isEmpty ? "Cash" : name, categoryID: category, date: date)
        saved += 1
        dismiss()
    }
}

/// Offline parser for spoken cash: "fifty rupees chai", "$12 coffee".
struct LocalQuickEntryParser {
    struct Entry { var merchant: String; var amount: Decimal; var currencyCode: String }
    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = ["hundred": 100, "thousand": 1_000, "lakh": 100_000]
    private static let currencies: [String: String] = [
        "rupee": "INR", "rupees": "INR", "rs": "INR", "₹": "INR", "dollar": "USD", "dollars": "USD", "bucks": "USD", "$": "USD",
        "euro": "EUR", "euros": "EUR", "€": "EUR", "pound": "GBP", "pounds": "GBP", "£": "GBP", "dirham": "AED", "dirhams": "AED",
    ]

    func parse(_ text: String, defaultCurrency: String) -> Entry? {
        var s = text.lowercased()
        for sym in ["₹", "$", "€", "£"] { s = s.replacingOccurrences(of: sym, with: " \(sym) ") }
        var currency: String?, digits: Decimal?, total = 0, current = 0, sawWord = false
        var rest: [String] = []
        for t in s.replacingOccurrences(of: ",", with: "").split(whereSeparator: \.isWhitespace).map(String.init) {
            if let c = Self.currencies[t] { currency = c; continue }
            if digits == nil, let v = Decimal(string: t), v > 0 { digits = v; continue }
            if let u = Self.units[t] { current += u; sawWord = true; continue }
            if let sc = Self.scales[t], sawWord { if sc == 100 { current = max(current, 1) * 100 } else { total += max(current, 1) * sc; current = 0 }; continue }
            if ["and", "for", "on", "at", "a", "of"].contains(t) { continue }
            rest.append(t)
        }
        guard let amount = digits ?? (sawWord && total + current > 0 ? Decimal(total + current) : nil) else { return nil }
        let m = rest.joined(separator: " ").capitalized
        return Entry(merchant: m.isEmpty ? "Cash" : m, amount: amount, currencyCode: currency ?? defaultCurrency)
    }
}
