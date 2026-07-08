//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation


@available(iOS 17, macOS 14, visionOS 1, *)
protocol NilValueProtocol {
    func nilValue<Value>(_ value: Value.Type) -> Value
}

/// If injected type T of ``LLMFunction/Parameter`` is an `Optional`, enable the conformance of `nil` to static type T
@available(iOS 17, macOS 14, visionOS 1, *)
extension _LLMFunctionParameterWrapper: NilValueProtocol where T: AnyOptional {
    func nilValue<Value>(_ value: Value.Type) -> Value {
        guard let nilLiteral = T(nilLiteral: ()) as? Value else {
            fatalError(
            """
            Inconsistent code: Could not cast T to passed Value (which has to be T)
            """
            )
        }
        
        return nilLiteral
    }
}
