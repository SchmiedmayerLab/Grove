//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


extension Binding {
    func withDefault<T>(
        _ defaultValue: @autoclosure @escaping @Sendable () -> T
    ) -> Binding<T> where Value == T?, Self: Sendable {
        Binding<T> {
            self.wrappedValue ?? defaultValue()
        } set: { newValue in
            self.wrappedValue = newValue
        }
    }
}
