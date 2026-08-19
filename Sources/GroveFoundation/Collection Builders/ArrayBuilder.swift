//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// An `ArrayBuilder<T>` is a result builder that constructs an `Array<T>`.
public typealias ArrayBuilder<T> = RangeReplaceableCollectionBuilder<[T]>

extension Array {
    /// Constructs a new array, using a result builder.
    @inlinable
    public init<E>(@ArrayBuilder<Element> build: () throws(E) -> Self) throws(E) {
        self = try build()
    }
}
