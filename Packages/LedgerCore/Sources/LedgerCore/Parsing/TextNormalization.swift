import Foundation

enum TextNormalization {
    static func collapse(_ s: String) -> String {
        RX.replace(#"\s+"#, in: s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes identifiers (VPAs, emails, long digit runs) and rail prefixes.
    static func stripIdentifiers(_ raw: String) -> String {
        var s = raw
        s = RX.replace(#"\S+@\S+"#, in: s, with: " ")
        s = RX.replace(#"[Xx*#]*\d{4,}"#, in: s, with: " ")
        s = RX.replace(#"[/_*#|:]+"#, in: s, with: " ")
        return collapse(s)
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
    }

    static func titleCase(_ s: String) -> String {
        let shouting = s.filter(\.isLetter).allSatisfy(\.isUppercase)
        return s.split(separator: " ").map { w in
            !shouting && w.count <= 3 && w.allSatisfy(\.isUppercase) ? String(w) : w.capitalized
        }.joined(separator: " ")
    }
}
