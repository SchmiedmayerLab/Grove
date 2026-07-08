//
// This source file is part of the Stanford XCTestExtensions open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Allows the definition of an enum of different test cases in your test application that are associated with SwiftUI views.
///
/// The following example demonstrates the usage for a simple test app with two cases:
/// ```swift
/// enum TestAppTestsExample: String, TestAppTests {
///     case firstTest = "First Test"
///     case secondTest = "Second Test"
///
///
///     func view(withNavigationPath path: Binding<NavigationPath>) -> some View {
///         switch self {
///         case .firstTest:
///             FirstTestTestsView()
///         case .secondTest:
///             SecondTestTestsView()
///         }
///     }
/// }
/// ```
@available(iOS 16, macOS 13, watchOS 9, visionOS 1, *)
public protocol TestAppTests: RawRepresentable, Hashable, CaseIterable, Identifiable where RawValue: StringProtocol {
    associatedtype Content: View
    
    @MainActor
    @ViewBuilder
    /// Returns a SwiftUi `View` associated with the enum case.
    /// - Parameter path: A `NavigationPath` binding that can be passed to the subviews.
    /// - Returns:Returns a SwiftUi `View` associated with the enum case.
    func view(withNavigationPath path: Binding<NavigationPath>) -> Content
}


@available(iOS 16, macOS 13, watchOS 9, visionOS 1, *)
extension TestAppTests {
    /// Unique identifier based on the ``TestAppTests``'s `rawValue`.
    public var id: RawValue {
        self.rawValue
    }
}
