import LedgerCore
import SwiftUI

/// Automatic-capture status: connecting, syncing progress, last update, reconnect.
struct SyncStatusCard: View {
    @Environment(GmailSource.self) private var gmail

    var body: some View {
        switch gmail.status {
        case .notConnected:
            Button { Task { await gmail.connect() } } label: {
                row("bolt.badge.automatic.fill", "Turn on automatic tracking", "Connect Gmail — takes 10 seconds", tint: .accentColor, chevron: true)
            }
            .buttonStyle(.plain)
            .popSurface(elevated: true, tint: Pop.paccha)
        case let .syncing(found, processed):
            VStack(alignment: .leading, spacing: 8) {
                row("arrow.triangle.2.circlepath", found == 0 ? "Checking your email…" : "Reading \(found) emails on this iPhone…",
                    found == 0 ? "Looking for bank and card alerts" : "\(processed) of \(found)", tint: .accentColor, chevron: false)
                if found > 0 { ProgressView(value: Double(processed), total: Double(max(found, 1))).padding(.horizontal, 16).padding(.bottom, 12) }
            }
            .popSurface()
        case .needsReconnect:
            Button { Task { await gmail.connect() } } label: {
                row("exclamationmark.arrow.triangle.2.circlepath", "Reconnect Gmail", "Google asks test apps to sign in again weekly", tint: .orange, chevron: true)
            }
            .buttonStyle(.plain)
            .popSurface(elevated: true, tint: Pop.orange)
        case let .failed(message):
            row("wifi.exclamationmark", "Couldn't update", message, tint: .orange, chevron: false)
                .popSurface()
        case .idle:
            if let last = gmail.lastSync {
                Label("Updated \(last.formatted(.relative(presentation: .named))) · automatic", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ subtitle: String, tint: Color, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                .symbolEffect(.rotate, isActive: { if case .syncing = gmail.status { return true } else { return false } }())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if chevron { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .padding(16)
        .contentShape(.rect)
    }
}
