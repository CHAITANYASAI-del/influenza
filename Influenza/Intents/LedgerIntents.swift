import AppIntents
import Foundation
import LedgerCore

/// Optional power-user actions (spec §64). Never required by onboarding.
struct ImportFinancialMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Financial Message"
    static let description = IntentDescription("Reads a bank, card or UPI alert on your iPhone and adds it to your ledger.")
    static let openAppWhenRun = false

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult {
        LedgerStore.shared.pasteAlert(message)
        return .result()
    }
}

struct LogCardTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Card Tap"
    static let description = IntentDescription("Logs an Apple Pay payment to your ledger.")
    static let openAppWhenRun = false

    @Parameter(title: "Merchant") var merchant: String
    @Parameter(title: "Amount") var amount: String

    @MainActor
    func perform() async throws -> some IntentResult {
        LedgerStore.shared.walletTap(merchant: merchant, amount: amount)
        return .result()
    }
}

struct AddCashIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Cash"
    static let openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "influenza://cash")!))
    }
}

struct InfluenzaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddCashIntent(), phrases: ["Add cash in \(.applicationName)"], shortTitle: "Add Cash", systemImageName: "banknote.fill")
        AppShortcut(intent: ImportFinancialMessageIntent(), phrases: ["Import a bank message in \(.applicationName)"],
                    shortTitle: "Import Message", systemImageName: "text.bubble.fill")
        AppShortcut(intent: LogCardTapIntent(), phrases: ["Log a card tap in \(.applicationName)"], shortTitle: "Log Card Tap", systemImageName: "wave.3.right")
    }
}
