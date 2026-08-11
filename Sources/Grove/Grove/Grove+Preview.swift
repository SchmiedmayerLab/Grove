//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
import Foundation
import RuntimeAssertions
public import SwiftUI


#if os(iOS) || os(visionOS) || os(tvOS)
/// Protocol used to silence deprecation warnings.
package protocol DeprecatedLaunchOptionsCall {
    /// Forward to legacy lifecycle handlers.
    @MainActor
    func callWillFinishLaunching(_ application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any])
}
#endif


/// Options to simulate behavior for a ``LifecycleHandler`` in cases where there is no app delegate like in Preview setups.
@MainActor
public enum LifecycleSimulationOptions {
    /// Simulation is disabled.
    case disabled
#if os(iOS) || os(visionOS) || os(tvOS)
    /// Injects the ``Grove/launchOptions`` property to be accessed via the `@Application` property wrapper.
    case launchWithOptions(_ launchOptions: [UIApplication.LaunchOptionsKey: Any])
#elseif os(macOS)
    /// Injects the ``Grove/launchOptions`` property to be accessed via the `@Application` property wrapper.
    case launchWithOptions(_ launchOptions: [Never: Any])
#else // os(watchOS)
    /// Injects the ``Grove/launchOptions`` property to be accessed via the `@Application` property wrapper.
    case launchWithOptions(_ launchOptions: [Never: Any])
#endif

    static let launchWithOptions: LifecycleSimulationOptions = .launchWithOptions([:])
}


#if os(iOS) || os(visionOS) || os(tvOS)
@available(iOS 18, macOS 15, watchOS 11, *)
extension Grove: DeprecatedLaunchOptionsCall {
    @available(*, deprecated, message: "Propagate deprecation warning.")
    package func callWillFinishLaunching(_ application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]) {
        lifecycleHandler.willFinishLaunchingWithOptions(application, launchOptions: launchOptions)
    }
}
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Configure Grove for your previews using a Standard and a collection of Modules.
    ///
    /// This modifier can be used to configure Grove with a Standard a collection of Modules without declaring a ``GroveAppDelegate``.
    ///
    /// - Important: This modifier is only recommended for Previews. As it doesn't configure a ``GroveAppDelegate`` lifecycle handling
    ///     functionality, using ``LifecycleHandler``,  of modules is not fully supported. You may use the `simulateLifecycle`
    ///     parameter to simulate a call to ``LifecycleHandler/willFinishLaunchingWithOptions(_:launchOptions:)-8jatp``.
    ///
    /// - Parameters:
    ///   - standard: The global  ``Standard`` used throughout the app to manage global data flow.
    ///   - simulateLifecycle: Options to simulate behavior for ``LifecycleHandler``s. Disabled by default.
    ///   - modules: The ``Module``s used in the Grove project.
    /// - Returns: The configured view using the Grove framework.
    @MainActor
    public func previewWith<S: Standard>(
        standard: S,
        simulateLifecycle: LifecycleSimulationOptions = .disabled,
        @ModuleBuilder _ modules: () -> ModuleCollection
    ) -> AnyView {
        precondition(
            ProcessInfo.processInfo.isPreviewSimulator,
            "The Grove previewWith(standard:_:) modifier can only used within Xcode preview processes."
        )
        var storage = GroveStorage()
        if case let .launchWithOptions(options) = simulateLifecycle {
            storage[LaunchOptionsKey.self] = options
        }
        let grove = Grove(standard: standard, modules: modules().elements, storage: storage)
        return self
            .modifier(GroveViewModifier(grove))
            .task(grove.run)
#if os(iOS) || os(visionOS) || os(tvOS)
            .task { @MainActor in
                if case let .launchWithOptions(options) = simulateLifecycle {
                    (grove as any DeprecatedLaunchOptionsCall)
                        .callWillFinishLaunching(UIApplication.shared, launchOptions: options)
                }
            }
#endif
            .intoAnyView()
    }

    /// Configure Grove for your previews using a collection of Modules.
    ///
    /// This modifier can be used to configure Grove with a collection of Modules without declaring a ``GroveAppDelegate``.
    ///
    /// - Important: This modifier is only recommended for Previews. As it doesn't configure a ``GroveAppDelegate`` lifecycle handling
    ///     functionality, using ``LifecycleHandler``,  of modules is not fully supported. You may use the `simulateLifecycle`
    ///     parameter to simulate a call to ``LifecycleHandler/willFinishLaunchingWithOptions(_:launchOptions:)-8jatp``.
    ///
    /// - Parameters:
    ///   - simulateLifecycle: Options to simulate behavior for ``LifecycleHandler``s. Disabled by default.
    ///   - modules: The ``Module``s used in the Grove project.
    /// - Returns: The configured view using the Grove framework.
    @MainActor
    public func previewWith(
        simulateLifecycle: LifecycleSimulationOptions = .disabled,
        @ModuleBuilder _ modules: () -> ModuleCollection
    ) -> some View {
        previewWith(standard: DefaultStandard(), simulateLifecycle: simulateLifecycle, modules)
    }
    
    
    private func intoAnyView() -> AnyView {
        AnyView(self)
    }
}
#endif
