//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


/// Decodes one ``LLMTool/Parameter``'s value out of the arguments the model produced.
@available(iOS 18, macOS 15, watchOS 11, *)
protocol LLMToolParameterValueCollector {
    /// Indicates if the ``LLMTool/Parameter`` that retrieves the parameter value is optional.
    var isOptional: Bool { get }

    /// Decodes this parameter's value from its slice of the arguments.
    ///
    /// - Parameter data: JSON-based parameter data.
    func decodeValue(from data: Data) throws -> any Sendable
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper: LLMToolParameterValueCollector {
    var isOptional: Bool {
        // Only `Optional` conforms to `ExpressibleByNilLiteral`: https://developer.apple.com/documentation/swift/expressiblebynilliteral
        T.self is any ExpressibleByNilLiteral.Type
    }


    func decodeValue(from data: Data) throws -> any Sendable {
        try JSONDecoder().decode(T.self, from: data)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMTool {
    /// All ``LLMTool/Parameter``s conforming to `LLMToolParameterValueCollector`, mapped by their name.
    var parameterValueCollectors: [String: any LLMToolParameterValueCollector] {
        retrieveProperties(ofType: (any LLMToolParameterValueCollector).self)
    }


    /// Retrieves all ``LLMTool/Parameter``s (`@Parameter`s) including their name conforming to a certain `Value` from the ``LLMTool``.
    ///
    /// - Parameters:
    ///    - type: Specifies which type of ``LLMTool/Parameter``s should be retrieved.
    func retrieveProperties<Value>(ofType type: Value.Type) -> [String: Value] {
        let mirror = Mirror(reflecting: self)

        return mirror.children.reduce(into: [String: Value]()) { partialResult, child in
            guard let label = child.label?.dropFirst(), // Necessary to remove "_" from property wrapper value
                  let value = child.value as? Value else {
                return
            }

            partialResult[String(label)] = value
        }
    }

    /// Injects the requested function call argument from the LLM into the ``LLMTool``.
    ///
    /// - Parameters:
    ///    - parameterData: JSON-based parameter data of the ``LLMTool``.
    package func arguments(from parameterData: Data) throws -> LLMToolArguments {
        // A function that carries its own schema decodes the arguments itself; there are no `@Parameter`s to fill.
        guard !(self is any _LLMToolSchemaProviding) else {
            return LLMToolArguments(payload: parameterData)
        }
        let topLayerParameterData = try JSONDecoder().decode(
            LLMToolParameterIntermediary.self,
            from: parameterData
        ).topLayerJSONRepresentation

        var values: [ObjectIdentifier: any Sendable] = [:]
        for (propertyName, propertyValue) in parameterValueCollectors {
            guard let propertyData = topLayerParameterData[propertyName] else {
                // If optional property, tolerable that there isn't a value
                if propertyValue.isOptional {
                    continue
                }

                let missingCodingKey = LLMToolParameterCodingKey(stringValue: propertyName)

                throw DecodingError.keyNotFound(
                    missingCodingKey,
                    .init(
                        codingPath: [missingCodingKey],
                        debugDescription: "Mismatch between the defined values of the LLM Function and the requested values by the LLM"
                    )
                )
            }

            let parameter = propertyValue as AnyObject
            values[ObjectIdentifier(parameter)] = try propertyValue.decodeValue(from: propertyData)
        }
        return LLMToolArguments(payload: parameterData, values: values)
    }

    /// Runs the function with the given arguments in scope.
    ///
    /// Nothing is written to the function itself, so any number of invocations can run at once.
    package func execute(with arguments: LLMToolArguments) async throws -> String? {
        try await LLMToolInvocation.$arguments.withValue(arguments) {
            try await execute()
        }
    }
}
