//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Represents LLM function calling parameters in the shape of an `String`-based `enum`.
///
/// In order to map a `String`-based Swift `enum` to a function calling parameter, developers must conform `enum`s to the ``LLMToolParameterEnum`` protocol.
/// This enables ``GroveLLMOpenAI`` to automatically synthezise the OpenAI function calling schema from the `String`-based `enum`.
///
/// > Important: The developer-defined `enum` has to have a `RawValue` of type `String`.
///
/// The ``LLMToolParameterEnum`` enforces conformance to the following protocols, ensuring that all `enum` cases can be iterated over and
/// represented by a raw type, as well as the ability to decode the `enum` from `Data`: `CaseIterable`, `RawRepresentable`, and `Decodable`.
///
/// # Usage
///
/// An example usage of the ``LLMToolParameterEnum`` for a `String`-based `enum`  type:
///
/// ```swift
/// struct LLMOpenAIFunctionWeather: LLMTool {
///     /// Manual conformance to `LLMToolParameterEnum`.
///     enum TemperatureUnit: String, LLMToolParameterEnum {
///         case celsius
///         case fahrenheit
///     }
///
///     // ...
///
///     @Parameter(description: "The unit of the temperature")
///     var unit: TemperatureUnit
///
///
///     func execute() async throws -> String? {
///         "..."
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMToolParameterEnum: CaseIterable, RawRepresentable, Decodable {}
