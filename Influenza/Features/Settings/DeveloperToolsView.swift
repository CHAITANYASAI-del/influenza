#if DEBUG
import LedgerCore
import SwiftUI

/// Spec §82 — DEBUG only; never shipped in Release.
struct DeveloperToolsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var status = ""

    var body: some View {
        List {
            Section("Seed") {
                Button("Seed India demo") { seedIndia() }
                Button("Seed US demo") { seedUS() }
                Button("Generate 5,000 transactions") { generate(5_000) }
            }
            Section("Stats") {
                LabeledContent("Evidence", value: "\(store.engine.state.evidence.count)")
                LabeledContent("Observations", value: "\(store.engine.state.observations.count)")
                LabeledContent("Canonical transactions", value: "\(store.engine.state.transactions.count)")
                LabeledContent("Review", value: "\(store.reviewCount)")
                LabeledContent("Recurring", value: "\(store.recurring.count)")
                if !status.isEmpty { Text(status).font(.caption) }
            }
            Section { Button("Clear test data", role: .destructive) { store.deleteAll() } }
        }
        .navigationTitle("Developer tools")
    }

    private func seedIndia() {
        let cal = Calendar.current
        func d(_ daysAgo: Int) -> String {
            let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
            return f.string(from: cal.date(byAdding: .day, value: -daysAgo, to: .now)!)
        }
        var rows = ["Date,Narration,Withdrawal Amt.,Deposit Amt."]
        rows += [
            "\(d(28)),SALARY ACME CORP,,150000.00", "\(d(26)),UPI/P2M/426912340001/SWIGGY,452.00,", "\(d(24)),UPI/P2M/426912340002/ZOMATO,389.00,",
            "\(d(22)),UPI/P2M/426912340003/UBER INDIA,218.00,", "\(d(20)),NETFLIX.COM,649.00,", "\(d(18)),UPI/P2M/426912340004/BLINKIT,812.50,",
            "\(d(15)),ATM WDL MG ROAD,5000.00,", "\(d(12)),CC PAYMENT ICICI CREDIT CARD,25000.00,", "\(d(10)),UPI/P2M/426912340005/AMAZON,1299.00,",
            "\(d(8)),REFUND AMAZON,1299.00,", "\(d(6)),BESCOM ELECTRICITY,1840.00,", "\(d(4)),UPI/P2M/426912340006/RAPIDO,96.00,",
            "\(d(2)),UPI/P2M/426912340007/SWIGGY INSTAMART,634.00,",
        ]
        _ = try? store.importStatement(text: rows.joined(separator: "\n"), fileName: "demo-hdfc.csv", format: .csv, data: nil)
        store.pasteAlert("Sent Rs.180.00 From HDFC Bank A/C *1234 To CHAI POINT On today Ref 426999990001")
        store.addCash(amount: 40, currency: "INR", merchant: "Chai", categoryID: "food.coffee", date: .now)
        status = "Seeded India demo"
    }

    private func seedUS() {
        let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"
        func d(_ n: Int) -> String { f.string(from: Calendar.current.date(byAdding: .day, value: -n, to: .now)!) }
        let rows = ["Date,Description,Amount",
                    "\(d(20)),DD *DOORDASH CHIPOTLE,-42.18", "\(d(18)),WHOLEFDS MKT #102,-56.20", "\(d(15)),UBER *TRIP,-18.40",
                    "\(d(12)),AMZN MKTP US*123,-89.99", "\(d(10)),TARGET 00012345,-50.00", "\(d(8)),SPOTIFY USA,-11.99",
                    "\(d(5)),PAYROLL ACME INC,3200.00", "\(d(3)),AUTOPAY PAYMENT - THANK YOU,-500.00"]
        _ = try? store.importStatement(text: rows.joined(separator: "\n"), fileName: "demo-chase.csv", format: .csv, data: nil)
        store.addReceipt("DoorDash\nRestaurant: Chipotle\nBurrito Bowl 28.00\nFees 6.00\nTip 8.18\nTotal $42.18",
                         date: Calendar.current.date(byAdding: .day, value: -20, to: .now)!)
        status = "Seeded US demo"
    }

    private func generate(_ n: Int) {
        let merchants = ["SWIGGY", "ZOMATO", "UBER INDIA", "AMAZON", "BIGBASKET", "NETFLIX.COM", "SHELL", "STARBUCKS", "BLINKIT", "MYNTRA"]
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        var rows = ["Date,Description,Amount"]
        for i in 0..<n {
            let date = Calendar.current.date(byAdding: .hour, value: -i * 3, to: .now)!
            rows.append("\(f.string(from: date)),\(merchants[i % merchants.count]) \(i),-\(100 + (i * 37) % 4900).\(String(format: "%02d", i % 100))")
        }
        let t = Date()
        let job = try? store.importStatement(text: rows.joined(separator: "\n"), fileName: "gen-\(n).csv", format: .csv, data: nil)
        status = "Imported \(job?.newTransactions ?? 0) in \(String(format: "%.1f", Date().timeIntervalSince(t)))s"
    }
}
#endif
