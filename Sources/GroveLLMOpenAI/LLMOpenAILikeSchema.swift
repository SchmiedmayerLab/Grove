//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import GroveLLM


/// Defines the type and configuration of the ``LLMOpenAISession``.
///
/// The ``LLMOpenAISchema`` is used as a configuration for the to-be-used OpenAI LLM. It contains all information necessary for the creation of an executable ``LLMOpenAISession``.
/// It is bound to a ``LLMOpenAIPlatform`` that is responsible for turning the ``LLMOpenAISchema`` to an ``LLMOpenAISession``.
///
/// - Tip: ``LLMOpenAISchema`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the OpenAI LLMs and external tools. For details, refer to ``LLMTool`` and ``LLMTool/Parameter`` or the <doc:ToolCalling> DocC article.
///
/// - Tip: For more information, refer to the documentation of the `LLMSchema` from GroveLLM.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMOpenAILikeSchema<PlatformDefinition: LLMOpenAILikePlatformDefinition>: LLMSchema, Sendable {
    public typealias Platform = LLMOpenAILikePlatform<PlatformDefinition>
    
    let parameters: LLMOpenAILikeParameters<PlatformDefinition>
    let modelParameters: LLMOpenAIModelParameters
    let functions: [String: any LLMTool]
    /// Whether the model may search the web to answer.
    public let searchesTheWeb: Bool
    /// Whether the model may draw images in its answer.
    public let generatesImages: Bool
    public let injectIntoContext: Bool
    
    
    /// Creates an instance of the ``LLMOpenAISchema`` containing all necessary configuration for OpenAI LLM inference.
    ///
    /// - Parameters:
    ///    - parameters: Parameters of the OpenAI LLM client.
    ///    - modelParameters: Parameters of the used OpenAI LLM.
    ///    - injectIntoContext: Indicates if the inference output by the ``LLMOpenAISession`` should automatically be inserted into the ``LLMOpenAILikeSession/context``, defaults to false.
    ///    - searchesTheWeb: Lets the model search the web and cite what it finds, defaults to `false`.
    ///     Searching costs more and sends the query to the provider's search infrastructure, so it is asked for
    ///     rather than assumed. Only the Responses API serves it — see ``LLMOpenAIAPIMode``.
    ///    - generatesImages: Lets the model draw images, which arrive in the context as assistant messages,
    ///     defaults to `false`. Only models whose ``LLMOpenAILikePlatformModelType/supportsImageGeneration``
    ///     is `true` take the tool; for all others the request goes out without it.
    ///    - functions: The tools offered to the model.
    public init(
        parameters: LLMOpenAILikeParameters<PlatformDefinition>,
        modelParameters: LLMOpenAIModelParameters = .init(),
        injectIntoContext: Bool = false,
        searchesTheWeb: Bool = false,
        generatesImages: Bool = false,
        @LLMToolBuilder _ functions: () -> _LLMToolCollection = { _LLMToolCollection() }
    ) {
        self.parameters = parameters
        self.modelParameters = modelParameters
        self.injectIntoContext = injectIntoContext
        self.searchesTheWeb = searchesTheWeb
        self.generatesImages = generatesImages
        self.functions = functions().functions
    }
}
