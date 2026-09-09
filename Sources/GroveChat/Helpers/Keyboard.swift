//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif


/// Resigns whichever text field holds the keyboard.
///
/// A sheet presented over the composer leaves the keyboard standing on iOS; a picture or file viewer should not open
/// behind it.
@MainActor
func dismissKeyboard() {
    #if os(iOS) || os(visionOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}
