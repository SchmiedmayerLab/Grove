//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


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
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol TestAppTests: RawRepresentable, Hashable, CaseIterable, Identifiable where RawValue: StringProtocol {
    associatedtype Content: View
    
    @MainActor
    @ViewBuilder
    /// Returns a SwiftUi `View` associated with the enum case.
    /// - Parameter path: A `NavigationPath` binding that can be passed to the subviews.
    /// - Returns:Returns a SwiftUi `View` associated with the enum case.
    func view(withNavigationPath path: Binding<NavigationPath>) -> Content
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension TestAppTests {
    /// Unique identifier based on the ``TestAppTests``'s `rawValue`.
    public var id: RawValue {
        self.rawValue
    }
}
