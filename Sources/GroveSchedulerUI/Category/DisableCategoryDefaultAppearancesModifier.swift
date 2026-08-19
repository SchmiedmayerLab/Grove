//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct DisableCategoryDefaultAppearancesModifier: ViewModifier { // swiftlint:disable:this type_name
    private let disabled: Bool

    @Environment(\.taskCategoryAppearances)
    private var taskCategoryAppearances

    init(disabled: Bool) {
        self.disabled = disabled
    }

    func body(content: Content) -> some View {
        content
            .environment(\.taskCategoryAppearances, taskCategoryAppearances.disablingDefaultAppearances(disabled))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    func disableCategoryDefaultAppearances(_ disabled: Bool = true) -> some View {
        modifier(DisableCategoryDefaultAppearancesModifier(disabled: disabled))
    }
}
