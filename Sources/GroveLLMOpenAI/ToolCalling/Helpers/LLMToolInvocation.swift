//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


/// The arguments one invocation of an ``LLMTool`` was given.
///
/// Arguments belong to the invocation rather than to the function. A function is registered once and shared by every
/// call the model makes to it, so anything written onto the function itself is written over by the next call — and a
/// model is free to request the same function several times in a single turn. Keeping the arguments here instead lets
/// any number of calls to one function run at the same time, each reading only what it was given.
@available(iOS 18, macOS 15, watchOS 11, *)
package struct LLMToolArguments: Sendable {
    /// The raw JSON the model produced, for a function that decodes its own arguments.
    package let payload: Data
    /// The decoded value for each `@Parameter`, keyed by the parameter it belongs to.
    private let values: [ObjectIdentifier: any Sendable]

    package init(payload: Data, values: [ObjectIdentifier: any Sendable] = [:]) {
        self.payload = payload
        self.values = values
    }

    /// The value bound to the given parameter, or `nil` when the model supplied none.
    func value<Value>(for parameter: AnyObject, as type: Value.Type) -> Value? {
        values[ObjectIdentifier(parameter)] as? Value
    }
}


/// The invocation the current task is running.
///
/// A task-local, so the arguments reach `execute()` — and any child task it spawns — without being stored anywhere
/// two invocations can both see.
@available(iOS 18, macOS 15, watchOS 11, *)
package enum LLMToolInvocation {
    @TaskLocal package static var arguments: LLMToolArguments?
}
