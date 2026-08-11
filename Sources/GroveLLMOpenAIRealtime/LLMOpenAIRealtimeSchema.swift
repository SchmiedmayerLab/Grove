//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveChat
public import GroveLLM
public import GroveLLMOpenAI

/// Defines the type and configuration of the ``LLMOpenAIRealtimeSession``.
///
/// The ``LLMOpenAIRealtimeSchema`` is used as a configuration for the to-be-used Realtime OpenAI LLM. It contains all information necessary for the creation of an executable ``LLMOpenAIRealtimeSession``.
/// It is bound to a ``LLMOpenAIRealtimePlatform`` that is responsible for turning the ``LLMOpenAIRealtimeSchema`` to an ``LLMOpenAIRealtimeSession``.
///
/// - Tip: ``LLMOpenAIRealtimeSchema`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the OpenAI LLMs and external tools. For details, refer to `LLMFunction` and `LLMFunction/Parameter` from GroveLLMOpenAI or see [Function Calling](../GroveLLMOpenAI/GroveLLMOpenAI.docc/FunctionCalling.md).
///
/// - Tip: For more information, refer to the documentation of the `LLMSchema` from GroveLLM.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMOpenAIRealtimeSchema: LLMSchema, Sendable {
    public typealias Platform = LLMOpenAIRealtimePlatform

    let parameters: LLMOpenAIRealtimeParameters
    let functions: [String: any LLMFunction]
    public var injectIntoContext: Bool

    /// Creates an instance of the ``LLMOpenAIRealtimeSchema`` containing all necessary configuration for Realtime OpenAI LLM inference.
    ///
    /// - Parameters:
    ///    - parameters: Parameters of the Realtime OpenAI LLM client.
    ///    - injectIntoContext: Indicates if the ``LLMOpenAIRealtimeSession`` inference output (text and audio based inference), as well as user transcripts
    ///                         should automatically be inserted into the ``LLMOpenAIRealtimeSession/context``, defaults to `true`.
    ///    - functionsCollection: LLM Functions (tools) used for the OpenAI function calling mechanism.
    public init(
        parameters: LLMOpenAIRealtimeParameters,
        injectIntoContext: Bool = true,
        @LLMFunctionBuilder _ functionsCollection: () -> _LLMFunctionCollection = { _LLMFunctionCollection() }
    ) {
        self.parameters = parameters
        self.injectIntoContext = injectIntoContext
        self.functions = functionsCollection().functions
    }
}
