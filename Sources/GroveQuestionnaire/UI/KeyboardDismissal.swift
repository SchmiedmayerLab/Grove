//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


#if canImport(UIKit) && !os(watchOS)
/// A tap on the window that ends editing, unless it lands on a field.
///
/// A SwiftUI gesture on the form fires for taps on its fields too, and a field tapped and told to resign
/// in the same instant keeps or loses the keyboard by chance. A recogniser can look at the touch first.
private struct KeyboardDismissingTap: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowTapView {
        WindowTapView()
    }

    func updateUIView(_ uiView: WindowTapView, context: Context) {}
}


/// Carries the recogniser onto whichever window it lands in, and takes it off again on the way out.
private final class WindowTapView: UIView, UIGestureRecognizerDelegate {
    private var recognizer: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let recognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        guard let window else {
            return
        }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    @objc
    private func tapped() {
        window?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is any UITextInput {
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    deinit {
        if let recognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
    }
}
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Lets the keyboard go the way the system's forms let it go: a tap anywhere else, a drag down the page, or
    /// Return on a single-line field. Apply it to the page's form.
    func dismissesKeyboardLikeAForm() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            #if canImport(UIKit) && !os(watchOS)
            .background(KeyboardDismissingTap())
            #endif
    }
}
