import SwiftUI

/// Two screens. The only thing asked of the user: one Google sign-in.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            AmbientBackground()
            if step == 0 {
                WelcomeStep { withAnimation(.smooth(duration: 0.4)) { step = 1 } }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                ConnectStep(onFinish: onFinish).transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

private struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.pie.fill").font(.system(size: 64)).foregroundStyle(.tint)
                .frame(width: 128, height: 128).popSurface(elevated: true, tint: Pop.paccha)
            VStack(spacing: 12) {
                Text("Your money,\nfinally in one place.").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("UPI, cards and bank transfers are tracked automatically. You only add cash.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            PrimaryButton(title: "Get started", action: next)
        }
        .padding(24)
    }
}

private struct ConnectStep: View {
    let onFinish: () -> Void
    @Environment(GmailSource.self) private var gmail
    @Environment(LedgerStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Track everything\nautomatically").font(.largeTitle.bold())
            Text("Your bank already emails you for every payment. Connect that Gmail and Influenza keeps your ledger up to date on its own.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                promise("envelope.open", "Reads only transaction emails — read-only")
                promise("iphone", "Read on this iPhone. Nothing sent to any server")
                promise("cpu", "No AI. No bank passwords. Disconnect anytime")
            }
            .padding(18)
            .popSurface()

            status
            Spacer()

            switch gmail.status {
            case .idle where gmail.isConnected:
                PrimaryButton(title: "See where your money went", action: onFinish)
            case .syncing:
                PrimaryButton(title: "Continue — this keeps running", action: onFinish)
            default:
                PrimaryButton(title: "Continue with Google", symbol: "envelope.fill") { Task { await gmail.connect() } }
                HStack {
                    Button("Import a statement instead") {
                        onFinish()
                        Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); model.sheet = .importStatement }
                    }
                    Spacer()
                    Button("Skip", action: onFinish)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(24)
        .animation(.smooth, value: gmail.status)
    }

    @ViewBuilder private var status: some View {
        switch gmail.status {
        case let .syncing(found, processed):
            VStack(alignment: .leading, spacing: 8) {
                Text(found == 0 ? "Checking your email…" : "Reading \(found) emails on this iPhone…").font(.headline)
                ProgressView(value: Double(processed), total: Double(max(found, 1)))
                Text("\(store.transactions.count) transactions found so far").font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        case .idle where gmail.isConnected:
            Label("\(store.transactions.count) transactions found in your email", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange)
        default: EmptyView()
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline)
    }
}

/// Manual sources, available from "+" on Home.
struct SourceCards: View {
    let open: (AppSheet) -> Void

    var body: some View {
        VStack(spacing: 12) {
            card("banknote.fill", "Add cash", "Takes two seconds", .cash)
            card("doc.text.fill", "Import a statement", "Backfill older history · CSV · OFX · QFX · PDF", .importStatement)
            card("text.bubble.fill", "Paste an alert", "For a bank that doesn't email you", .pasteAlert)
            card("receipt.fill", "Add a receipt", "Adds shop and item detail", .receipt)
        }
    }

    private func card(_ symbol: String, _ title: String, _ detail: String, _ sheet: AppSheet) -> some View {
        Button { open(sheet) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 44, height: 44)
                    .popSurface(elevated: true, tint: Pop.paccha)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popSurface(elevated: true)
    }
}

struct BringMoneyInSheet: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationStack {
            ScrollView {
                SourceCards { sheet in
                    model.sheet = nil
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); model.sheet = sheet }
                }
                .padding(20)
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
