//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Observation
#if canImport(SwiftUI)
import SwiftUI
#endif


/// Places a ``Module`` into the SwiftUI environment.
///
/// Below is a short code example how you would declare an environment accessible module,
/// and how to access it within SwiftUI, if it is configured in your ``Configuration``.
///
/// ```swift
/// public class ExampleModule: Module, EnvironmentAccessible {
///     // ... implement your functionality
/// }
///
///
/// struct ExampleView: View {
///     @Environment(ExampleModule.self) var module
///
///     var body: some View {
///         // ... access module functionality
///     }
/// }
/// ```
///
/// The conformance itself needs nothing from SwiftUI, so it stays available where SwiftUI isn't — a module can
/// declare it once and be usable both in an app and on a server. Only the environment plumbing below is
/// Apple-only; on other platforms the conformance simply has no environment to be placed into.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol EnvironmentAccessible: AnyObject, Observable {}


#if canImport(SwiftUI)
@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentAccessible {
    @MainActor var viewModifier: any ViewModifier {
        ModelModifier(model: self)
    }
}
#endif
