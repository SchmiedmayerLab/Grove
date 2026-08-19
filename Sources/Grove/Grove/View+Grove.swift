//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
import Foundation
public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
@_spi(APISupport)
public struct GroveViewModifier: ViewModifier {
    @State private var grove: Grove
    
    
    public init(_ grove: Grove) {
        self.grove = grove
    }
    
    
    public func body(content: Content) -> some View {
        grove.viewModifiers
            .modify(content)
            .task(grove.run) // service lifecycle
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Configure Grove for your application using a delegate.
    /// - Parameter delegate: The ``GroveAppDelegate`` used in the SwiftUI App instance.
    /// - Returns: The configured view using the Grove framework.
    @MainActor
    public func grove(_ delegate: GroveAppDelegate) -> some View {
        modifier(GroveViewModifier(delegate.grove))
    }
}


extension Array where Element == any ViewModifier {
    @MainActor
    fileprivate func modify<V: View>(_ view: V) -> AnyView {
        var view = AnyView(view)
        for modifier in self {
            view = modifier.modify(view)
        }
        return view
    }
}


extension ViewModifier {
    fileprivate func modify(_ view: AnyView) -> AnyView {
        AnyView(view.modifier(self))
    }
}
#endif
