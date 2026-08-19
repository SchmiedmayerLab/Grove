//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
protocol NilValueProtocol {
    func nilValue<Value>(_ value: Value.Type) -> Value
}

/// If injected type T of ``LLMTool/Parameter`` is an `Optional`, enable the conformance of `nil` to static type T
@available(iOS 18, macOS 15, watchOS 11, *)
extension _LLMToolParameterWrapper: NilValueProtocol where T: AnyOptional {
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
