//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Holds globally accessible runtime testing support configurations.
///
/// The ``RuntimeConfig`` stores configurations of the current runtime environment for testing support.
/// 
/// - Important: ``RuntimeConfig`` is only exposed as the [System Programming Interface (SPI)](https://blog.eidinger.info/system-programming-interfaces-spi-in-swift-explained)
/// target `TestingSupport`, therefore requiring to state the SPI target upon importing the `GroveFoundation` target via `@_spi(TestingSupport)`.
///
/// ### Usage
///
/// One is able to access the ``RuntimeConfig`` from the `TestingSupport` SPI target as shown below.
///
/// ```swift
/// // Import the entire target, including the `TestingSupport` SPI target.
/// @_spi(TestingSupport) import GroveFoundation
///
/// if RuntimeConfig.testMode { /* ... */ }
/// ```
///
/// As of Swift 5.8, one is able to only import the SPI target, without any other parts of the overall SPM target,
/// by setting the `-experimental-spi-only-imports` Swift compiler flag and using the `@_spiOnly` notation upon target import.
///
/// ```swift
/// // Import only the `TestingSupport` SPI target.
/// @_spiOnly import GroveFoundation
///
/// if RuntimeConfig.testMode { /* ... */ }
/// ```
@_spi(TestingSupport)
public struct RuntimeConfig: Sendable {
    public static let testMode: Bool = ProcessInfo.processInfo.arguments.contains("--testMode")
}
