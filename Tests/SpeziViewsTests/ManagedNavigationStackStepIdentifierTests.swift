//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziViews
import SwiftUI
import Testing


struct ManagedNavigationStackIdentifierTests {
    @Test
    @MainActor
    func testOnboardingIdentifierModifier() throws {
        let path = ManagedNavigationStack.Path()
        let stack = ManagedNavigationStack(path: path) {
            Text("Hello World")
                .navigationStepIdentifier("Custom Identifier")
        }
        // The stack configures its path when it first appears, which doesn't happen for a view that is never
        // added to a view hierarchy; we perform the configuration manually instead.
        stack.configurePath()

        #expect(path.didConfigure)
        let identifier = try #require(path.firstStepIdentifier)
        #expect(identifier.identifierKind == .identifiable("Custom Identifier"))
    }
}
