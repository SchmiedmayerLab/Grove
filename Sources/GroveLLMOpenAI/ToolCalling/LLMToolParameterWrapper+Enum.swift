//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation

// swiftlint:disable discouraged_optional_boolean

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: LLMToolParameterEnum, T.RawValue: StringProtocol {
    /// Declares an `enum`-based ``LLMTool/Parameter`` defining all options of a text-based parameter of the
    /// ``LLMTool``.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil
    ) {
        do {
            try self.init(schema: .init(unvalidatedValue: [
                "type": "string",
                "description": String(description),
                "const": const.map { String($0) } as (any Sendable)?,
                "enum": T.allCases.map { String($0.rawValue) }
            ].compactingAbsentValues()))
        } catch {
            fatalError("GroveLLMOpenAI: Failed to create validated function call schema definition of `LLMTool/Parameter`: \(error)")
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: AnyOptional, T.Wrapped: LLMToolParameterEnum,
    T.Wrapped.RawValue: StringProtocol {
    /// Declares an optional `enum`-based ``LLMTool/Parameter`` defining all options of a text-based parameter of
    /// the ``LLMTool``.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil
    ) {
        do {
            try self.init(schema: .init(unvalidatedValue: [
                "type": "string",
                "description": String(description),
                "const": const.map { String($0) } as (any Sendable)?,
                "enum": T.Wrapped.allCases.map { String($0.rawValue) }
            ].compactingAbsentValues()))
        } catch {
            fatalError("GroveLLMOpenAI: Failed to create validated function call schema definition of `LLMTool/Parameter`: \(error)")
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: AnyArray, T.Element: LLMToolParameterEnum,
    T.Element.RawValue: StringProtocol {
    /// Declares an `enum`-based ``LLMTool/Parameter`` `array`. An individual `array` element defines all options of
    /// a text-based parameter of the ``LLMTool``.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    ///    - minItems: Defines the minimum amount of values in the `array`.
    ///    - maxItems: Defines the maximum amount of values in the `array`.
    ///    - uniqueItems: Specifies if all `array` elements need to be unique.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil
    ) {
        do {
            try self.init(schema: .init(unvalidatedValue: [
                "type": "array",
                "description": String(description),
                "items": [
                    "type": "string",
                    "const": const.map { String($0) } as (any Sendable)?,
                    "enum": T.Element.allCases.map { String($0.rawValue) }
                ].compactingAbsentValues(),
                "minItems": minItems as (any Sendable)?,
                "maxItems": maxItems as (any Sendable)?,
                "uniqueItems": uniqueItems
            ].compactingAbsentValues()))
        } catch {
            fatalError("GroveLLMOpenAI: Failed to create validated function call schema definition of `LLMTool/Parameter`: \(error)")
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper where T: AnyOptional,
    T.Wrapped: AnyArray,
    T.Wrapped.Element: LLMToolParameterEnum,
    T.Wrapped.Element.RawValue: StringProtocol {
    /// Declares an optional `enum`-based ``LLMTool/Parameter`` `array`. An individual `array` element defines all
    /// options of a text-based parameter of the ``LLMTool``.
    ///
    /// - Parameters:
    ///    - description: Describes the purpose of the parameter, used by the LLM to grasp the purpose of the parameter.
    ///    - const: Specifies the constant `String`-based value of a certain parameter.
    ///    - minItems: Defines the minimum amount of values in the `array`.
    ///    - maxItems: Defines the maximum amount of values in the `array`.
    ///    - uniqueItems: Specifies if all `array` elements need to be unique.
    public convenience init(
        description: some StringProtocol,
        const: (any StringProtocol)? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil
    ) {
        do {
            try self.init(schema: .init(unvalidatedValue: [
                "type": "array",
                "description": String(description),
                "items": [
                    "type": "string",
                    "const": const.map { String($0) } as (any Sendable)?,
                    "enum": T.Wrapped.Element.allCases.map { String($0.rawValue) }
                ],
                "minItems": minItems as (any Sendable)?,
                "maxItems": maxItems as (any Sendable)?,
                "uniqueItems": uniqueItems as (any Sendable)?
            ].compactingAbsentValues()))
        } catch {
            fatalError("GroveLLMOpenAI: Failed to create validated function call schema definition of `LLMTool/Parameter`: \(error)")
        }
    }
}

// swiftlint:enable discouraged_optional_boolean
