//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import FoundationModels
public import GroveLLM


/// Configures an Apple `FoundationModels` LLM.
///
/// ### Usage
///
/// ```swift
/// let schema = LLMFoundationModelsSchema(
///     modelType: .onDevice,
///     systemPrompt: "You're a helpful assistant that answers questions from users."
/// )
/// ```
@available(iOS 27, macOS 27, visionOS 27, *)
public struct LLMFoundationModelsSchema: LLMSchema {
    public typealias Platform = LLMFoundationModelsPlatform

    /// The Apple-provided model the session runs against.
    public let modelType: LLMFoundationModelsModelType
    /// The instructions handed to the model, which `FoundationModels` keeps outside the conversation itself.
    public let systemPrompt: String?
    /// Sampling and length options for every response.
    public let generationOptions: GenerationOptions

    public let injectIntoContext: Bool


    /// Creates an ``LLMFoundationModelsSchema``.
    ///
    /// - Parameters:
    ///   - modelType: The Apple-provided model to run against. Defaults to the on-device model.
    ///   - systemPrompt: Instructions that shape the model's behaviour.
    ///   - generationOptions: Sampling and length options, defaulting to the model's own.
    ///   - injectIntoContext: Whether the generated output is written back into the session's `LLMContext`.
    public init(
        modelType: LLMFoundationModelsModelType = .onDevice,
        systemPrompt: String? = nil,
        generationOptions: GenerationOptions = GenerationOptions(),
        injectIntoContext: Bool = false
    ) {
        self.modelType = modelType
        self.systemPrompt = systemPrompt
        self.generationOptions = generationOptions
        self.injectIntoContext = injectIntoContext
    }
}
