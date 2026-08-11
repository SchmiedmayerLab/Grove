//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Grove
#if canImport(SwiftUI)
import SwiftUI


/// Configure and resolve the dependency tree for a collection of [`Module`](../Grove/Grove.docc/Module/Module.md)s.
///
/// This method can be used in unit test to resolve dependencies and properly initialize a set of Grove `Module`s.
///
/// - Parameters:
///   - standard: The Grove [`Standard`](../Grove/Grove.docc/Standard.md) to initialize.
///   - simulateLifecycle: Options to simulate behavior for [`LifecycleHandler`](../Grove/Grove.docc/Grove.md)s.
///   - modules: The collection of Modules that are configured.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
public func withDependencyResolution<S: Standard>(
    standard: S,
    simulateLifecycle: LifecycleSimulationOptions = .disabled,
    @ModuleBuilder _ modules: () -> ModuleCollection
) {
    var storage = GroveStorage()
    if case let .launchWithOptions(options) = simulateLifecycle {
        storage[LaunchOptionsKey.self] = options
    }

    let grove = Grove(standard: standard, modules: modules().elements, storage: storage)

#if os(iOS) || os(visionOS) || os(tvOS)
    if case let .launchWithOptions(options) = simulateLifecycle {
        // maintain backwards compatibility
        (grove as any DeprecatedLaunchOptionsCall)
            .callWillFinishLaunching(UIApplication.shared, launchOptions: options)
    }
#endif
}

/// Configure and resolve the dependency tree for a collection of [`Module`](../Grove/Grove.docc/Module/Module.md)s.
///
/// This method can be used in unit test to resolve dependencies and properly initialize a set of Grove `Module`s.
///
/// - Parameters:
///   - simulateLifecycle: Options to simulate behavior for [`LifecycleHandler`](../Grove/Grove.docc/Grove.md)s.
///   - modules: The collection of Modules that are configured.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
public func withDependencyResolution(
    simulateLifecycle: LifecycleSimulationOptions = .disabled,
    @ModuleBuilder _ modules: () -> ModuleCollection
) {
    withDependencyResolution(standard: DefaultStandard(), simulateLifecycle: simulateLifecycle, modules)
}
#else
/// Configure and resolve the dependency tree for a collection of [`Module`](../Grove/Grove.docc/Module/Module.md)s.
///
/// This method can be used in unit test to resolve dependencies and properly initialize a set of Grove `Module`s on non-Apple platforms.
///
/// - Parameters:
///   - modules: The collection of Modules that are configured.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
public func withDependencyResolution(
    @ModuleBuilder _ modules: () -> ModuleCollection
) {
    let storage = GroveStorage()
    _ = Grove(standard: DefaultStandard(), modules: modules().elements, storage: storage)
}
#endif
