//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


extension Sequence {
    /// An asynchronous version of Swift's `Sequence.reduce(_:_:)` function.
    @available(*, deprecated, renamed: "reduceAsync(_:_:)", message: "Prefer the explicitly-async version to avoid overload resolution issues")
    @inlinable
    public func reduce<Result>(
        _ initialResult: Result,
        _ nextPartialResult: (Result, Element) async throws -> Result
    ) async rethrows -> Result {
        try await reduceAsync(initialResult, nextPartialResult)
    }
    
    /// An asynchronous version of Swift's `Sequence.reduce(into:_:)` function.
    @available(*, deprecated, renamed: "reduceAsync(into:_:)", message: "Prefer the explicitly-async version to avoid overload resolution issues")
    @inlinable
    public func reduce<Result>(
        into initial: Result,
        _ updateAccumulatingResult: (inout Result, Element) async throws -> Void
    ) async rethrows -> Result {
        try await reduceAsync(into: initial, updateAccumulatingResult)
    }
}
