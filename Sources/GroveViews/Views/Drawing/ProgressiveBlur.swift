//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


#if os(iOS) || os(visionOS)
@available(iOS 18, visionOS 2, *)
private struct UIKitProgressiveBlur: UIViewRepresentable {
    final class MaskedVisualEffectView: UIVisualEffectView {
        private let gradient = CAGradientLayer()

        var locations: [Double] {
            get { (gradient.locations ?? []).map(\.doubleValue) }
            set { gradient.locations = newValue.map { NSNumber(value: $0) } } // swiftlint:disable:this legacy_objc_type
        }

        init() {
            super.init(effect: UIBlurEffect(style: .regular))
            gradient.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            layer.mask = gradient
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            gradient.frame = bounds
        }
    }

    let locations: [Double]

    func makeUIView(context: Context) -> MaskedVisualEffectView {
        MaskedVisualEffectView()
    }

    func updateUIView(_ view: MaskedVisualEffectView, context: Context) {
        view.locations = locations
    }
}
#endif


/// A blur that fades in from clear at the top to full strength at the bottom.
///
/// Put it behind controls that float over scrolling content, such as a chat composer or a set of onboarding buttons:
/// what scrolls underneath stays legible where the blur is faint and gives way to the controls where it is strong.
///
/// - Parameter locations: Where the blur starts and where it reaches full strength, as fractions of the height.
///   `[0, 0.55]` fades in over the top half and stays fully blurred below.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ProgressiveBlur: View {
    private let locations: [Double]

    @_documentation(visibility: internal)
    public var body: some View {
        #if os(iOS) || os(visionOS)
        UIKitProgressiveBlur(locations: locations)
        #else
        // No masked visual effect view elsewhere; a material under a gradient mask reads the same way.
        Rectangle()
            .fill(.regularMaterial)
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: locations[0]), .init(color: .black, location: locations[1])],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        #endif
    }

    /// - Parameter locations: The start and the full-strength point of the fade, as fractions of the height.
    public init(locations: [Double] = [0, 1]) {
        precondition(locations.count == 2, "A progressive blur fades between exactly two locations.")
        self.locations = locations
    }
}
