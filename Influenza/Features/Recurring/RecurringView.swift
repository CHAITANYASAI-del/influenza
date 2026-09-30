import LedgerCore
import SwiftUI

struct RecurringView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        List {
            if store.recurring.isEmpty {
                ContentUnavailableView("No repeats yet", systemImage: "repeat",
                                       description: Text("Subscriptions and bills appear after they repeat."))
            }
            ForEach(store.recurring) { s in
                HStack(spacing: 12) {
                    Image(systemName: "repeat").frame(width: 36, height: 36).popSurface()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.merchantName).font(.body.weight(.medium))
                        Text("\(s.cadence.rawValue.capitalized) · next \(s.nextExpectedDate.formatted(.dateTime.day().month(.abbreviated)))\(s.kind == .likelyRecurring ? " · likely" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.money(s.typicalAmount, s.currencyCode)).font(.body.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .navigationTitle("Recurring")
    }
}
