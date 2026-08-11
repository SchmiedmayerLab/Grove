//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
private struct OperationStateAlert<T: OperationState>: ViewModifier {
    private let operationState: T
    // periphery:ignore - read through its projected value
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


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Automatically displays an alert using the localized error descriptions based on a ``ViewState``  derived from an ``OperationState``.
    /// - Parameter state: The ``OperationState`` from which the ``ViewState`` is derived.
    public func viewStateAlert<T: OperationState>(state: T) -> some View {
        self
            .modifier(OperationStateAlert(operationState: state))
    }
}
