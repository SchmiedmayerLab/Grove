//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Allows the definition of an enum of different test cases in your test application that are associated with SwiftUI views
@available(iOS 18, macOS 15, watchOS 11, *)
public struct TestAppTestsView<Tests: TestAppTests>: View {
    private let showCloseButton: Bool

    @Environment(\.dismiss)
    private var dismiss

    // periphery:ignore - read through its projected value
    @State private var path = NavigationPath()

    public var body: some View {
        NavigationStack(path: $path) {
            List(Array(Tests.allCases)) { test in
                NavigationLink(test.rawValue, value: test)
            }
                .navigationDestination(for: Tests.self) { test in
                    test
                        .view(withNavigationPath: $path)
                        .navigationTitle(test.rawValue)
#if !os(macOS) && !os(tvOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif
                }
                .navigationTitle(String(describing: Tests.self))
                .toolbar {
                    if showCloseButton {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                dismiss()
                            }
                        }
                    }
                }
        }
    }
    

    // periphery:ignore:parameters tests - drives generic inference for out-of-index UI-test apps
    /// Create a new tests view.
    /// - Parameters:
    ///   - tests: The ``TestAppTests`` type that should be associated with the ``TestAppTestsView``
    ///   - showCloseButton: Show an optional close button. Helpful if this view is presented within a modal view.
    public init(tests: Tests.Type = Tests.self, showCloseButton: Bool = false) {
        self.showCloseButton = showCloseButton
    }
}
