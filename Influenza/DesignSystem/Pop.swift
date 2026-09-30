import LedgerCore
import SwiftUI
import UIKit

/// CRED-style light design language: off-white canvas, white sheets, serif
/// money, letter-spaced small caps, thin icons, small pill actions, soft 3D edges.
/// Legacy token names are kept as aliases so every screen picks up the new look.
enum Pop {
    // Semantic tokens
    static let canvas = Color(hex: "F2F1EE")
    static let sheet = Color.white
    static let ink = Color(hex: "111111")
    static let ink2 = Color(hex: "7A7A7A")
    static let hairline = Color(hex: "E4E4E1")
    static let subtle = Color(hex: "F7F7F5")
    static let link = Color(hex: "2C5ECD")
    static let positive = Color(hex: "0E9F6E")
    static let negative = Color(hex: "E0662A")

    // Legacy aliases (mapped to the light system)
    static let black500 = canvas
    static let black400 = subtle
    static let black300 = sheet
    static let black200 = hairline
    static let black100 = ink2
    static let paccha = ink
    static let parkGreen = positive
    static let orange = negative
    static let pink = Color(hex: "E5486B")
    static let purple = Color(hex: "6A35FF")
    static let manna = Color(hex: "E3A92B")
    static let yoyo = Color(hex: "9B45E4")

    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static let label = Font.system(size: 11, weight: .semibold)

    static func shade(_ color: Color, _ factor: CGFloat) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: s, brightness: max(0, min(1, b * factor)), opacity: a)
    }
}

// MARK: - Typography

/// "₹3,107.47": bold serif rupees, lighter paise.
struct MoneyText: View {
    let amount: Decimal
    let currency: String
    var size: CGFloat = 40
    var signed = false

    var body: some View {
        let text = Fmt.money(amount, currency, signed: signed)
        let sep = Locale.current.decimalSeparator ?? "."
        if let r = text.range(of: sep, options: .backwards), text.distance(from: r.lowerBound, to: text.endIndex) <= 3 {
            (Text(text[..<r.lowerBound]).font(.system(size: size, weight: .semibold, design: .serif))
             + Text(text[r.lowerBound...]).font(.system(size: size * 0.92, weight: .light, design: .serif)))
                .monospacedDigit()
        } else {
            Text(text).font(.system(size: size, weight: .semibold, design: .serif)).monospacedDigit()
        }
    }
}

struct PopLabel: View {
    let text: String
    var color: Color = Pop.ink2
    var body: some View { Text(text.uppercased()).font(Pop.label).tracking(2.4).foregroundStyle(color) }
}

struct PopTag: View {
    let text: String
    var color: Color = Pop.ink2
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.2)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.1), in: .capsule)
    }
}

/// Blue small-caps link, like "CHECK BALANCE".
struct PopLink: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.4).underline()
            }
            .foregroundStyle(Pop.link)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buttons

struct PopButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, dark }
    var kind: Kind = .primary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        Group {
            switch kind {
            case .primary:
                // Black block with a thin 3D edge — the main call to action.
                configuration.label
                    .font(.system(size: 13, weight: .bold)).textCase(.uppercase).tracking(1.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).frame(height: 48)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .background(Pop.ink)
                    .background(alignment: .topLeading) { PopEdges(color: Color(hex: "3A3A3A"), depth: pressed ? 0 : 3) }
                    .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
                    .padding(.trailing, 3).padding(.bottom, 3)
            case .secondary, .dark:
                // Small outlined pill, like "send money".
                configuration.label
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Pop.ink)
                    .padding(.horizontal, 14).frame(height: 38)
                    .frame(maxWidth: fullWidth && kind == .secondary ? .infinity : nil)
                    .background(Pop.sheet, in: .capsule)
                    .overlay(Capsule().stroke(Pop.hairline, lineWidth: 1))
                    .background(Capsule().fill(Pop.hairline).offset(y: pressed ? 0 : 2.5))
                    .offset(y: pressed ? 2 : 0)
            }
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
        .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, now in now }
    }
}

struct PopEdges: View {
    let color: Color
    var depth: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, d = depth
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w + d, y: d))
                    p.addLine(to: CGPoint(x: w + d, y: h + d)); p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
                }.fill(Pop.shade(color, 0.85))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: w + d, y: h + d)); p.addLine(to: CGPoint(x: d, y: h + d)); p.closeSubpath()
                }.fill(Pop.shade(color, 0.6))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Surfaces

/// White rounded surface with a hairline — used sparingly (sheets, inputs, small panels).
struct PopSurface: ViewModifier {
    var elevated = false
    var tint: Color? = nil
    func body(content: Content) -> some View {
        content
            .background(tint.map { $0.opacity(0.08) } ?? Pop.sheet, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.map { $0.opacity(0.35) } ?? Pop.hairline, lineWidth: 1))
    }
}

extension View {
    func popSurface(elevated: Bool = false, tint: Color? = nil) -> some View { modifier(PopSurface(elevated: elevated, tint: tint)) }
}

struct DashedDivider: View {
    var body: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Pop.hairline).frame(height: 1)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: r.width, y: 0)) } }
    }
}

/// Circle "coin" with a soft 3D bottom edge, used behind logos and icons in rows.
struct CoinFrame<Content: View>: View {
    var size: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(Circle().stroke(Pop.hairline, lineWidth: 1))
            .background(Circle().fill(Color(hex: "D9D8D4")).offset(y: size * 0.06))
            .padding(.bottom, size * 0.06)
    }
}

// MARK: - Category icon (for shops without a logo)

struct CategoryIcon3D: View {
    let categoryID: String
    var size: CGFloat = 40

    var body: some View {
        let tint = CategoryStyle.tint(categoryID)
        CoinFrame(size: size) {
            ZStack {
                LinearGradient(colors: [Pop.shade(tint, 1.15).opacity(0.22), tint.opacity(0.14)], startPoint: .top, endPoint: .bottom)
                Circle().fill(.white.opacity(0.6)).frame(width: size * 0.9).offset(y: -size * 0.45).blur(radius: size * 0.15)
                Image(systemName: CategoryStyle.symbol(categoryID))
                    .font(.system(size: size * 0.4, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Pop.shade(tint, 0.8))
            }
            .background(Pop.sheet)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Spend meter (kept for Trend)

struct SpendMeter: View {
    let spent: Decimal
    let usual: Decimal?
    let currency: String
    let caption: String

    private var ratio: Double {
        guard let usual, usual > 0 else { return 0.5 }
        return min(1, max(0, spent.double / (usual.double * 2)))
    }
    private var tone: Color {
        guard let usual, usual > 0 else { return Pop.ink }
        return spent <= usual ? Pop.positive : Pop.negative
    }
    private var verdict: String {
        guard let usual, usual > 0 else { return "this month" }
        if abs((spent - usual).double) / usual.double < 0.05 { return "about usual" }
        return spent < usual ? "below usual" : "above usual"
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().trim(from: 0.125, to: 0.875).stroke(Pop.subtle, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(90))
                Circle().trim(from: 0.125, to: 0.125 + 0.75 * ratio).stroke(tone, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(90)).animation(.spring(response: 0.9, dampingFraction: 0.8), value: ratio)
                VStack(spacing: 4) {
                    MoneyText(amount: spent, currency: currency, size: 26).minimumScaleFactor(0.5).lineLimit(1)
                    PopLabel(text: verdict, color: tone)
                }
                .padding(.horizontal, 24)
            }
            .frame(width: 190, height: 190).padding(.bottom, -24)
            Text(caption).font(.caption).foregroundStyle(Pop.ink2)
        }
    }
}
