import SwiftUI

struct LockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: model.lock.lastError)
                Text("Influenza is locked").font(.title2.bold())
                if let error = model.lock.lastError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Button { Task { await model.lock.unlock() } } label: {
                    Label("Unlock with \(model.lock.biometryName)", systemImage: "faceid").padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(PopButtonStyle(kind: .primary, fullWidth: false)).controlSize(.large)
            }
        }
        .task { await model.lock.unlock() }
    }
}
