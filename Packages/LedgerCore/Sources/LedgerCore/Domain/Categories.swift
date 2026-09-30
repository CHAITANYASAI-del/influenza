import Foundation

/// Data-driven category tree (spec §25). IDs are stable dotted paths.
public struct CategoryNode: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public var parentID: String? { id.contains(".") ? String(id.split(separator: ".").first!) : nil }
    public var topLevelID: String { String(id.split(separator: ".").first!) }
}

public enum CategoryTree {
    public static let all: [CategoryNode] = {
        let tree: [(String, String, String, [(String, String)])] = [
            ("food", "Food", "fork.knife", [("groceries", "Groceries"), ("restaurant", "Restaurant"), ("delivery", "Delivery"), ("coffee", "Coffee"), ("fastFood", "Fast Food"), ("bakery", "Bakery"), ("other", "Other")]),
            ("transport", "Transport", "car.fill", [("rideHailing", "Ride Hailing"), ("publicTransit", "Public Transit"), ("fuel", "Fuel"), ("parking", "Parking"), ("tolls", "Tolls"), ("flights", "Flights"), ("hotels", "Hotels"), ("vehicle", "Vehicle Maintenance")]),
            ("shopping", "Shopping", "bag.fill", [("general", "General"), ("electronics", "Electronics"), ("clothing", "Clothing"), ("home", "Home"), ("beauty", "Beauty"), ("personalCare", "Personal Care"), ("books", "Books"), ("marketplace", "Marketplace"), ("other", "Other")]),
            ("bills", "Bills", "bolt.fill", [("rent", "Rent"), ("electricity", "Electricity"), ("water", "Water"), ("gas", "Gas"), ("internet", "Internet"), ("mobile", "Mobile"), ("insurance", "Insurance"), ("software", "Software & apps"), ("subscriptions", "Subscriptions")]),
            ("entertainment", "Entertainment", "popcorn.fill", [("streaming", "Streaming"), ("gaming", "Gaming"), ("movies", "Movies"), ("events", "Events"), ("music", "Music"), ("sports", "Sports & games")]),
            ("health", "Health", "cross.case.fill", [("pharmacy", "Pharmacy"), ("doctor", "Doctor"), ("dental", "Dental"), ("fitness", "Fitness"), ("other", "Other")]),
            ("education", "Education", "book.fill", [("courses", "Courses"), ("fees", "Fees")]),
            ("financial", "Financial", "building.columns.fill", [("transfer", "Transfer"), ("creditCardPayment", "Credit Card Payment"), ("atm", "ATM Withdrawal"), ("bankFee", "Bank Fee"), ("interest", "Interest"), ("investment", "Investment"), ("loanPayment", "Loan Payment")]),
            ("people", "People", "person.2.fill", [("family", "Family"), ("friends", "Friends"), ("other", "Sent to people")]),
            ("income", "Income", "arrow.down.circle.fill", [("salary", "Salary"), ("refund", "Refund"), ("cashback", "Cashback"), ("interest", "Interest"), ("other", "Other")]),
            ("other", "Other", "square.grid.2x2.fill", [("local", "Local payments"), ("unknown", "Unknown")]),
        ]
        var nodes: [CategoryNode] = []
        for (id, name, symbol, children) in tree {
            nodes.append(CategoryNode(id: id, name: name, symbol: symbol))
            nodes += children.map { CategoryNode(id: "\(id).\($0.0)", name: $0.1, symbol: symbol) }
        }
        return nodes
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    public static func node(_ id: String) -> CategoryNode? { byID[id] }
    public static var topLevel: [CategoryNode] { all.filter { $0.parentID == nil } }

    /// "Food · Delivery"
    public static func displayName(_ id: String) -> String {
        guard let node = node(id) else { return "Other" }
        guard let parent = node.parentID.flatMap(self.node) else { return node.name }
        return "\(parent.name) · \(node.name)"
    }
}
