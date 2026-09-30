import SwiftUI

@main
struct InfluenzaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(LedgerStore.shared)
                .environment(GmailSource.shared)
                .preferredColorScheme(.light)
                .tint(Pop.ink)
        }
        // iOS wakes the app a few times a day to pull new alert emails.
        .backgroundTask(.appRefresh(GmailSource.refreshTaskID)) {
            await GmailSource.shared.sync()
            await GmailSource.shared.scheduleBackgroundRefresh()
        }
    }
}

enum AppSheet: String, Identifiable {
    case bringMoneyIn, importStatement, pasteAlert, receipt, cash
    var id: String { rawValue }
}

@MainActor
@Observable
final class AppModel {
    let lock = AppLock()
    var sheet: AppSheet?
    var selectedTab = 0

    func handle(url: URL) {
        guard url.scheme == "influenza" else { return }
        switch url.host() {
        case "cash": sheet = .cash
        case "paste": sheet = .pasteAlert
        case "review": selectedTab = 2
        default: break
        }
    }
}
