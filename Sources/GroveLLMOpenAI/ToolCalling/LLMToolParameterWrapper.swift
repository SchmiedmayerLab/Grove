//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
public import OpenAPIRuntime
import Synchronization


// NOTE: OpenAPIRuntime.OpenAPIObjectContainer is the underlying type for Components.Schemas.FunctionParameters.additionalProperties

/// Alias of the OpenAI `JSONSchema/Property` type, describing properties within an object schema.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMToolParameterPropertySchema = OpenAPIRuntime.OpenAPIObjectContainer
/// Alias of the OpenAI `JSONSchema/Item` type, describing array items within an array schema.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMToolParameterItemSchema = OpenAPIRuntime.OpenAPIObjectContainer


/// Refer to the documentation of ``LLMTool/Parameter`` for information on how to use the `@Parameter` property wrapper.
@propertyWrapper
@available(iOS 18, macOS 15, watchOS 11, *)
public final class _LLMToolParameterWrapper<T: Decodable & Sendable>: LLMToolParameterSchemaCollector { // swiftlint:disable:this type_name
    let schema: LLMToolParameterItemSchema

    /// The value the invocation running on this task was given.
    ///
    /// Read from the invocation rather than from this object, so that concurrent calls to one function never see
    /// each other's arguments. An absent value means the model omitted the parameter, which only an optional one
    /// may be.
    public var wrappedValue: T {
        if let value = LLMToolInvocation.arguments?.value(for: self, as: T.self) {
            return value
        }
        if let optional = self as? any NilValueProtocol {
            return optional.nilValue(T.self)   // Indirection needed to return nil as the static type T
        }
        fatalError("""
        Tried to access @Parameter for value [\(T.self)] outside of an invocation that supplied it. \
        A `@Parameter` only carries a value while the `LLMTool/execute()` it belongs to is running.
        """)
    }


    /// Creates an ``LLMTool/Parameter`` which contains a custom-defined type that conforms to ``LLMToolParameter``.
    ///
    /// The custom-defined type needs to implement the ``LLMToolParameter`` protocol which mandates the implementation of the
    /// ``LLMToolParameter/schema`` property, describing the JSON schema of the property necessary for OpenAI.
    ///
    /// More documentation about parameters that are supported by OpenAI can be found here: https://json-schema.org/draft-07/json-schema-validation
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    @_disfavoredOverload
    public convenience init(description _: some StringProtocol) where T: LLMToolParameter {
        self.init(schema: T.schema)
    }

    init(schema: LLMToolParameterItemSchema) {
        self.schema = schema
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMTool {
    /// Defines parameters within an ``LLMTool``.
    ///
    /// The `@Parameter` property wrapper (``LLMTool/Parameter``) can be used within an ``LLMTool`` to declare that the function takes a number of arguments of specific type.
    /// As the function is called by the LLM, the function parameters that are sent by the LLM are automatically injected into the ``LLMTool`` by ``GroveLLMOpenAI``.
    ///
    /// The wrapper contains various initializers for the respective wrapped types of the parameter, such as `Int`, `Float`, `Double`, `Bool` or `String`, as well as `Optional`, `array`, and `enum` data types.
    /// For these types, ``GroveLLMOpenAI`` is able to automatically synthezise the OpenAI function parameter schema from the declared ``LLMTool/Parameter``s.
    ///
    /// > Tip: In case developers want to manually define schema's for custom and complex types, please refer to ``LLMToolParameter``, ``LLMToolParameterEnum``, and ``LLMToolParameterArrayElement``.
    ///
    /// # Usage
    ///
    /// The example below demonstrates a simple use case of an ``LLMTool/Parameter`` within a ``LLMTool``.
    ///
    /// ```swift
    /// struct WeatherFunction: LLMTool {
    ///     @Parameter(description: "The city and state of the to be determined weather, e.g. San Francisco, CA")
    ///     var location: String
    ///
    ///     func execute() async throws -> String? {
    ///         "The weather at \(location) is 30 degrees"
    ///     }
    /// }
    /// ```
    public typealias Parameter<WrappedValue> =
        _LLMToolParameterWrapper<WrappedValue> where WrappedValue: Decodable
}
