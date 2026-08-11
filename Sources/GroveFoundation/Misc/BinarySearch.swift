//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import enum Foundation.ComparisonResult


/// The result of a binary search looking for some element in a collection.
public enum BinarySearchIndexResult<Index> {
    /// The searched-for element was found in the collection, at the specified index.
    case found(Index)
    /// The searched-for element was not found in the collection, but if it were a member of the collection, it would belong at the specified index.
    case notFound(Index)
}

extension BinarySearchIndexResult: Equatable where Index: Equatable {}
extension BinarySearchIndexResult: Hashable where Index: Hashable {}
extension BinarySearchIndexResult: Sendable where Index: Sendable {}


extension Collection {
    /// Performs a binary search over the collection, determining the index of an element.
    /// - parameter element: The element to locate
    /// - parameter compare: Closure that gets called to determine how two `Element`s compare to each other.
    ///     The return value determines how the algorithm proceeds: if the closure returns `.orderedAscending` the search will continue to the left;
    ///     for `.orderedDescending` it will continue to the right.
    /// - Note: If the element is not in the collection (i.e., the `compare` closure never returns `.orderedSame`),
    ///     the algorithm will compute and return the index where the element should be, if it were to become a member of the collection.
    @inlinable
    public func binarySearchForIndex(
        of element: Element,
        using compare: (Element, Element) -> ComparisonResult
    ) -> BinarySearchIndexResult<Index> {
        binarySearchForIndex(in: startIndex..<endIndex, using: { compare(element, $0) })
    }
    
    /// Performs a binary search over the collection, determining the first index where a condition is true.
    /// - parameter compare: Closure that gets called to determine how two `Element`s compare to each other.
    ///     The return value determines how the algorithm proceeds: if the closure returns `.orderedAscending` the search will continue to the left;
    ///     for `.orderedDescending` it will continue to the right.
    ///     I.e., the closure should determine the to-be-found index's location, relative to the element it is passed in.
    /// - Note: If the element is not in the collection (i.e., the `compare` closure never returns `.orderedSame`),
    ///     the algorithm will compute and return the index where the element should be, if it were to become a member of the collection.
    @inlinable
    public func binarySearchFirstIndex(
        where compare: (Element) -> ComparisonResult
    ) -> BinarySearchIndexResult<Index> {
        binarySearchForIndex(in: startIndex..<endIndex, using: compare)
    }
    
    /// Performs a binary search over the collection, looking for the index of the specified element
    /// - parameter range: The range in which to look for the element.
    /// - parameter compare: Closure that gets called to determine how two `Element`s compare to each other.
    ///     The return value determines how the algorithm proceeds: if the closure returns `.orderedAscending` the search will continue to the left;
    ///     for `.orderedDescending` it will continue to the right.
    /// - Note: If the element is not in the collection (i.e., the `compare` closure never returns `.orderedSame`),
    ///     the algorithm will compute and return the index where the element should be, if it were to become a member of the collection.
    @usableFromInline
    internal func binarySearchForIndex(
        in range: Range<Index>,
        using compare: (Element) -> ComparisonResult
    ) -> BinarySearchIndexResult<Index> {
        guard let middle: Self.Index = middleIndex(of: range) else {
            return .notFound(range.upperBound)
        }
        switch compare(self[middle]) {
        case .orderedAscending: // lhs < rhs
            return binarySearchForIndex(in: range.lowerBound..<middle, using: compare)
        case .orderedDescending: // lhs > rhs
            return binarySearchForIndex(in: index(after: middle)..<range.upperBound, using: compare)
        case .orderedSame: // lhs == rhs
            return .found(middle)
        }
    }
    
    /// Computes, for a non-empty range over the collection, the middle of the range.
    /// If the range is empty, this function will return `nil`.
    private func middleIndex(of range: Range<Index>) -> Index? {
        guard !range.isEmpty else {
            return nil
        }
        let distance = self.distance(from: range.lowerBound, to: range.upperBound)
        let resultIdx = self.index(range.lowerBound, offsetBy: distance / 2)
        return resultIdx
    }
}
