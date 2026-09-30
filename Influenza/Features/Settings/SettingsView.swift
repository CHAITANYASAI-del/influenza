import LedgerCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LedgerStore.self) private var store
    @AppStorage("defaultCurrency") private var defaultCurrency = Locale.current.currency?.identifier ?? "USD"
    @AppStorage("widgetPrivacyMode") private var widgetPrivacy = true
    @State private var confirmDelete = false
    @State private var exportDoc: ExportDocument?

    var body: some View {
        @Bindable var lock = model.lock
        NavigationStack {
            Form {
                Section {
                    NavigationLink { PrivacyCenterView() } label: { Label("Privacy Center", systemImage: "hand.raised.fill") }
                    HStack {
                        Label("Require \(model.lock.biometryName)", systemImage: "faceid")
                        Spacer()
                        NeoSwitch(isOn: $lock.isEnabled).frame(width: 56, height: 28)
                    }
                }

                Section("Preferences") {
                    Picker("Default currency", selection: $defaultCurrency) {
                        ForEach(["INR", "USD", "EUR", "GBP", "AED", "SGD", "AUD", "CAD", "JPY", "CHF", "SAR", "MYR", "IDR", "PHP", "THB", "BRL", "MXN", "ZAR", "NGN", "KES", "PKR", "BDT", "LKR", "NPR"], id: \.self) { Text($0) }
                    }
                }

                GmailSettingsSection()

                Section {
                    NavigationLink { SourcesStatusView() } label: { Label("Data sources", systemImage: "tray.2.fill") }
                    NavigationLink { AutomationHelpView() } label: { Label("Automation (optional)", systemImage: "bolt.badge.automatic") }
                } header: { Text("Sources") }

                Section {
                    Button("Export CSV", systemImage: "tablecells") { exportDoc = ExportDocument(data: store.exportCSV(), type: .commaSeparatedText, name: "influenza-ledger.csv") }
                    Button("Export JSON", systemImage: "curlybraces") {
                        if let data = try? store.exportJSON() { exportDoc = ExportDocument(data: data, type: .json, name: "influenza-ledger.json") }
                    }
                    Button("Delete all data", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } header: { Text("Your data") } footer: {
                    Text("\(store.transactions.count) transactions, stored encrypted on this iPhone only.")
                }

                #if DEBUG
                Section("Developer") { NavigationLink("Developer tools") { DeveloperToolsView() } }
                #endif
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete every transaction, statement, message and receipt?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) { store.deleteAll() }
            } message: { Text("Settings are kept. This can't be undone.") }
            .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                          document: exportDoc, contentType: exportDoc?.type ?? .data, defaultFilename: exportDoc?.name) { _ in }
        }
    }
}

struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .json]
    let data: Data
    let type: UTType
    let name: String
    init(data: Data, type: UTType, name: String) { self.data = data; self.type = type; self.name = name }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data(); type = .data; name = "export" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Spec §86 — every statement technically accurate for this build.
struct PrivacyCenterView: View {
    var body: some View {
        List {
            row("Financial data", "Stored on this iPhone", "iphone")
            row("Statements", "Processed on this iPhone", "doc.text")
            row("Gmail", "Read-only, read on this iPhone", "envelope")
            row("Emails kept", "Only the payment sentence", "text.quote")
            row("Pasted messages & receipts", "Processed on this iPhone", "text.bubble")
            row("AI", "Not used", "cpu")
            row("Advertising profile", "Not created", "megaphone")
            row("Analytics & crash SDKs", "None included", "chart.bar.xaxis")
            row("Cloud copy of financial data", "None", "icloud.slash")
            row("Bank passwords", "Never asked for", "key.slash")
            row("Widget", "Totals only, hidden on Lock Screen", "square.grid.2x2")
            Section {
                Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: "onlineLogosEnabled") as? Bool ?? true },
                                     set: { UserDefaults.standard.set($0, forKey: "onlineLogosEnabled") })) {
                    Label("Find logos for other brands", systemImage: "photo.circle")
                }
            } footer: {
                Text("88 popular brand logos are built into the app. For other brands, Influenza looks up the brand's official App Store icon by shop name only — never amounts, dates or anything about you. Names of people are never looked up. Turn off to use category icons instead.")
            }
        }
        .navigationTitle("Privacy Center")
    }
    private func row(_ title: String, _ value: String, _ symbol: String) -> some View {
        LabeledContent { Text(value).foregroundStyle(.secondary) } label: { Label(title, systemImage: symbol) }
    }
}

