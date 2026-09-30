import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LedgerStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingView { withAnimation(.smooth) { onboardingComplete = true } }
            }
            if model.lock.isLocked && onboardingComplete {
                LockView().transition(.opacity)
            }
        }
        .animation(.smooth, value: model.lock.isLocked)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .bringMoneyIn: BringMoneyInSheet().presentationDetents([.medium, .large])
            case .importStatement: ImportStatementSheet()
            case .pasteAlert: PasteAlertSheet().presentationDetents([.medium, .large])
            case .receipt: ReceiptSheet()
            case .cash: CashSheet().presentationDetents([.medium, .large])
            }
        }
        .onOpenURL { model.handle(url: $0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                model.lock.lockIfNeeded()
                GmailSource.shared.stopForegroundPolling()
                GmailSource.shared.scheduleBackgroundRefresh()
            case .active:
                store.refreshOnActivate()
                GmailSource.shared.syncIfStale()
                GmailSource.shared.startForegroundPolling(every: 15)
            default: break
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(LedgerStore.self) private var store

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) { HomeView() }
            Tab("Transactions", systemImage: "list.bullet", value: 1) { TransactionsView() }
            Tab("Review", systemImage: "checkmark.circle", value: 2) { ReviewView() }
                .badge(store.reviewCount)
            Tab("Settings", systemImage: "gearshape.fill", value: 3) { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
