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
        _ = ManagedNavigationStack(path: path) {
            Text("Hello World")
                .navigationStepIdentifier("Custom Identifier")
        }
        
        #expect(path.didConfigure)
        let identifier = try #require(path.firstStepIdentifier)
        #expect(identifier.identifierKind == .identifiable("Custom Identifier"))
    }
}
