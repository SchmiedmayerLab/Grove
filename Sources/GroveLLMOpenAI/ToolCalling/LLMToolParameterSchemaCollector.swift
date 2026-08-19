//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
package import GeneratedOpenAIClient
import GroveFoundation
import OpenAPIRuntime


/// An ``LLMTool`` that describes its own parameters rather than having them reflected out of `@Parameter`s.
///
/// Used by the `FoundationModels` compatibility layer, where the parameter schema comes from the tool's
/// `GenerationSchema`. Not intended for direct conformance.
@available(iOS 18, macOS 15, watchOS 11, *)
package protocol _LLMToolSchemaProviding: LLMTool { // swiftlint:disable:this type_name
    /// The function's parameter schema.
    var _schema: LLMTool.LLMToolParameterSchema { get throws } // swiftlint:disable:this identifier_name
}


/// Defines the `LLMToolParameterSchemaCollector/schema` requirement to collect the function calling parameter schema's from the ``LLMTool/Parameter``s.
///
/// Conformance of ``LLMTool/Parameter`` to `LLMToolParameterSchemaCollector` can be found in the declaration of
/// the ``LLMTool/Parameter``.
@available(iOS 18, macOS 15, watchOS 11, *)
protocol LLMToolParameterSchemaCollector: Sendable {
    var schema: LLMToolParameterItemSchema { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMTool {
    package typealias LLMToolParameterSchema = Components.Schemas.FunctionParameters
    var schemaValueCollectors: [String: any LLMToolParameterSchemaCollector] {
        retrieveProperties(ofType: (any LLMToolParameterSchemaCollector).self)
    }

    /// Aggregates the individual parameter schemas of all ``LLMTool/Parameter``s and combines them into the complete parameter schema of the ``LLMTool``.
    ///
    /// A function that already knows its own schema — one adapting a `FoundationModels` tool, say — supplies it
    /// through ``_LLMToolSchemaProviding`` instead of having it reflected out of `@Parameter` properties.
    @available(iOS 18, macOS 15, watchOS 11, *)
    package var schema: LLMToolParameterSchema {
        get throws {
            if let providing = self as? any _LLMToolSchemaProviding {
                return try providing._schema
            }
            let requiredPropertyNames = Array(
                parameterValueCollectors
                    .filter {
                        !$0.value.isOptional
                    }
                    .keys
            )

            let properties = schemaValueCollectors.compactMapValues { $0.schema }

            var functionParameterSchema: LLMToolParameterSchema = .init()
            do {
                functionParameterSchema.additionalProperties = try .init(
                    unvalidatedValue: [
                        "type": "object",
                        "properties": properties.mapValues { $0.value },
                        "required": requiredPropertyNames
                    ]
                )
            } catch {
                // Errors should be incredibly rare here
                Logger(subsystem: "org.grovealliance", category: "GroveLLMOpenAI")
                    .error("GroveLLMOpenAI: Error extracting the function call schema DSL into the `LLMToolParameterSchema`: \(error.localizedDescription).")
                throw LLMOpenAIError.toolCallSchemaExtractionError(error)
            }
            return functionParameterSchema
        }
    }
}
