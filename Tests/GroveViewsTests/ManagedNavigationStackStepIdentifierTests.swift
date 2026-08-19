//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveViews
import SwiftUI
import Testing


@Suite
struct ManagedNavigationStackIdentifierTests {
    @Test
    @MainActor
    func testOnboardingIdentifierModifier() throws {
        let path = ManagedNavigationStack.Path()
        let step = Text("Hello World")
            .navigationStepIdentifier("Custom Identifier")
        #expect(!path.didConfigure)
        // The stack configures its path when it first appears, which doesn't happen for a view that is never
        // added to a view hierarchy; we perform the configuration manually instead.
        path.configure(
            elements: [.init(view: step, sourceLocation: .init(fileId: #fileID, line: #line, column: #column))],
            isComplete: nil,
            startAtStep: nil
        )
        #expect(path.didConfigure)
        let identifier = try #require(path.firstStepIdentifier)
        #expect(identifier.identifierKind == .identifiable("Custom Identifier"))
    }
}
