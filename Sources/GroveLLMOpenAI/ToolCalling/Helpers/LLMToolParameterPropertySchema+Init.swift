//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import OpenAPIRuntime


/// Convenience extension to initialize a simple object-type function calling schema definition.
@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMToolParameterPropertySchema {
    /// Initialize a simple, object-type ``LLMToolParameterPropertySchema``.
    /// - Parameter type: The type of the ``LLMToolParameterPropertySchema``.
    public init(type: Property.PropertyType) throws {
        try self.init(
            unvalidatedValue: [
                "type": type.rawValue
            ]
        )
    }
}
