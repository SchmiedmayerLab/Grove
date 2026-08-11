//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


extension Sequence {
    /// Returns the elements of the sequence, sorted using the given array of existential `SortComparator`s to compare elements.
    ///
    /// - Note: This function exists as an alternative to Foundation's `sorted(using:)` implementation, for the case where the comparators are of heterogeneous types.
    ///
    /// - parameter comparators: a sequence of comparators used to compare elements.
    ///     The first comparator specifies the primary comparator to be used in
    ///     sorting the sequence's elements. Any subsequent comparators are used
    ///     to further refine the order of elements with equal values.
    /// - returns: an array of the elements sorted using `comparators`.
    @_disfavoredOverload
    @inlinable
    public func sorted(using comparators: some Sequence<any SortComparator<Element>>) -> [Element] {
        var copy = Array(self)
        copy.sort(using: comparators)
        return copy
    }
}


extension MutableCollection where Self: RandomAccessCollection {
    /// Sorts the collection using the given array of existential `SortComparator`s to compare elements.
    ///
    /// - Note: This function exists as an alternative to Foundation's `sort(using:)` implementation, for the case where the comparators are of heterogeneous types.
    ///
    /// - parameter comparators: a sequence of comparators used to compare elements.
    ///     The first comparator specifies the primary comparator to be used in
    ///     sorting the sequence's elements. Any subsequent comparators are used
    ///     to further refine the order of elements with equal values.
    @_disfavoredOverload
    @inlinable
    public mutating func sort(using comparators: some Sequence<any SortComparator<Element>>) {
        self.sort { lhs, rhs in
            comparators.compare(lhs, rhs) == .orderedAscending
        }
    }
}


extension Sequence {
    @inlinable
    func compare<Compared>(
        _ lhs: Compared,
        _ rhs: Compared
    ) -> ComparisonResult where Element == any SortComparator<Compared> {
        for comparator in self {
            let result = comparator.compare(lhs, rhs)
            switch result {
            case .orderedAscending, .orderedDescending:
                return result
            case .orderedSame:
                continue
            }
        }
        // all compared equal
        return .orderedSame
    }
}
