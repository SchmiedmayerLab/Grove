//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Defines a collection of ``GroveLLMOpenAI`` ``LLMTool``s.
///
/// You can not create a `_LLMToolCollection` yourself. Please use the ``LLMOpenAISchema`` that internally creates a `_LLMToolCollection` with the passed ``LLMTool``s.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct _LLMToolCollection {  // swiftlint:disable:this type_name
    package let functions: [String: any LLMTool]

    package init(functions: [any LLMTool]) {
        self.functions = functions.reduce(into: [:]) {
            $0[$1.name] = $1
        }
    }

    /// Creates an empty `_LLMToolCollection`
    public init() {
        functions = [:]
    }
}
