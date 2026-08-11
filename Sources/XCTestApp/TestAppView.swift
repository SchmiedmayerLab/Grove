//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Automatically run a ``TestAppTestCase`` instance and display the result for a UI test to use.
public struct TestAppView: View {
    @State private var testState = "Running ..."
    private let testCase: any TestAppTestCase
    

    public var body: some View {
        Text(testState)
            .task {
                do {
                    try await testCase.runTests()
                    testState = "Passed"
                } catch {
                    testState = "Failed: \(error)"
                }
            }
    }
    
    
    /// - Parameter testCase: The ``TestAppTestCase`` instance that should be executed.
    public init(testCase: any TestAppTestCase) {
        self.testCase = testCase
    }
}
