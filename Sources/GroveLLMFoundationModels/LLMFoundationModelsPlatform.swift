//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FoundationModels
public import GroveLLM


/// Whether a model is ready to serve requests.
@available(iOS 27, macOS 27, visionOS 27, *)
public enum LLMFoundationModelsAvailability: Hashable, Sendable {
    /// The model can serve requests.
    case available
    /// The model cannot serve requests, for the given reason.
    case unavailable(UnavailableReason)

    /// Why a model cannot serve requests.
    public enum UnavailableReason: Hashable, Sendable {
        /// The device's hardware does not support the model.
        case deviceNotEligible
        /// The device supports the model, but Apple Intelligence has not been turned on.
        case appleIntelligenceNotEnabled
        /// The model is coming — assets are downloading, or the system is not ready yet.
        case modelNotReady
    }


    /// The error to surface for an unavailable model.
    var error: LLMFoundationModelsError? {
        switch self {
        case .available: nil
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        }
    }
}


/// Configures an ``LLMFoundationModelsPlatform``.
@available(iOS 27, macOS 27, visionOS 27, *)
public struct LLMFoundationModelsPlatformConfiguration: Sendable {
    /// The maximum number of inference tasks running at once.
    public let concurrentStreams: Int
    /// The task priority of the initiated LLM inference tasks.
    public let taskPriority: TaskPriority


    /// Creates an ``LLMFoundationModelsPlatformConfiguration``.
    ///
    /// - Parameters:
    ///   - concurrentStreams: The maximum number of inference tasks running at once. Defaults to `1`, matching the
    ///     single generation `FoundationModels` sessions serve at a time.
    ///   - taskPriority: The task priority of the initiated LLM inference tasks.
    public init(concurrentStreams: Int = 1, taskPriority: TaskPriority = .userInitiated) {
        self.concurrentStreams = concurrentStreams
        self.taskPriority = taskPriority
    }
}


/// Runs Apple `FoundationModels` LLMs within the Grove ecosystem.
///
/// Configure the platform in the Grove `Configuration`, then reach it through the `LLMRunner` with an
/// ``LLMFoundationModelsSchema``.
///
/// ### Usage
///
/// ```swift
/// class TestAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             LLMRunner {
///                 LLMFoundationModelsPlatform()
///             }
///         }
///     }
/// }
/// ```
@available(iOS 27, macOS 27, visionOS 27, *)
public final class LLMFoundationModelsPlatform: LLMPlatform {
    @MainActor
    private static var onDeviceAvailability: LLMFoundationModelsAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady): .unavailable(.modelNotReady)
        @unknown default: .unavailable(.modelNotReady)
        }
    }

    @MainActor
    private static var privateCloudComputeAvailability: LLMFoundationModelsAvailability {
        #if compiler(>=6.4)
        switch PrivateCloudComputeLanguageModel().availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .unavailable(.deviceNotEligible)
        case .unavailable(.systemNotReady): .unavailable(.modelNotReady)
        @unknown default: .unavailable(.modelNotReady)
        }
        #else
        .unavailable(.modelNotReady)
        #endif
    }

    /// Queue that processes the LLM inference tasks in a structured concurrency manner.
    let queue: LLMInferenceQueue<String>


    @MainActor public var state: LLMPlatformState {
        queue.platformState
    }


    /// Creates an ``LLMFoundationModelsPlatform``.
    ///
    /// - Parameter configuration: The configuration of the platform.
    public init(configuration: LLMFoundationModelsPlatformConfiguration = .init()) {
        self.queue = LLMInferenceQueue(
            maxConcurrentTasks: configuration.concurrentStreams,
            taskPriority: configuration.taskPriority
        )
    }


    /// Whether the given model can serve a request right now, and if not, why.
    ///
    /// Neither model is guaranteed to be there: the on-device model needs an eligible device with Apple Intelligence
    /// turned on, and Private Cloud Compute needs an eligible device and a reachable system service. Check before
    /// offering a model in the UI rather than discovering it on the first prompt.
    @MainActor
    public func availability(of modelType: LLMFoundationModelsModelType) -> LLMFoundationModelsAvailability {
        switch modelType {
        case .onDevice: Self.onDeviceAvailability
        case .privateCloudCompute: Self.privateCloudComputeAvailability
        }
    }

    public func run() async {
        do {
            try await queue.runQueue()
        } catch is CancellationError {
            // No-op, shutdown
        } catch {
            fatalError("Inconsistent state of the LLMFoundationModelsPlatform: \(error)")
        }
    }

    public func callAsFunction(with llmSchema: LLMFoundationModelsSchema) -> LLMFoundationModelsSession {
        LLMFoundationModelsSession(self, schema: llmSchema)
    }


    deinit {
        queue.shutdown()    // Safeguard shutdown of the queue (should happen upon `ServiceModule/run()` cancellation)
    }
}
