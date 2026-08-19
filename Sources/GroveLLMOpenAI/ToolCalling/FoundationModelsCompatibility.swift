//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(FoundationModels)
import Foundation
public import FoundationModels
import OpenAPIRuntime
import Synchronization


/// Failures specific to bridging a `FoundationModels` tool onto an ``LLMTool``.
@available(iOS 26, macOS 26, visionOS 26, *)
enum LLMFoundationModelsCompatibilityError: Error {
    /// The tool's `GenerationSchema` did not encode to a JSON object.
    case schemaIsNotAnObject
}


/// Presents a `FoundationModels` tool as an ``LLMTool``.
///
/// Grove's own ``LLMTool`` DSL remains the primary way to define a function — it takes its parameter schema from
/// `@Parameter` properties and gets dependencies injected the way the rest of Grove does. This type exists so that a
/// tool already written against `FoundationModels` can be handed to a Grove schema unchanged, and so that the same
/// tool can serve both an on-device `FoundationModels` session and a remote model.
///
/// Reach for it through ``FoundationModels/Tool/asLLMTool()`` rather than naming it directly.
@available(iOS 26, macOS 26, visionOS 26, *)
public struct LLMFoundationModelsTool<WrappedTool: Tool>: LLMTool, _LLMToolSchemaProviding {
    private let tool: WrappedTool

    public var name: String { tool.name }
    public var description: String { tool.description }

    package var _schema: LLMTool.LLMToolParameterSchema { // swiftlint:disable:this identifier_name
        get throws {
            // `GenerationSchema` is `Codable` and encodes as JSON Schema, which is exactly what the function-calling
            // request wants — so it round-trips rather than being translated field by field.
            let encoded = try JSONEncoder().encode(tool.parameters)
            guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: any Sendable] else {
                throw LLMOpenAIError.toolCallSchemaExtractionError(
                    LLMFoundationModelsCompatibilityError.schemaIsNotAnObject
                )
            }
            var schema = LLMTool.LLMToolParameterSchema()
            schema.additionalProperties = try .init(unvalidatedValue: object)
            return schema
        }
    }


    /// Wraps the given tool.
    public init(_ tool: WrappedTool) {
        self.tool = tool
    }


    public func execute() async throws -> String? {
        // The arguments come from the invocation, so nothing about this type is written to between calls.
        let argumentData = LLMToolInvocation.arguments?.payload ?? Data("{}".utf8)
        let content = try GeneratedContent(json: String(decoding: argumentData, as: UTF8.self))
        let output = try await tool.call(arguments: try WrappedTool.Arguments(content))
        // `Tool.Output` is `PromptRepresentable`; a `String` output is by far the common case and passes through
        // unchanged, while anything else is described rather than dropped.
        return output as? String ?? String(describing: output)
    }
}


@available(iOS 26, macOS 26, visionOS 26, *)
extension Tool {
    /// Presents this tool as an ``LLMTool``, so that it can be handed to a Grove LLM schema.
    ///
    /// ```swift
    /// let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt5_6)) {
    ///     GetWeather().asLLMTool()
    /// }
    /// ```
    public func asLLMTool() -> LLMFoundationModelsTool<Self> {
        LLMFoundationModelsTool(self)
    }
}


#endif
