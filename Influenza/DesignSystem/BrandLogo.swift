import LedgerCore
import SwiftUI
import UIKit

/// Online lookup for brands not bundled with the app: the brand's official App Store
/// icon, matched strictly by name and cached on the phone. Sends only the shop name —
/// never amounts, dates or anything about you. Can be switched off in Privacy Center.
actor LogoLookup {
    static let shared = LogoLookup()
    private let dir = URL.cachesDirectory.appending(path: "BrandLogos", directoryHint: .isDirectory)
    private var memory: [String: UIImage] = [:]
    private var misses: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for name: String) async -> UIImage? {
        let key = BrandLogo.slug(name)
        guard key.count >= 3 else { return nil }
        if let hit = memory[key] { return hit }
        if misses.contains(key) { return nil }
        let file = dir.appending(path: "\(key).png"), miss = dir.appending(path: "\(key).miss")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) { memory[key] = img; return img }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: miss.path), let date = attrs[.modificationDate] as? Date,
           Date.now.timeIntervalSince(date) < 14 * 86_400 { misses.insert(key); return nil }   // retry misses after two weeks
        if let running = inFlight[key] { return await running.value }
        let task = Task<UIImage?, Never> { await Self.search(name) }
        inFlight[key] = task
        let img = await task.value
        inFlight[key] = nil
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let img, let png = img.pngData() { memory[key] = img; try? png.write(to: file) }
        else { misses.insert(key); try? Data().write(to: miss) }
        return img
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    private static func search(_ name: String) async -> UIImage? {
        let target = normalized(name)
        let countries = [Locale.current.region?.identifier.lowercased() ?? "us", "us", "in", "gb"].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for country in countries.prefix(3) {
            var c = URLComponents(string: "https://itunes.apple.com/search")!
            c.queryItems = [.init(name: "term", value: name), .init(name: "entity", value: "software"),
                            .init(name: "country", value: country), .init(name: "limit", value: "6")]
            guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { continue }
            // Strict: the app's name or its publisher must contain the whole merchant name.
            let match = results.first { r in
                let track = normalized(r["trackName"] as? String ?? ""), seller = normalized(r["sellerName"] as? String ?? "")
                return track.hasPrefix(target) || seller.hasPrefix(target) || (target.count >= 6 && (track.contains(target) || seller.contains(target)))
            }
            guard let art = (match?["artworkUrl512"] ?? match?["artworkUrl100"]) as? String, let artURL = URL(string: art),
                  let (img, _) = try? await URLSession.shared.data(from: artURL), let image = UIImage(data: img) else { continue }
            return image.preparingThumbnail(of: CGSize(width: 256, height: 256)) ?? image
        }
        return nil
    }
}

/// Brand logo: bundled official icon → online App Store icon → 3D category icon.
struct BrandLogo: View {
    let name: String
    var categoryID: String? = nil
    var size: CGFloat = 40
    @AppStorage("onlineLogosEnabled") private var onlineLogos = true
    @State private var fetched: UIImage?

    static func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func bundled(_ name: String) -> UIImage? { UIImage(named: "brand-\(slug(name))") }

    /// Only look up names that plausibly belong to a brand (not people, transfers or "Cash").
    private var eligibleForLookup: Bool {
        let top = (categoryID ?? "").split(separator: ".").first.map(String.init) ?? ""
        return !["financial", "income"].contains(top) && !["cash", "unknown"].contains(name.lowercased())
            && !MerchantNames.looksLikePerson(name) && name.filter(\.isLetter).count >= 3
    }

    var body: some View {
        Group {
            if let logo = Self.bundled(name) ?? fetched {
                logoView(logo)
            } else {
                CategoryIcon3D(categoryID: categoryID ?? BrandCatalog.defaultCategory(for: name), size: size)
            }
        }
        .task(id: "\(name)|\(onlineLogos)") {
            guard Self.bundled(name) == nil, onlineLogos, eligibleForLookup else { fetched = nil; return }
            fetched = await LogoLookup.shared.image(for: name)
        }
    }

    private func logoView(_ logo: UIImage) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: logo).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            if let categoryID, size >= 36 {
                Image(systemName: CategoryStyle.symbol(categoryID))
                    .font(.system(size: size * 0.19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(CategoryStyle.tint(categoryID), in: .circle)
                    .overlay(Circle().stroke(Pop.black300, lineWidth: 2))
                    .offset(x: size * 0.1, y: size * 0.1)
            }
        }
        .accessibilityHidden(true)
    }
}
