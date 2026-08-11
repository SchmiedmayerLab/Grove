//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


extension ViewModifier {
    func inject<V: View>(into view: V) -> AnyView {
        AnyView(view.modifier(self))
    }
}


extension View {
    func anyModifiers(_ modifiers: [any ViewModifier]) -> some View {
        var anyView = AnyView(self)
        for modifier in modifiers {
            anyView = modifier.inject(into: anyView)
        }
        return anyView
    }
}