/// Spec §109 — show capability truthfully.
struct SourcesStatusView: View {
    var body: some View {
        List {
            status("Gmail alerts (automatic)", "Bank, card, UPI and merchant emails", true)
            status("Statement import", "CSV · OFX · QFX · PDF", true)
            status("Paste transaction alert", "Any bank, any country", true)
            status("Receipts", "Paste, photo or camera", true)
            status("Cash", "Manual", true)
            status("Home & Lock Screen widget", "Small · Medium · Large · Lock Screen", true)
            Section("Needs a paid Apple developer account") {
                status("Share from Messages", "Share Extension — coming with the paid account", false)
                status("Apple financial data (FinanceKit)", "Needs Apple approval · US/UK only", false)
            }
            Section("Future connections") {
                status("India Account Aggregator", "Coming through a supported connection", false)
            }
        }
        .navigationTitle("Data sources")
    }
    private func status(_ title: String, _ detail: String, _ available: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text(available ? "Available" : "Not yet").font(.caption.weight(.semibold)).foregroundStyle(available ? .green : .secondary)
        }
    }
}

/// Spec §64 — optional power-user path, never required.
struct AutomationHelpView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section {
                Text("Optional. If you want bank alerts logged the moment they arrive, you can create a Shortcuts automation. Everything works without this.")
                    .font(.subheadline)
            }
            Section("Log bank SMS automatically") {
                step(1, "Shortcuts → Automation → + → Message")
                step(2, "Message Contains: debited (add others like spent, paid)")
                step(3, "Run Immediately → Next → New Blank Automation")
                step(4, "Add “Import Financial Message” (Influenza) → Message = Shortcut Input")
            }
            Section("Log Apple Pay taps") {
                step(1, "Shortcuts → Automation → + → Wallet → your cards")
                step(2, "Run Immediately → add “Log Card Tap” (Influenza)")
                step(3, "Merchant and Amount = Shortcut Input")
            }
            Button("Open Shortcuts", systemImage: "arrow.up.forward.app") { openURL(URL(string: "shortcuts://")!) }
        }
        .navigationTitle("Automation")
    }
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top) { Text("\(n).").bold().frame(width: 20); Text(text) }.font(.subheadline)
    }
}

struct GmailSettingsSection: View {
    @Environment(GmailSource.self) private var gmail
    @State private var confirmDisconnect = false

    var body: some View {
        Section {
            if gmail.isConnected {
                LabeledContent("Gmail", value: gmail.email ?? "Connected")
                if let last = gmail.lastSync { LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named))) }
                Button("Check now", systemImage: "arrow.clockwise") { Task { await gmail.sync() } }
                NavigationLink { RecentEmailsView() } label: { Label("Recent emails", systemImage: "tray.full") }
                Button("Re-read all emails", systemImage: "arrow.triangle.2.circlepath") { Task { await gmail.rereadAll() } }
                Button("Disconnect Gmail", role: .destructive) { confirmDisconnect = true }
            } else {
                Button("Connect Gmail", systemImage: "envelope.fill") { Task { await gmail.connect() } }
            }
        } header: { Text("Automatic tracking") } footer: {
            Text("Influenza asks Google for read-only access and reads only transaction emails, on this iPhone. Transactions already found stay if you disconnect.")
        }
        .confirmationDialog("Stop reading Gmail?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await gmail.disconnect() } }
        }
    }
}

/// Transparency: what Influenza did with every money-related email it checked.
struct RecentEmailsView: View {
    @Environment(GmailSource.self) private var gmail
    @State private var added: Set<String> = []

    var body: some View {
        List {
            Section {
                ForEach(gmail.recentChecks) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(c.outcome)).foregroundStyle(color(c.outcome)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.subject.isEmpty ? "(no subject)" : c.subject).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text("\(c.sender.isEmpty ? "" : c.sender + " · ")\(c.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(c.detail).font(.caption).foregroundStyle(color(c.outcome))
                            }
                        }
                        if c.outcome == .skipped, c.excerpt != nil, !added.contains(c.id) {
                            Button("This was a payment — add it") {
                                if gmail.addAnyway(c) { added.insert(c.id) }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.leading, 28)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("The last 60 money-related emails Influenza checked, newest first. Everything here stays on this iPhone.")
            }
        }
        .overlay { if gmail.recentChecks.isEmpty { ContentUnavailableView("Nothing checked yet", systemImage: "tray") } }
        .navigationTitle("Recent emails")
        .refreshable { await gmail.sync(userInitiated: true) }
    }

    private func symbol(_ o: EmailCheck.Outcome) -> String {
        switch o { case .added: "plus.circle.fill"; case .matched: "link.circle.fill"; case .duplicate: "equal.circle"; case .skipped: "minus.circle"; case .unreadable: "exclamationmark.triangle" }
    }
    private func color(_ o: EmailCheck.Outcome) -> Color {
        switch o { case .added: Pop.positive; case .matched: .blue; case .duplicate: .secondary; case .skipped: .secondary; case .unreadable: Pop.negative }
    }
}
