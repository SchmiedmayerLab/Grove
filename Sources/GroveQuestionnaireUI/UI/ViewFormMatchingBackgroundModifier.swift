//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


extension View {
    /// Sets the view's background to a color that matches the system's background color used for `Form`s with a `grouped` style.
    func makeBackgroundMatchFormBackground() -> some View {
        #if canImport(UIKit)
        self.background(Color(uiColor: .systemGroupedBackground))
        #else
        self
        #endif
    }
}
