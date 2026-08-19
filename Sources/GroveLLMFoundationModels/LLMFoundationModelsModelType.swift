//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FoundationModels


/// The Apple-provided model an ``LLMFoundationModelsSession`` runs against.
///
/// Both models are reached through the same `LanguageModel` protocol, so the only thing that changes between them is
/// where the inference happens — and, with it, what the model is capable of. Ask the platform for
/// ``LLMFoundationModelsPlatform/availability(of:)`` before offering one in the UI.
@available(iOS 27, macOS 27, visionOS 27, *)
public enum LLMFoundationModelsModelType: Sendable, Hashable, CaseIterable {
    /// The model that ships with the operating system, running entirely on device.
    ///
    /// Requires Apple Intelligence to be enabled on an eligible device, and nothing else — no account, no network.
    case onDevice
    /// Apple's server-side model, run in Private Cloud Compute.
    ///
    /// More capable than the on-device model and reasoning-capable, still without an account or an API key.
    case privateCloudCompute


    #if compiler(>=6.4)
    /// The `FoundationModels` model this case stands for.
    var languageModel: any LanguageModel {
        switch self {
        case .onDevice: SystemLanguageModel.default
        case .privateCloudCompute: PrivateCloudComputeLanguageModel()
        }
    }
    #endif

    /// Whether the model accepts images alongside the prompt.
    var supportsVision: Bool {
        #if compiler(>=6.4)
        languageModel.capabilities.contains(.vision)
        #else
        false
        #endif
    }
}
