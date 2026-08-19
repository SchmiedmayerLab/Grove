//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper {
    /// Shared helper to build an `object` schema whose values are of the given JSON-Schema `type`.
    ///
    /// - Parameters:
    ///   - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///   - const: Specifies the constant `String`-based value of a certain parameter.
    ///   - valueType: The JSON-Schema type of the dictionary value
    ///                (e.g. `"integer"`, `"number"`, `"boolean"`, `"string"`).
    private convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)?,
        valueType: LLMToolParameterItemSchema.Property.PropertyType
    ) {
        do {
            try self.init(schema: .init(unvalidatedValue: [
                "type": "object",
                "description": String(description),
                "properties": [:] as [String: any Sendable],
                "const": const.map { String($0) } as (any Sendable)?,
                "additionalProperties": ["type": valueType.rawValue]
            ].compactingAbsentValues()))
        } catch {
            fatalError(
              "GroveLLMOpenAI: Failed to create validated function call schema definition of `LLMTool/Parameter`: \(error)"
            )
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: ExpressibleByDictionaryLiteral,
                                             T.Key: StringProtocol & Hashable,
                                             T.Value: BinaryInteger {
    /// Declares a ``LLMTool/Parameter``  of type `object`
    /// representing a dictionary with `String`-based keys and `Int`-based values.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil
    ) {
        self.init(description: description, const: const, valueType: .integer)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: ExpressibleByDictionaryLiteral,
                                             T.Key: StringProtocol & Hashable,
                                             T.Value: BinaryFloatingPoint {
    /// Declares a ``LLMTool/Parameter``  of type `object`
    /// representing a dictionary with `String`-based keys and `Float` or `Double` (`BinaryFloatingPoint`) -based values.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil
    ) {
        self.init(description: description, const: const, valueType: .number)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: ExpressibleByDictionaryLiteral,
                                             T.Key: StringProtocol & Hashable,
                                             T.Value == Bool {
    /// Declares a ``LLMTool/Parameter``  of type `object`
    /// representing a dictionary with `String`-based keys and `boolean` values.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil
    ) {
        self.init(description: description, const: const, valueType: .boolean)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: ExpressibleByDictionaryLiteral,
                                             T.Key: StringProtocol & Hashable,
                                             T.Value: StringProtocol {
    /// Declares a ``LLMTool/Parameter``  of type `object`
    /// representing a dictionary with `String`-based keys and `String`-based values.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    ///    - pattern: A Regular Expression that the keys of the objects needs to conform to.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil
    ) {
        self.init(description: description, const: const, valueType: .string)
    }
}
