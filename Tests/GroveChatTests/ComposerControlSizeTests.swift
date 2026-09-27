//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveChat
import SwiftUI
import Testing


/// Holds the composer's round controls to the field's height; a button style that pads its label grows them past it.
@Suite("Composer Controls")
@MainActor
struct ComposerControlSizeTests {
    @Test("A round control is exactly as tall as the field")
    func roundControlMatchesTheField() {
        guard #available(iOS 26, macOS 26, visionOS 26, *) else {
            return
        }
        let size = fittingSize(of: Button {} label: { Image(systemName: "plus") }.buttonStyle(.composerControl))
        #expect(size.width == MessageInputView.controlSize)
        #expect(size.height == MessageInputView.controlSize)
    }

    private func fittingSize(of view: some View) -> CGSize {
        let proposal = CGSize(width: 400, height: 400)
        #if canImport(UIKit)
        return UIHostingController(rootView: view).sizeThatFits(in: proposal)
        #else
        return NSHostingController(rootView: view).sizeThatFits(in: proposal)
        #endif
    }
}
