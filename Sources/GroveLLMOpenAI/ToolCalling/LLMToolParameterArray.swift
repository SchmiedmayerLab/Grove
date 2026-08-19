//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import OpenAPIRuntime


/// Represents an LLM function calling parameter in the form of an `array` element.
///
/// The ``LLMToolParameterArrayElement``enables developers to manually specify the conformance of an array-based Swift type to the [OpenAI Function calling schema](https://platform.openai.com/docs/guides/function-calling). <!-- markdown-link-check-disable-line -->
/// However, the usage of ``LLMToolParameterArrayElement`` should rarely be required as ``GroveLLMOpenAI`` automatically synthezises the OpenAI schema from `array`-based types with primitive Swift types as elements.
///
/// The protocol enforces the ``LLMToolParameterArrayElement/itemSchema`` property that defines the OpenAI schema-based structure of array-based elements.
///
/// # Usage
///
/// An example usage of the ``LLMToolParameterArrayElement`` for a custom array type looks like the following:
///
/// ```swift
/// struct LLMOpenAIFunctionPerson: LLMTool {
///     /// Manual conformance to `LLMToolParameterArrayElement` of a custom array item type.
///     struct CustomArrayItemType: LLMToolParameterArrayElement {
///         static let itemSchema: LLMToolParameterItemSchema = {
///             guard let schema = try? LLMToolParameterItemSchema(
///                 .init(name: "firstName", type: .string, description: "The first name of the person"),
///                 .init(name: "lastName", type: .string, description: "The last name of the person")
///             ) else {
///                 fatalError("Couldn't create function calling schema definition.")
///             }
///
///             return schema
///         }()
///
///         let firstName: String
///         let lastName: String
///     }
///
///     // ...
///
///     @Parameter(description: "Persons which age is to be determined.")
///     var persons: [CustomArrayItemType]
///
///     func execute() async throws -> String? {
///         "..."
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMToolParameterArrayElement: Decodable {
    static var itemSchema: LLMToolParameterItemSchema { get }
}
