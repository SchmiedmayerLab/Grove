//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Represents an LLM function calling parameter.
///
/// The ``LLMToolParameter``enables developers to manually specify the conformance of Swift types to the [OpenAI Function calling schema](https://platform.openai.com/docs/guides/function-calling). <!-- markdown-link-check-disable-line -->
/// However, the usage of ``LLMToolParameter`` should rarely be required as ``GroveLLMOpenAI`` automatically synthezises the OpenAI schema from the underlying primitive Swift types,
/// such as `Int`s, `Float`s, `Double`s, `Bool`s, and `String`s. Furthermore, `array`- or `enum`-based compositions of these type are automatically supported, similar to `Optional`s of these types.
///
/// The protocol enforces the ``LLMToolParameter/schema`` property that defines the OpenAI schema-based structure of the function calling arguments,
/// enabling developers full freedom over the defined schema.
///
/// > Warning: One cannot use the ``LLMToolParameter`` to nest OpenAI schema `object`s within `object`s, as the defining OpenAI schema language doesn't allow for that.
/// > In case your LLM function calling use case requires such functionality, please rethink your approach and try to simplify it.
///
/// # Usage
///
/// An example usage of the ``LLMToolParameter`` for a custom type looks like the following:
///
/// ```swift
/// /// Manual conformance to `LLMToolParameter` of a custom type.
/// extension Data: LLMToolParameter {
///     public static var schema: LLMToolParameterPropertySchema = {
///         guard let schema = try? LLMToolParameterPropertySchema(type: .string) else {
///             fatalError("Couldn't create function calling schema definition.")
///         }
///
///         return schema
///     }()
/// }
///
/// struct WeatherFunction: LLMTool {
///     @Parameter(description: "Random base64 coded data")
///     var customParameter: Data
///
///     func execute() async throws -> String? {
///         "..."
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMToolParameter: Decodable {
    static var schema: LLMToolParameterPropertySchema { get }
}
