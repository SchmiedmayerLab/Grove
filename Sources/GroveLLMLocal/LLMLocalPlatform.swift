//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
#if MLX
public import Grove
import GroveFoundation
public import GroveLLM
import MLX
#if targetEnvironment(simulator)
import OSLog
#endif

/// LLM execution platform of an ``LLMLocalSchema``.
///
/// The ``LLMLocalPlatform`` turns a received ``LLMLocalSchema`` to an executable ``LLMLocalSession``.
/// Use ``LLMLocalPlatform/callAsFunction(with:)`` with an ``LLMLocalSchema`` parameter to get an executable ``LLMLocalSession`` that does the actual inference.
///
/// - Important: ``LLMLocalPlatform`` shouldn't be used directly but used via the `GroveLLM` `LLMRunner` that delegates the requests towards the ``LLMLocalPlatform``.
/// The `GroveLLM` `LLMRunner` must be configured with the ``LLMLocalPlatform`` within the Grove `Configuration`.
///
/// - Tip: For more information, refer to the documentation of the `LLMPlatform` from GroveLLM.
///
/// ### Usage
///
/// The example below demonstrates the setup of the ``LLMLocalPlatform`` within the Grove `Configuration`.
///
/// ```swift
/// class TestAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             LLMRunner {
///                 LLMLocalPlatform()
///             }
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public final class LLMLocalPlatform: LLMPlatform, DefaultInitializable {
    /// Configuration of the platform.
    public let configuration: LLMLocalPlatformConfiguration
    /// Queue that processed the LLM inference tasks in a structured concurrency manner.
    let queue: LLMInferenceQueue<String>


    @MainActor public var state: LLMPlatformState {
        self.queue.platformState
    }


    /// Creates an instance of the ``LLMLocalPlatform``.
    ///
    /// - Parameters:
    ///     - configuration: The configuration of the platform.
    public init(configuration: LLMLocalPlatformConfiguration) {
        self.configuration = configuration
        self.queue = LLMInferenceQueue(
            maxConcurrentTasks: 1,      // only one task at a time for local inference
            taskPriority: configuration.taskPriority
        )
    }
    
    /// Convenience initializer for the ``LLMLocalPlatform``.
    public convenience init() {
        self.init(configuration: .init())
    }
    
    public func configure() {
#if targetEnvironment(simulator)
        Logger(
            subsystem: "org.grovealliance",
            category: "LLMLocalPlatform"
        ).warning("GroveLLMLocal is only supported on physical devices. A mock session will be used instead.")
        
        Logger(
            subsystem: "org.grovealliance",
            category: "LLMLocalPlatform"
        ).warning("\(String(localized: "LLM_MLX_NOT_SUPPORTED_WORKAROUND", bundle: .module))")
#else
        if let cacheLimit = configuration.cacheLimit {
            MLX.GPU.set(cacheLimit: cacheLimit * 1024 * 1024)
        }
        if let memoryLimit = configuration.memoryLimit {
            MLX.GPU.set(memoryLimit: memoryLimit.limit, relaxed: memoryLimit.relaxed)
        }
#endif
    }

    public func run() async {
        do {
            // Run the LLM task queue
            try await self.queue.runQueue()
        } catch is CancellationError {
            // No-op, shutdown
        } catch {
            fatalError("Inconsistent state of the LLMLocalPlatform: \(error)")
        }
    }

    public func callAsFunction(with llmSchema: LLMLocalSchema) -> LLMLocalSession {
        LLMLocalSession(self, schema: llmSchema)
    }
    
    deinit {
        MLX.GPU.clearCache()
        self.queue.shutdown()   // Safeguard shutdown of queue (should happen upon `ServiceModule/run() cancellation)
    }
}
#endif
