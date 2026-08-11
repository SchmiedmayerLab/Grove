//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import RuntimeAssertions


/// An `Array`-like data structure that uses a user-defined total order to arrange its elements.
///
/// An  `OrderedArray`'s `Element` should be a type which is either fully immutable, or at least immutable w.r.t. the array's comparator.
/// The array does not observe changes within individual elements, and does not automatically re-arrange its elements.
///
/// - Note: The `OrderedArray` type intentionally does not conform to `Equatable` or `Hashable`.
///     The reason for this is that, while we can compare or hash the elements in the array, we cannot do the same with the array's
///     comparator (which is a function). If you want to compare the elements of two `OrderedArray`s, use `Sequence`'s `elementsEqual(_:)` function.
///
/// ## Topics
/// ### Initializers
/// - ``init(areInIncreasingOrder:)``
/// ### Invariant
/// - ``areInIncreasingOrder``
/// - ``checkInvariant()``
/// - ``withInvariantCheckingTemporarilyDisabled(_:)``
/// ### Finding Elements
/// - ``contains(_:)``
/// - ``firstIndex(of:)``
/// - ``search(for:)``
/// ### Mutating the OrderedArray
/// - ``insert(_:)``
/// - ``insert(contentsOf:)``
/// - ``remove(at:)``
/// - ``removeAll(keepingCapacity:)``
/// - ``removeFirstOccurrence(of:)``
/// - ``remove(contentsOf:)``
/// - ``removeAll(where:)``
/// ### Unsafe Operations
/// - ``unsafelyInsert(_:at:)``
/// - ``subscript(unsafe:)``
/// ### Other
/// - ``capacity``
public struct OrderedArray<Element> {
    /// The comparator used to determine the ordering between two `Element`s.
    /// - returns: `true` iff the first element comares less to the second one, `false` otherwise.
    public typealias Comparator = (Element, Element) -> Bool
    /// The ``OrderedArray``'s underlying storage type.
    public typealias Storage = [Element]
    
    /// The total order used to compare elements.
    /// When comparing two elements, it should return `true` if their ordering satisfies the relation, otherwise `false`.
    public let areInIncreasingOrder: Comparator
    
    private var storage: Storage {
        didSet {
            if shouldAssertInvariantAfterMutations {
                checkInvariant()
            }
        }
    }
    
    /// Whether the array should assert its invariant after every mutation
    var shouldAssertInvariantAfterMutations = true {
        didSet {
            if shouldAssertInvariantAfterMutations && !oldValue {
                checkInvariant()
            }
        }
    }
    
    
    /// The total number of elements that the array can contain without allocating new storage.
    public var capacity: Int {
        storage.capacity
    }
    
    
    /// Creates a new ``OrderedArray`` using the specified comparator.
    public init(areInIncreasingOrder: @escaping Comparator) {
        self.storage = []
        self.areInIncreasingOrder = areInIncreasingOrder
    }
    
    
    /// Allows multiple operations on the array, which might temporarily break the invariant, to run as a single transaction, during which invariant checking is temporarily disabled.
    /// - Note: The invariant must still be satisfied at the end of the mutations.
    public mutating func withInvariantCheckingTemporarilyDisabled<Result>(_ block: (inout Self) -> Result) -> Result {
        let prevValue = shouldAssertInvariantAfterMutations
        shouldAssertInvariantAfterMutations = false
        let retval = block(&self)
        shouldAssertInvariantAfterMutations = prevValue
        return retval
    }
    
    
    /// Checks that the array is ordered according to its invariant (i.e., the comparator).
    /// If the invariant is satisfied, this function will terminate execution.
    public func checkInvariant() {
        if !self.isSorted(by: areInIncreasingOrder) {
            preconditionFailure("'\(Self.self)' contains unordered elements!")
        }
    }
}


extension OrderedArray: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "OrderedArray(\(storage.description))"
    }
    
    public var debugDescription: String {
        "OrderedArray(\(storage.debugDescription))"
    }
}


// MARK: RandomAccessCollection

extension OrderedArray: RandomAccessCollection {
    public typealias Index = Storage.Index
    
    public var startIndex: Index {
        storage.startIndex
    }
    public var endIndex: Index {
        storage.endIndex
    }
    
    public func index(after idx: Index) -> Index {
        storage.index(after: idx)
    }
    
    /// We implement this function in order to have the default `Collection.firstIndex(of:)` operation
    /// take advantage of our invariant and binary-search based element lookup.
    public func _customIndexOfEquatableElement(_ element: Element) -> Index?? { // swiftlint:disable:this identifier_name
        Index??.some(firstIndex(of: element))
    }
    
    /// We implement this function in order to have the default `Collection.contains(_:)` operation
    /// take advantage of our invariant and binary-search based element lookup.
    public func _customContainsEquatableElement(_ element: Element) -> Bool? { // swiftlint:disable:this identifier_name discouraged_optional_boolean
        Bool?.some(firstIndex(of: element) != nil) // swiftlint:disable:this discouraged_optional_boolean
    }
    
