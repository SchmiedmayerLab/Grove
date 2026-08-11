//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


extension KeyValuePairs {
    /// Creates a `KeyValuePairs` object, using the elements of a `Sequence`.
    /// - parameter seq: The Sequence whose elements should be used as the key-value pairs of the resulting `KeyValuePairs` instance.
    @inlinable
    public init<S: Sequence>(_ seq: S) where S.Element == (Key, Value) {
        let initFn = unsafeBitCast(Self.init(dictionaryLiteral:), to: (([S.Element]) -> Self).self)
        self = initFn(Array(seq))
    }
}
