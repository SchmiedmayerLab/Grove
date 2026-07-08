//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
#if canImport(SwiftUI)
import SwiftUI


/// Configure and resolve the dependency tree for a collection of [`Module`](../Spezi/Spezi.docc/Module/Module.md)s.
///
/// This method can be used in unit test to resolve dependencies and properly initialize a set of Spezi `Module`s.
///
/// - Parameters:
///   - standard: The Spezi [`Standard`](../Spezi/Spezi.docc/Standard.md) to initialize.
///   - simulateLifecycle: Options to simulate behavior for [`LifecycleHandler`](../Spezi/Spezi.docc/Spezi.md)s.
///   - modules: The collection of Modules that are configured.
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
@MainActor
public func withDependencyResolution<S: Standard>(
    standard: S,
    simulateLifecycle: LifecycleSimulationOptions = .disabled,
    @ModuleBuilder _ modules: () -> ModuleCollection
) {
    var storage = SpeziStorage()
    if case let .launchWithOptions(options) = simulateLifecycle {
        storage[LaunchOptionsKey.self] = options
    }

    let spezi = Spezi(standard: standard, modules: modules().elements, storage: storage)

#if os(iOS) || os(visionOS) || os(tvOS)
    if case let .launchWithOptions(options) = simulateLifecycle {
        // maintain backwards compatibility
        (spezi as any DeprecatedLaunchOptionsCall)
            .callWillFinishLaunching(UIApplication.shared, launchOptions: options)
    }
#endif
}

/// Configure and resolve the dependency tree for a collection of [`Module`](../Spezi/Spezi.docc/Module/Module.md)s.
///
/// This method can be used in unit test to resolve dependencies and properly initialize a set of Spezi `Module`s.
///
/// - Parameters:
///   - simulateLifecycle: Options to simulate behavior for [`LifecycleHandler`](../Spezi/Spezi.docc/Spezi.md)s.
///   - modules: The collection of Modules that are configured.
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
@MainActor
public func withDependencyResolution(
    simulateLifecycle: LifecycleSimulationOptions = .disabled,
    @ModuleBuilder _ modules: () -> ModuleCollection
) {
    withDependencyResolution(standard: DefaultStandard(), simulateLifecycle: simulateLifecycle, modules)
}
#else
/// Configure and resolve the dependency tree for a collection of [`Module`](../Spezi/Spezi.docc/Module/Module.md)s.
///
/// This method can be used in unit test to resolve dependencies and properly initialize a set of Spezi `Module`s on non-Apple platforms.
///
/// - Parameters:
///   - modules: The collection of Modules that are configured.
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
@MainActor
public func withDependencyResolution(
    @ModuleBuilder _ modules: () -> ModuleCollection
) {
    let storage = SpeziStorage()
    _ = Spezi(standard: DefaultStandard(), modules: modules().elements, storage: storage)
}
#endif
