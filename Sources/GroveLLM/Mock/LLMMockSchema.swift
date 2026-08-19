//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A mock ``LLMSchema``, used for testing purposes.
///
/// The ``LLMMockSchema`` is bound to the ``LLMMockPlatform``.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMMockSchema: LLMSchema {
    public typealias Platform = LLMMockPlatform
    
    public let injectIntoContext = false
    
    
    /// Initializer for the ``LLMMockSchema``.
    public init() {}
}
