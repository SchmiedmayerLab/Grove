//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
import SwiftUI


@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
struct ModelModifier<Model: Observable & AnyObject>: ViewModifier {
    @State private var model: Model

    init(model: Model) {
        self.model = model
    }

    func body(content: Content) -> some View {
        content
            .environment(model)
    }
}
#endif
