import NeoPop
import SwiftUI
import UIKit

/// SwiftUI wrappers around CRED's open-source NeoPOP components (Apache 2.0,
/// github.com/CRED-CLUB/neopop-ios). These are CRED's actual controls — the
/// 3D press, levitating floating button and shimmer come from the library itself.

/// The signature CRED call-to-action: floating 3D block with a shimmer sweep.
struct NeoFloatingButton: UIViewRepresentable {
    let title: String
    var color: UIColor = UIColor(Pop.ink)
    var textColor: UIColor = .white
    var shimmer = true
    let action: () -> Void

    func makeUIView(context: Context) -> PopFloatingButton {
        let button = PopFloatingButton()
        button.configureFloatingButton(withModel: .init(backgroundColor: color, shadowColor: UIColor(Pop.canvas),
                                                        edgeWidth: 9, shimmerModel: shimmer ? PopShimmerModel(spacing: 10, lineColor1: .white, lineColor2: .white,
                                                                                                                   lineWidth1: 16, lineWidth2: 35, duration: 2.5, delay: 5) : nil))
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        apply(to: button)
        if shimmer { button.startShimmerAnimation() }
        return button
    }

    func updateUIView(_ button: PopFloatingButton, context: Context) {
        context.coordinator.action = action
        apply(to: button)
    }

    private func apply(to button: PopFloatingButton) {
        let text = NSAttributedString(string: title.uppercased(), attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: textColor, .kern: 1.6,
        ])
        button.configureButtonContent(withModel: .init(attributedTitle: text))
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Standard NeoPOP elevated button (bottom-right edges, press-in effect).
struct NeoButton: UIViewRepresentable {
    let title: String
    var symbol: String? = nil
    var color: UIColor = .white
    var textColor: UIColor = UIColor(Pop.ink)
    var parent: UIColor = .white
    let action: () -> Void

    func makeUIView(context: Context) -> PopButton {
        let button = PopButton()
        button.configurePopButton(withModel: .init(direction: .bottomRight, position: .bottomRight, backgroundColor: color,
                                                   superViewColor: parent, parentContainerBGColor: parent,
                                                   buttonFaceBorderColor: EdgeColors(color: UIColor(Pop.ink)), borderWidth: 1,
                                                   edgeLength: 3, customEdgeColor: EdgeColors(left: nil, right: UIColor(Pop.ink),
                                                                                              top: nil, bottom: UIColor(Pop.ink))))
        button.addTarget(context.coordinator, action: #selector(NeoFloatingButton.Coordinator.tapped), for: .touchUpInside)
        apply(to: button)
        return button
    }

    func updateUIView(_ button: PopButton, context: Context) {
        context.coordinator.action = action
        apply(to: button)
    }

    private func apply(to button: PopButton) {
        let text = NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: textColor])
        let image = symbol.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) }
        button.configureButtonContent(withModel: .init(attributedTitle: text, leftImage: image, leftImageTintColor: textColor,
                                                       leftImageScale: 0.9, contentLeftRightInset: 14))
    }

    func makeCoordinator() -> NeoFloatingButton.Coordinator { .init(action: action) }
}

/// NeoPOP switch.
struct NeoSwitch: UIViewRepresentable {
    @Binding var isOn: Bool

    func makeUIView(context: Context) -> PopSwitch {
        let s = PopSwitch()
        s.configureMode(.light)
        s.setOn(isOn, animated: false)
        s.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return s
    }

    func updateUIView(_ s: PopSwitch, context: Context) {
        if s.isOn != isOn { s.setOn(isOn, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }
    final class Coordinator: NSObject {
        let isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func changed(_ s: PopSwitch) { isOn.wrappedValue = s.isOn }
    }
}

/// Measured sizes for the UIKit-backed controls.
extension View {
    func neoSize(height: CGFloat = 50, width: CGFloat? = nil) -> some View {
        frame(width: width, height: height)
    }
}