    public subscript(position: Index) -> Element {
        storage[position]
    }
    
    /// Unsafely accesses the element at the specified position.
    ///
    /// This operation is unsafe, since it allows mutating the element, which may result in it no longer satisfying the invariant.
    ///
    /// - Important: The caller is responsible for ensuring that any changes made to the collection maintain the invariant.
    public subscript(unsafe position: Index) -> Element {
        get { storage[position] }
        set { storage[position] = newValue }
    }
}


// MARK: Insertion, Removal, Mutation, Other

extension OrderedArray {
    /// Inserts a new element into the ``OrderedArray``, at the correct position based on the array's comparator.
    /// - returns: The index at which the element was inserted.
    @discardableResult
    public mutating func insert(_ element: Element) -> Index {
        let insertionIdx: Index
        switch search(for: element) {
        case .found(let idx):
            insertionIdx = idx
        case .notFound(let idx):
            insertionIdx = idx
        }
        storage.insert(element, at: insertionIdx)
        return insertionIdx
    }
    
    /// Unsafely unserts a new element into the ``OrderedArray``, at the specified position.
    ///
    /// - parameter element: The value that should be added to the `OrderedArray`
    /// - parameter position: The index where the element should be placed.
    ///
    /// - Important: The caller is responsible for ensuring that any changes made to the collection maintain the invariant.
    public mutating func unsafelyInsert(_ element: Element, at position: Index) {
        storage.insert(element, at: position)
    }
    
    
    /// Inserts the elements of some other `Sequence` into the ``OrderedArray``, at their respective correct positions, based on the array's comparator.
    public mutating func insert(contentsOf sequence: some Sequence<Element>) {
        withInvariantCheckingTemporarilyDisabled { `self` in
            for element in sequence {
                self.insert(element)
            }
        }
    }
    
    /// Removes the element at the specified index from the array.
    /// - returns: The removed element.
    @discardableResult
    public mutating func remove(at index: Index) -> Element {
        storage.remove(at: index)
    }
    
    
    /// Removes all occurrences of the objects in `elements` from the array.
    /// - Note: if the array contains multiple occurrences of an element, all of them will be removed.
    public mutating func remove(contentsOf elements: some Sequence<Element>) where Element: Equatable {
        withInvariantCheckingTemporarilyDisabled { `self` in
            for element in elements {
                // In the case of removals, we also perform an O(n) search for the to-be-removed element,
                // as a fallback if the default binary search didn't yield a result.
                // This is requied because we might be removing an element whose "correct" position in the
                // array has changed, in which case we would not necessarily be able to find it via the normal search.
                // (E.g.: you have an array of objects ordered based on some property, and this property has changed for
                // some of the elements, and you now want to remove them from their current positions in response.)
                while let index = self.firstIndex(of: element) ?? self.indices.first(where: { self[$0] == element }) {
                    self.storage.remove(at: index)
                }
            }
        }
    }
    
    
    /// Removes from the array all elements which match the predicate
    public mutating func removeAll(where predicate: (Element) -> Bool) {
        withInvariantCheckingTemporarilyDisabled { `self` in
            self.storage.removeAll(where: predicate)
        }
    }
    
    
    /// Removes all elements from the array.
    public mutating func removeAll(keepingCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }
    
    
    /// Returns the first index of the specified element.
    public func firstIndex(of element: Element) -> Index? {
        switch search(for: element) {
        case .found(let idx):
            idx
        case .notFound:
            nil
        }
    }
    
    /// Determines whether the array contains the specified element.
    @inlinable
    public func contains(_ element: Element) -> Bool {
        firstIndex(of: element) != nil
    }
    
    /// Removes the first occurrence of the specified element, if applicable.
    /// - returns: the index from which the element was removed. `nil` if the element wasn't a member of the array.
    @discardableResult
    public mutating func removeFirstOccurrence(of element: Element) -> Index? {
        if let idx = firstIndex(of: element) {
            remove(at: idx)
            return idx
        } else {
            return nil
        }
    }
}


// MARK: Position Finding etc

extension OrderedArray {
    /// The result of searching the array for an element.
    public typealias SearchResult = BinarySearchIndexResult<Index>
    
    /// Searches the array for an element.
    public func search(for element: Element) -> SearchResult {
        binarySearchForIndex(of: element, using: compare)
    }
    
    /// Compares two elements based on the comparator, and returns a matching `ComparisonResult`.
    fileprivate func compare(_ lhs: Element, _ rhs: Element) -> ComparisonResult {
        if areInIncreasingOrder(lhs, rhs) {
            .orderedAscending
        } else if areInIncreasingOrder(rhs, lhs) {
            .orderedDescending
        } else {
            .orderedSame
        }
    }
}
