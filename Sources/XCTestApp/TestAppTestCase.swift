//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A collection of test cases that can be executed in an ``TestAppView``.
public protocol TestAppTestCase: Identifiable {
    /// Implement this method to run all the tests that should be executed.
    @MainActor
    func runTests() async throws
}


extension TestAppTestCase {
    /// Identifier of the ``TestAppTestCase`` providing a unique value for each ``TestAppTestCase`` type.
    public var id: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }
}
