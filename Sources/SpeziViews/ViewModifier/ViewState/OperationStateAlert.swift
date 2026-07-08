//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
private struct OperationStateAlert<T: OperationState>: ViewModifier {
    private let operationState: T
    @State private var viewState: ViewState
    
    init(operationState: T) {
        self.operationState = operationState
        self._viewState = State(wrappedValue: operationState.representation)
    }
    
    
    func body(content: Content) -> some View {
        content
            .map(state: operationState, to: $viewState)
            .viewStateAlert(state: $viewState)
    }
}


extension View {
    /// Automatically displays an alert using the localized error descriptions based on a ``ViewState``  derived from an ``OperationState``.
    /// - Parameter state: The ``OperationState`` from which the ``ViewState`` is derived.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    public func viewStateAlert<T: OperationState>(state: T) -> some View {
        self
            .modifier(OperationStateAlert(operationState: state))
    }
}
